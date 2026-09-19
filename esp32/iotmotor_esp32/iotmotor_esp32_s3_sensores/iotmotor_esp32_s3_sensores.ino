/* IoTMotor — ESP32-S3 (esp32-02): somente sensores, SEM acionamento.
 * Este sketch pressupoe MPU6050 (SDA GPIO5, SCL GPIO9) e DS18B20
 * (DQ GPIO4, resistor pull-up 4k7 a 3V3), como no projeto de dois modulos.
 * Confirme os pinos da SUA placa S3 antes de gravar. Sensores reais por padrao:
 * campos invalidos sao omitidos; nao inventamos temperatura ou vibracao.
 * O RMS de vibracao e estimativa da aceleracao dinamica em g; nao e mm/s.
 * Bibliotecas: PubSubClient, ArduinoJson 6.x, OneWire, DallasTemperature.
 * Broker publico: nao enviar senhas ou dados confidenciais; sem comandos.
 */
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <math.h>
#include "mqtt_websocket_client.h"
#define OTA_ARQUIVO "esp32-02.bin"
#define PORTAL_NOME "IoTMotor-esp32-02"
constexpr uint16_t PORTAL_SEGUNDOS = 180;
#include "ota_update.h"
#include "wifi_portal.h"

// Rede local: crie wifi_local.h na pasta do sketch (fora do Git) a partir de
// wifi_local.exemplo.h para usar outra rede sem publicar a senha no GitHub.
#if __has_include("wifi_local.h")
#include "wifi_local.h"
#endif
#ifndef WIFI_SSID_LOCAL
#define WIFI_SSID_LOCAL "IFMA_IOT"
#define WIFI_PASSWORD_LOCAL ""  // Wi-Fi aberto
#endif
// Redes de wifi_local.h: so semeiam a lista gravada na placa no primeiro boot.
// Depois, a lista e a ordem sao definidas pela aba "Wi-Fi" do painel.
const char* const REDES_INICIAIS[]={
  WIFI_SSID_LOCAL,
#ifdef WIFI_SSID_2
  WIFI_SSID_2,
#endif
#ifdef WIFI_SSID_3
  WIFI_SSID_3,
#endif
#ifdef WIFI_SSID_4
  WIFI_SSID_4,
#endif
};
const char* const SENHAS_INICIAIS[]={
  WIFI_PASSWORD_LOCAL,
#ifdef WIFI_SSID_2
  WIFI_PASSWORD_2,
#endif
#ifdef WIFI_SSID_3
  WIFI_PASSWORD_3,
#endif
#ifdef WIFI_SSID_4
  WIFI_PASSWORD_4,
#endif
};
static const char* MQTT_HOST = "test.mosquitto.org";
static const uint16_t MQTT_PORT = 8080;  // MQTT sobre WebSocket: a IFMA_IOT bloqueia 1883/8883
static const char* TOPIC_PREFIX = "iotmotor";
static const char* DEVICE_ID = "esp32-02";

static const uint8_t SDA_PIN = 5;
static const uint8_t SCL_PIN = 9;
static const uint8_t DS18B20_PIN = 4;
static const uint8_t MPU_ADDR = 0x68;
static const uint32_t WIFI_RETRY_MS = 12000UL;
static const uint32_t MQTT_RETRY_MS = 4000UL;
static const uint32_t SAMPLE_MS = 20UL;  // aproximadamente 50 amostras/s
static const uint32_t PUBLISH_MS = 1000UL;
static const uint32_t TEMP_REQUEST_MS = 2000UL;
static const uint32_t TEMP_WAIT_MS = 800UL; // DS18B20 12-bit: ate 750 ms

MqttWebSocketClient net;
PubSubClient mqtt(net);
// Criados apos a procura do sensor: o GPIO4 e o esperado, mas cada placa S3 varia.
OneWire* oneWire=nullptr;
DallasTemperature* ds18b20=nullptr;
uint8_t ds18b20Pin=0;
// Pinos livres candidatos (fora de I2C 5/9, USB 19/20, UART 43/44 e strapping).
static const uint8_t DS18B20_CANDIDATOS[]={DS18B20_PIN,1,2,6,7,8,10,11,12,13,14,15,16,17,18,21,38,39,40,41,42,47,48};
char telemetryTopic[96], statusTopic[96], capabilitiesTopic[96], commandTopic[96], ackTopic[96], wifiTopic[96];
uint32_t lastWifiAttempt=0,lastMqttAttempt=0,lastSample=0,lastPublish=0;
uint32_t lastTempRequest=0,tempRequestedAt=0,sequence=0,lastMpuRetry=0;
static const uint32_t MPU_RETRY_MS = 5000UL;
uint32_t sampleCount=0;
float vibrationSquares=0.0f,vibrationPeak=0.0f;
float gravityX=0.0f,gravityY=0.0f,gravityZ=1.0f;
float temperatureC=NAN;
bool mpuReady=false,tempPending=false,tempReady=false;

// Procura um DS18B20 nos pinos candidatos; so aceita ROM lida com CRC valido.
void procurarDs18b20() {
  for (uint8_t pino : DS18B20_CANDIDATOS) {
    OneWire barramento(pino);
    DallasTemperature sensor(&barramento);
    sensor.begin();
    DeviceAddress rom;
    // getAddress ja rejeita ROM com CRC invalido (validAddress).
    if (sensor.getDeviceCount() < 1 || !sensor.getAddress(rom,0)) continue;
    ds18b20Pin=pino;
    oneWire=new OneWire(pino);
    ds18b20=new DallasTemperature(oneWire);
    ds18b20->begin();
    ds18b20->setWaitForConversion(false);
    Serial.printf("[S3/DS18B20] encontrado no GPIO%u\n",pino);
    if (pino!=DS18B20_PIN) Serial.printf("[S3/DS18B20] atencao: esperado no GPIO%u\n",DS18B20_PIN);
    return;
  }
  Serial.printf("[S3/DS18B20] nenhum sensor no GPIO%u nem nos demais pinos livres;"
                " confira DQ, GND, 3V3 e o resistor de 4k7 entre DQ e 3V3\n",DS18B20_PIN);
}

void publishStatus(const char* msg) {
  Serial.printf("[S3/status] %s\n",msg);
  if (mqtt.connected()) mqtt.publish(statusTopic,msg,true);
}

bool mpuWrite(uint8_t reg,uint8_t value) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg); Wire.write(value);
  return Wire.endTransmission()==0;
}

bool initMpu(bool avisarFalha) {
  // WHO_AM_I (0x75) so confirma presenca: clones MPU6500/9250 respondem 0x70/0x71/0x73
  // e funcionam com os mesmos registradores, entao qualquer resposta e aceita.
  Wire.beginTransmission(MPU_ADDR);
  Wire.write((uint8_t)0x75);
  bool ok=Wire.endTransmission(false)==0 && Wire.requestFrom(MPU_ADDR,(uint8_t)1,(bool)true)==1;
  const uint8_t id=ok?Wire.read():0;
  ok=ok&&mpuWrite(0x6B,0x00);  // wake up
  ok=ok&&mpuWrite(0x1C,0x08);  // +/-4 g -> 8192 LSB/g
  if(ok) Serial.printf("[S3/MPU6050] iniciado nos GPIO5/9, WHO_AM_I=0x%02X\n",id);
  else if(avisarFalha) Serial.println("[S3/MPU6050] indisponivel; confira I2C e alimentacao (nova tentativa a cada 5 s)");
  return ok;
}

void sampleMpu() {
  if(!mpuReady)return;
  Wire.beginTransmission(MPU_ADDR);
  Wire.write((uint8_t)0x3B);
  if(Wire.endTransmission(false)!=0 || Wire.requestFrom(MPU_ADDR,(uint8_t)6,(bool)true)!=6) {
    mpuReady=false;
    Serial.println("[S3/MPU6050] leitura falhou; tentara reiniciar");
    return;
  }
  int16_t rx=(int16_t)((Wire.read()<<8)|Wire.read());
  int16_t ry=(int16_t)((Wire.read()<<8)|Wire.read());
  int16_t rz=(int16_t)((Wire.read()<<8)|Wire.read());
  const float x=rx/8192.0f,y=ry/8192.0f,z=rz/8192.0f;
  // Filtra gravidade lentamente, usa magnitude da aceleracao dinamica.
  gravityX=0.98f*gravityX+0.02f*x;
  gravityY=0.98f*gravityY+0.02f*y;
  gravityZ=0.98f*gravityZ+0.02f*z;
  const float dx=x-gravityX,dy=y-gravityY,dz=z-gravityZ;
  const float dynamicG=sqrtf(dx*dx+dy*dy+dz*dz);
  if(isfinite(dynamicG) && dynamicG<8.0f) {
    vibrationSquares+=dynamicG*dynamicG;
    vibrationPeak=fmaxf(vibrationPeak,dynamicG);
    sampleCount++;
  }
}

void pollTemperature(uint32_t now) {
  if(!ds18b20)return;
  if(tempPending && (uint32_t)(now-tempRequestedAt)>=TEMP_WAIT_MS) {
    float reading=ds18b20->getTempCByIndex(0);
    tempReady=isfinite(reading) && reading>-55.0f && reading<125.0f &&
              reading!=85.0f && reading!=DEVICE_DISCONNECTED_C;
    temperatureC=tempReady?reading:NAN;
    static int8_t ultimoEstado=-1;  // Avisa so na mudanca: evita repetir a cada 2 s.
    if(tempReady!=(ultimoEstado==1)||ultimoEstado<0) {
      if(tempReady)Serial.printf("[S3/DS18B20] %.2f C\n",temperatureC);
      else Serial.println("[S3/DS18B20] sensor ausente/leitura invalida");
      ultimoEstado=tempReady?1:0;
    }
    tempPending=false;
  }
  if(!tempPending && (lastTempRequest==0 || (uint32_t)(now-lastTempRequest)>=TEMP_REQUEST_MS)) {
    lastTempRequest=now;
    ds18b20->requestTemperatures(); // setWaitForConversion(false) na deteccao
    tempRequestedAt=now;
    tempPending=true;
  }
}

void publishCapabilities() {
  StaticJsonDocument<384> doc;
  doc["device_id"]=DEVICE_ID;
  doc["firmware_version"]="s3-sensors-1.1-websocket";
  doc["demo"]=false;
  doc["accepts_direct_command"]=false;
  doc["accepts_command_request"]=false;
  JsonArray fields=doc.createNestedArray("fields");
  fields.add("vibration");fields.add("vibration_peak");fields.add("temperature");
  char payload[384];size_t n=serializeJson(doc,payload,sizeof(payload));
  if(n)mqtt.publish(capabilitiesTopic,(const uint8_t*)payload,(unsigned int)n,true);
}

void publishTelemetry() {
  if(!mqtt.connected())return;
  StaticJsonDocument<384> doc;
  doc["device_id"]=DEVICE_ID;
  doc["seq"]=++sequence;
  doc["demo"]=false;
  doc["data_source"]="mpu6050_ds18b20";
  doc["mpu_ok"]=mpuReady;
  doc["temperature_ok"]=tempReady;
  doc["sample_count"]=sampleCount;
  if(mpuReady && sampleCount>=10) {
    doc["vibration"]=sqrtf(vibrationSquares/sampleCount); // RMS de aceleracao dinamica, g
    doc["vibration_peak"]=vibrationPeak;
  }
  if(tempReady && isfinite(temperatureC))doc["temperature"]=temperatureC;
  char payload[384];size_t n=serializeJson(doc,payload,sizeof(payload));
  if(!n||!mqtt.publish(telemetryTopic,(const uint8_t*)payload,(unsigned int)n,false))
    Serial.printf("[S3/MQTT] falha publicando, state=%d bytes=%u\n",mqtt.state(),(unsigned int)n);
  else if(sequence%10==1)Serial.printf("[S3/MQTT] telemetria seq=%lu, amostras=%lu, temp_ok=%d\n",(unsigned long)sequence,(unsigned long)sampleCount,tempReady);
  vibrationSquares=0.0f;vibrationPeak=0.0f;sampleCount=0;
}

// Lista de redes gravada na placa, sem senhas, com a chave publica para o
// painel cifrar senhas novas. Retida para a aba "Wi-Fi" abrir ja preenchida.
void publishNetworks() {
  if(!mqtt.connected())return;
  StaticJsonDocument<1024> doc;
  doc["device_id"]=DEVICE_ID;
  wifistore::descrever(doc);
  char payload[1024];size_t n=serializeJson(doc,payload,sizeof(payload));
  if(n)mqtt.publish(wifiTopic,(const uint8_t*)payload,(unsigned int)n,true);
}

void publishAck(const char* seq,const char* acao,bool aceito,const char* motivo) {
  StaticJsonDocument<256> resposta;
  resposta["device_id"]=DEVICE_ID;resposta["seq"]=seq;resposta["action"]=acao;
  resposta["accepted"]=aceito;resposta["reason"]=motivo;
  char saida[256];size_t n=serializeJson(resposta,saida,sizeof(saida));
  if(n)mqtt.publish(ackTopic,(const uint8_t*)saida,(unsigned int)n,false);
}

// Comandos aceitos: lista de redes Wi-Fi, portal de cadastro e atualizacao.
void onCommand(char* topic, uint8_t* payload, unsigned int length) {
  if(!topic || strcmp(topic,commandTopic) || !length || length>700)return;
  StaticJsonDocument<512> doc;
  if(deserializeJson(doc,payload,length) || doc["v"].as<int>()!=1 ||
     strcmp(doc["device_id"] | "",DEVICE_ID))return;
  const char* acao=doc["action"] | "";
  const char* seq=doc["seq"] | "";
  // Lista de redes: a senha chega cifrada para a chave desta placa.
  const char* motivoWifi="";
  const wifistore::Resultado resultado=wifistore::tratarComando(acao,doc.as<JsonVariantConst>(),motivoWifi);
  if(resultado!=wifistore::Resultado::NaoEWifi) {
    publishAck(seq,acao,resultado==wifistore::Resultado::Aceito,motivoWifi);
    publishNetworks();
    return;
  }
  // Portal de cadastro na propria placa (ultimo recurso).
  if(!strcmp(acao,"wifi_portal")) {
    publishAck(seq,acao,true,"rede da placa aberta por 180 s");
    delay(200);
    abrirPortalDeRede(PORTAL_SEGUNDOS);
    ESP.restart();
    return;
  }
  if(strcmp(acao,"update"))return;
  StaticJsonDocument<256> resposta;
  resposta["device_id"]=DEVICE_ID;resposta["seq"]=seq;resposta["action"]="update";
  resposta["accepted"]=true;resposta["reason"]="baixando firmware";
  char saida[256];size_t n=serializeJson(resposta,saida,sizeof(saida));
  if(n)mqtt.publish(ackTopic,(const uint8_t*)saida,(unsigned int)n,false);
  String motivo;
  atualizarPelaInternet(OTA_ARQUIVO,motivo);  // Sucesso reinicia a placa.
  resposta["accepted"]=false;resposta["reason"]=motivo;
  n=serializeJson(resposta,saida,sizeof(saida));
  if(n)mqtt.publish(ackTopic,(const uint8_t*)saida,(unsigned int)n,false);
}

void setup() {
  Serial.begin(115200);
  Wire.begin(SDA_PIN,SCL_PIN);
  Wire.setClock(100000);
  mpuReady=initMpu(true);
  lastMpuRetry=millis();
  procurarDs18b20();
  snprintf(telemetryTopic,sizeof(telemetryTopic),"%s/%s/telemetry",TOPIC_PREFIX,DEVICE_ID);
  snprintf(statusTopic,sizeof(statusTopic),"%s/%s/status",TOPIC_PREFIX,DEVICE_ID);
  snprintf(capabilitiesTopic,sizeof(capabilitiesTopic),"%s/%s/capabilities",TOPIC_PREFIX,DEVICE_ID);
  snprintf(commandTopic,sizeof(commandTopic),"%s/%s/command",TOPIC_PREFIX,DEVICE_ID);
  snprintf(ackTopic,sizeof(ackTopic),"%s/%s/command_ack",TOPIC_PREFIX,DEVICE_ID);
  mqtt.setServer(MQTT_HOST,MQTT_PORT);
  snprintf(wifiTopic,sizeof(wifiTopic),"%s/%s/wifi",TOPIC_PREFIX,DEVICE_ID);
  mqtt.setBufferSize(1536);
  mqtt.setCallback(onCommand);
  WiFi.mode(WIFI_STA);
  wifistore::carregar(REDES_INICIAIS,SENHAS_INICIAIS,sizeof(REDES_INICIAIS)/sizeof(REDES_INICIAIS[0]));
  wifistore::prepararChaves();
  wifistore::carregarRedePropria(PORTAL_NOME);
  Serial.printf("[S3/Wi-Fi] %u rede(s) na lista da placa\n",wifistore::total);
  // Nenhuma rede da lista respondeu: so o portal permite cadastrar sem cabo.
  if(!wifistore::conectarEmOrdem(10000))abrirPortalDeRede(PORTAL_SEGUNDOS);
  Serial.printf("[S3/boot] %s broker=%s:%u\n",DEVICE_ID,MQTT_HOST,MQTT_PORT);
}

void loop() {
  uint32_t now=millis();
  if((uint32_t)(now-lastSample)>=SAMPLE_MS){lastSample=now;sampleMpu();}
  if(!mpuReady && (uint32_t)(now-lastMpuRetry)>=MPU_RETRY_MS) {
    lastMpuRetry=now;
    mpuReady=initMpu(false);  // Falha ja avisada; so informa quando voltar.
  }
  pollTemperature(now);
  if(WiFi.status()!=WL_CONNECTED) {
    if(lastWifiAttempt==0 || (uint32_t)(now-lastWifiAttempt)>=WIFI_RETRY_MS) {
      lastWifiAttempt=now;
      Serial.printf("[S3/Wi-Fi] conectando, status=%d\n",WiFi.status());
      wifistore::conectarEmOrdem(8000);  // Redes visiveis, na ordem da lista.
    }
    delay(2);return;
  }
  if(!mqtt.connected()) {
    if(lastMqttAttempt==0 || (uint32_t)(now-lastMqttAttempt)>=MQTT_RETRY_MS) {
      lastMqttAttempt=now;
      Serial.printf("[S3/MQTT] IP=%s conectando %s:%u\n",WiFi.localIP().toString().c_str(),MQTT_HOST,MQTT_PORT);
      String clientId=String("iotmotor_s3_")+String((uint32_t)ESP.getEfuseMac(),HEX);
      if(mqtt.connect(clientId.c_str(),statusTopic,0,true,"offline")) {
        publishStatus("online");publishCapabilities();mqtt.subscribe(commandTopic,1);publishNetworks();
        Serial.printf("[S3/MQTT] conectado, publicando %s\n",telemetryTopic);
      } else Serial.printf("[S3/MQTT] falha state=%d\n",mqtt.state());
    }
    delay(2);return;
  }
  mqtt.loop();
  now=millis();
  if(lastPublish==0 || (uint32_t)(now-lastPublish)>=PUBLISH_MS) {
    lastPublish=now;publishTelemetry();
  }
  delay(2);
}
