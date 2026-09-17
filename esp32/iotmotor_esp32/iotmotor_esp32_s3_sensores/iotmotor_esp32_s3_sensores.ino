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

static const char* WIFI_SSID = "IFMA_IOT";
static const char* WIFI_PASS = "";  // Wi-Fi aberto
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
OneWire oneWire(DS18B20_PIN);
DallasTemperature ds18b20(&oneWire);
char telemetryTopic[96], statusTopic[96], capabilitiesTopic[96];
uint32_t lastWifiAttempt=0,lastMqttAttempt=0,lastSample=0,lastPublish=0;
uint32_t lastTempRequest=0,tempRequestedAt=0,sequence=0,lastMpuRetry=0;
static const uint32_t MPU_RETRY_MS = 5000UL;
uint32_t sampleCount=0;
float vibrationSquares=0.0f,vibrationPeak=0.0f;
float gravityX=0.0f,gravityY=0.0f,gravityZ=1.0f;
float temperatureC=NAN;
bool mpuReady=false,tempPending=false,tempReady=false;

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
  // WHO_AM_I (0x75) confirma que e um MPU6050, nao apenas um ACK no endereco.
  Wire.beginTransmission(MPU_ADDR);
  Wire.write((uint8_t)0x75);
  bool ok=Wire.endTransmission(false)==0 && Wire.requestFrom(MPU_ADDR,(uint8_t)1,(bool)true)==1 && Wire.read()==0x68;
  ok=ok&&mpuWrite(0x6B,0x00);  // wake up
  ok=ok&&mpuWrite(0x1C,0x08);  // +/-4 g -> 8192 LSB/g
  if(ok) Serial.println("[S3/MPU6050] iniciado nos GPIO5/9");
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
  if(tempPending && (uint32_t)(now-tempRequestedAt)>=TEMP_WAIT_MS) {
    float reading=ds18b20.getTempCByIndex(0);
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
    ds18b20.requestTemperatures(); // setWaitForConversion(false) no setup
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

void setup() {
  Serial.begin(115200);
  Wire.begin(SDA_PIN,SCL_PIN);
  Wire.setClock(100000);
  mpuReady=initMpu(true);
  lastMpuRetry=millis();
  ds18b20.begin();
  ds18b20.setWaitForConversion(false);
  snprintf(telemetryTopic,sizeof(telemetryTopic),"%s/%s/telemetry",TOPIC_PREFIX,DEVICE_ID);
  snprintf(statusTopic,sizeof(statusTopic),"%s/%s/status",TOPIC_PREFIX,DEVICE_ID);
  snprintf(capabilitiesTopic,sizeof(capabilitiesTopic),"%s/%s/capabilities",TOPIC_PREFIX,DEVICE_ID);
  mqtt.setServer(MQTT_HOST,MQTT_PORT);
  mqtt.setBufferSize(768);
  WiFi.mode(WIFI_STA);
  Serial.printf("[S3/boot] %s Wi-Fi=%s broker=%s:%u\n",DEVICE_ID,WIFI_SSID,MQTT_HOST,MQTT_PORT);
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
      if(strlen(WIFI_PASS))WiFi.begin(WIFI_SSID,WIFI_PASS);
      else WiFi.begin(WIFI_SSID);
    }
    delay(2);return;
  }
  if(!mqtt.connected()) {
    if(lastMqttAttempt==0 || (uint32_t)(now-lastMqttAttempt)>=MQTT_RETRY_MS) {
      lastMqttAttempt=now;
      Serial.printf("[S3/MQTT] IP=%s conectando %s:%u\n",WiFi.localIP().toString().c_str(),MQTT_HOST,MQTT_PORT);
      String clientId=String("iotmotor_s3_")+String((uint32_t)ESP.getEfuseMac(),HEX);
      if(mqtt.connect(clientId.c_str(),statusTopic,0,true,"offline")) {
        publishStatus("online");publishCapabilities();
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
