/* IoTMotor — ESP32-S3 (esp32-02): sensores e alarme local, SEM reles.
 * Este sketch pressupoe MPU6050 (SDA GPIO5, SCL GPIO9) e DS18B20
 * (DQ GPIO4, resistor pull-up 4k7 a 3V3), como no projeto de dois modulos.
 * Confirme os pinos da SUA placa S3 antes de gravar. Sensores reais por padrao:
 * campos invalidos sao omitidos; nao inventamos temperatura ou vibracao.
 * O RMS de vibracao e estimativa da aceleracao dinamica em g; nao e mm/s.
 * Bibliotecas: PubSubClient, ArduinoJson 6.x, OneWire, DallasTemperature.
 * Comandos de alarme, Wi-Fi e OTA; nenhum comando de motor.
 */
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <math.h>
#include <Preferences.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/semphr.h>
#include "mqtt_websocket_client.h"
#define OTA_ARQUIVO "esp32-02.bin"
#define PORTAL_NOME "IoTMotor-esp32-02"
constexpr uint16_t PORTAL_SEGUNDOS = 180;
#include "ota_update.h"
#include "wifi_portal.h"
#include "alarm_list.h"
#include "comando_seguro.h"
#include "relogio.h"

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
// Sinalizacao local da placa (mesma pinagem do modulo 2 original).
static const uint8_t BUZZER_PIN = 42;      // Passivo: acionado com tone().
static const uint8_t LED_AZUL_PIN = 16;
static const uint8_t LED_VERDE_PIN = 17;
static const uint8_t LED_VERM_PIN = 18;
static const bool RGB_ANODO_COMUM = false;  // Catodo comum: nivel alto acende.
static const uint32_t BEEP_MS = 400UL;      // Intervalo do alarme intermitente.
static const uint16_t BEEP_HZ = 2000;
// Limites padrao do alarme; ajustaveis pelo painel e gravados na placa.
static const float VIBRACAO_LIMITE_PADRAO = 0.50f;
static const float TEMPERATURA_LIMITE_PADRAO = 60.0f;
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
// GPIO4 so e pulado em runtime quando estiver realmente ocupado pelo DS18B20.
static const uint8_t DS18B20_CANDIDATOS[]={DS18B20_PIN,1,2,6,7,8,10,11,12,13,14,15,21,38,39,40,41,47,48};
char telemetryTopic[96], statusTopic[96], capabilitiesTopic[96], commandTopic[96], ackTopic[96], wifiTopic[96];
char alarmsTopic[96], quadroTelemetryTopic[96], authTopic[96], alarmLogTopic[96];
uint32_t lastWifiAttempt=0,lastMqttAttempt=0,lastSample=0,lastPublish=0;
uint32_t lastTempRequest=0,tempRequestedAt=0,sequence=0,lastMpuRetry=0;
static const uint32_t MPU_RETRY_MS = 5000UL;
uint32_t sampleCount=0;
float vibrationSquares=0.0f,vibrationPeak=0.0f;
float gravityX=0.0f,gravityY=0.0f,gravityZ=1.0f;
float temperatureC=NAN;
bool mpuReady=false,tempPending=false,tempReady=false;
// Alarme local: LED RGB e buzzer.
bool alarmeHabilitado=true,estadoCritico=false,buzzerLigado=false;
bool sonsDeEventos=true;  // Bipes curtos de evento, fora da emergencia.
uint32_t ultimoBeep=0,inicioDoTeste=0;
bool testeAtivo=false;
float picoAtual=0.0f,rmsAtual=0.0f;
uint32_t amostrasAtuais=0;
// Sensores e sinalizacao continuam durante reconexao Wi-Fi, portal e MQTT.
SemaphoreHandle_t sensoresMutex=nullptr;
void aplicarLed(bool azul,bool verde,bool vermelho) {
  digitalWrite(LED_AZUL_PIN, azul==!RGB_ANODO_COMUM?HIGH:LOW);
  digitalWrite(LED_VERDE_PIN, verde==!RGB_ANODO_COMUM?HIGH:LOW);
  digitalWrite(LED_VERM_PIN, vermelho==!RGB_ANODO_COMUM?HIGH:LOW);
}

// Interruptor geral e bipes de evento; os limites ficam na lista de alarmes.
void carregarConfigDoAlarme() {
  Preferences memoria;
  if(!memoria.begin("iot-alarme",true))return;
  alarmeHabilitado=memoria.getBool("ligado",true);
  sonsDeEventos=memoria.getBool("sons",true);
  memoria.end();
}

bool salvarConfigDoAlarme(bool ligado,bool sons) {
  Preferences memoria;
  if(!memoria.begin("iot-alarme",false))return false;
  memoria.putBool("ligado",ligado);
  memoria.putBool("sons",sons);
  memoria.end();
  xSemaphoreTake(sensoresMutex,portMAX_DELAY);
  alarmeHabilitado=ligado;sonsDeEventos=sons;
  xSemaphoreGive(sensoresMutex);
  return true;
}

// ---- Bipes curtos fora da emergencia ----
// Avisos de conexao e de comando recebido, e o bipe pedido pelo painel. Sao
// tocados sem travar o laco e nunca atrapalham o alarme, que tem prioridade.
uint8_t beepsRestantes=0;
uint16_t beepFrequencia=BEEP_HZ;
uint32_t beepDuracao=80,beepProximo=0;
bool beepTocando=false;

void pedirBeep(uint8_t vezes,uint16_t frequencia,uint32_t duracaoMs) {
  if(!vezes)return;
  beepsRestantes=vezes;
  beepFrequencia=frequencia;
  beepDuracao=duracaoMs;
  beepProximo=millis();
  beepTocando=false;
}

// ---- Procura do buzzer ----
// Percorre os pinos livres tocando de dois jeitos: tone (buzzer passivo) e
// nivel alto (buzzer ativo). Cada passo e anunciado em command_ack, entao da
// para casar o som ouvido com o pino. Anda no laco principal: chamar
// mqtt.loop() de dentro do tratador de comandos corrompe as mensagens.
static const uint8_t BUZZER_CANDIDATOS[]={42,41,40,39,38,47,48,21,15,14,13,12,11,10,8,7,6,4,2,1};
bool probeAtivo=false,probeTocando=false;
uint8_t probeIndice=0,probeModo=0;
uint32_t probePasso=700,probeProximo=0;
String probeSeq;

// ---- Procura dos canais do LED RGB ----
// Testa somente GPIOs livres, um por vez, em nivel alto e baixo.
// O GPIO17 (verde conhecido) fica fora da varredura para nao confundir.
static const uint8_t LED_CANDIDATOS[]={16,18,42,41,40,39,38,47,48,21,15,14,13,12,11,10,8,7,6,4,2,1};
bool ledProbeAtivo=false,ledProbeLigado=false;
uint8_t ledProbeIndice=0,ledProbeModo=0;
uint32_t ledProbePasso=900,ledProbeProximo=0;
String ledProbeSeq;

void beepDeEvento(uint8_t vezes) {
  if(sonsDeEventos)pedirBeep(vezes,BEEP_HZ,70);
}

// Retorna true enquanto estiver tocando um bipe (o alarme nao mexe no buzzer).
bool atualizarBeeps(uint32_t now) {
  if(!beepsRestantes&&!beepTocando)return false;
  if((int32_t)(now-beepProximo)<0)return true;
  if(beepTocando) {          // Fim do som: silencio do mesmo tamanho.
    noTone(BUZZER_PIN);
    beepTocando=false;
    beepProximo=now+beepDuracao;
    if(!beepsRestantes)return false;
    return true;
  }
  if(!beepsRestantes)return false;
  --beepsRestantes;
  tone(BUZZER_PIN,beepFrequencia);
  beepTocando=true;
  beepProximo=now+beepDuracao;
  return true;
}

// Lista de alarmes retida, para o painel e o app abrirem ja preenchidos.
void publishAlarms() {
  if(!mqtt.connected())return;
  StaticJsonDocument<1536> doc;
  doc["device_id"]=DEVICE_ID;
  xSemaphoreTake(sensoresMutex,portMAX_DELAY);
  doc["enabled"]=alarmeHabilitado;
  doc["sounds"]=sonsDeEventos;
  alarmes::descrever(doc);
  xSemaphoreGive(sensoresMutex);
  String texto;
  serializeJson(doc,texto);
  if(texto.length())
    mqtt.publish(alarmsTopic,(const uint8_t*)texto.c_str(),(unsigned int)texto.length(),true);
}

// Ultimos disparos, retidos: o painel abre ja mostrando o que aconteceu.
void publishAlarmLog() {
  if(!mqtt.connected())return;
  StaticJsonDocument<1536> doc;
  doc["device_id"]=DEVICE_ID;
  xSemaphoreTake(sensoresMutex,portMAX_DELAY);
  alarmes::descreverEventos(doc);
  alarmes::eventosMudaram=false;
  xSemaphoreGive(sensoresMutex);
  String texto;
  serializeJson(doc,texto);
  if(texto.length())
    mqtt.publish(alarmLogTopic,(const uint8_t*)texto.c_str(),(unsigned int)texto.length(),true);
}

// Desafio da vez, retido: o painel precisa dele para cifrar um comando.
void publishAuth() {
  if(!mqtt.connected())return;
  StaticJsonDocument<192> doc;
  doc["v"]=1;
  doc["device_id"]=DEVICE_ID;
  comandoseguro::descrever(doc);
  char payload[192];size_t n=serializeJson(doc,payload,sizeof(payload));
  if(n)mqtt.publish(authTopic,(const uint8_t*)payload,(unsigned int)n,true);
}

void publishAck(const char* seq,const char* acao,bool aceito,const char* motivo);

// Avanca a procura do buzzer; true enquanto ela estiver em andamento.
bool atualizarProcuraDoBuzzer(uint32_t now) {
  if(!probeAtivo)return false;
  if((int32_t)(now-probeProximo)<0)return true;
  const uint8_t pino=BUZZER_CANDIDATOS[probeIndice];
  if(probeTocando) {            // Fim do passo: solta o pino e faz uma pausa.
    if(probeModo)digitalWrite(pino,LOW);
    else noTone(pino);
    pinMode(pino,INPUT);
    probeTocando=false;
    probeProximo=now+250;
    if(++probeModo>1) {
      probeModo=0;
      if(++probeIndice>=sizeof(BUZZER_CANDIDATOS)) {
        probeAtivo=false;
        pinMode(BUZZER_PIN,OUTPUT);
        publishAck(probeSeq.c_str(),"buzzer_probe",true,"procura encerrada");
        return false;
      }
    }
    return true;
  }
  // Pula os pinos que ja tem dono nesta placa.
  if(pino==LED_AZUL_PIN||pino==LED_VERDE_PIN||pino==LED_VERM_PIN||pino==ds18b20Pin) {
    probeModo=0;
    if(++probeIndice>=sizeof(BUZZER_CANDIDATOS)) {probeAtivo=false;return false;}
    return true;
  }
  char aviso[64];
  snprintf(aviso,sizeof(aviso),"GPIO%u %s",pino,probeModo?"nivel alto (ativo)":"tone (passivo)");
  publishAck(probeSeq.c_str(),"buzzer_probe",true,aviso);
  Serial.printf("[BUZZER] %s\n",aviso);
  if(probeModo){pinMode(pino,OUTPUT);digitalWrite(pino,HIGH);}
  else tone(pino,BEEP_HZ);
  probeTocando=true;
  probeProximo=now+probePasso;
  return true;
}

// Avanca a procura dos canais do LED; true enquanto estiver em andamento.
bool atualizarProcuraDosLeds(uint32_t now) {
  if(!ledProbeAtivo)return false;
  if((int32_t)(now-ledProbeProximo)<0)return true;
  const uint8_t pino=LED_CANDIDATOS[ledProbeIndice];

  if(ledProbeLigado) {
    // Desliga o pino testado e devolve para alta impedancia.
    digitalWrite(pino,ledProbeModo?HIGH:LOW);
    pinMode(pino,INPUT);
    ledProbeLigado=false;
    ledProbeProximo=now+250;
    if(++ledProbeModo>1) {
      ledProbeModo=0;
      if(++ledProbeIndice>=sizeof(LED_CANDIDATOS)) {
        ledProbeAtivo=false;
        pinMode(LED_AZUL_PIN,OUTPUT);
        pinMode(LED_VERDE_PIN,OUTPUT);
        pinMode(LED_VERM_PIN,OUTPUT);
        publishAck(ledProbeSeq.c_str(),"led_probe",true,"procura encerrada");
        return false;
      }
    }
    return true;
  }

  // Nao interfere em I2C, USB/UART, sensor de temperatura, verde conhecido ou buzzer.
  if(pino==SDA_PIN||pino==SCL_PIN||pino==19||pino==20||pino==43||pino==44||
     pino==ds18b20Pin||pino==LED_VERDE_PIN||pino==BUZZER_PIN) {
    ledProbeModo=0;
    if(++ledProbeIndice>=sizeof(LED_CANDIDATOS)) {
      ledProbeAtivo=false;
      publishAck(ledProbeSeq.c_str(),"led_probe",true,"procura encerrada");
      return false;
    }
    return true;
  }

  pinMode(pino,OUTPUT);
  // modo 0 testa HIGH (catodo comum); modo 1 testa LOW (anodo comum).
  digitalWrite(pino,ledProbeModo?LOW:HIGH);
  char aviso[64];
  snprintf(aviso,sizeof(aviso),"GPIO%u nivel %s",pino,ledProbeModo?"LOW":"HIGH");
  publishAck(ledProbeSeq.c_str(),"led_probe",true,aviso);
  Serial.printf("[LED] %s\n",aviso);
  ledProbeLigado=true;
  ledProbeProximo=now+ledProbePasso;
  return true;
}

// Azul: sem sensor valido. Verde: tudo normal. Vermelho: limite ultrapassado.
void atualizarSinalizacao(uint32_t now,float vibracaoPico) {
  if(atualizarProcuraDoBuzzer(now))return;  // Procura do buzzer em andamento.
  if(atualizarProcuraDosLeds(now))return;   // Procura dos canais do LED em andamento.
  // Quem decide e a lista: cada alarme aponta a grandeza, o lado e o limite.
  const bool algumDisparou=alarmes::avaliar(now,mpuReady,tempReady,rmsAtual,vibracaoPico,
                                            temperatureC,relogio::agoraUtc());
  estadoCritico=alarmeHabilitado&&algumDisparou;
  if(testeAtivo&&(uint32_t)(now-inicioDoTeste)<1500UL)return;
  testeAtivo=false;  // Subtracao unsigned suporta a volta de millis() a zero.
  if(!mpuReady&&!tempReady)aplicarLed(true,false,false);
  else aplicarLed(false,!estadoCritico,estadoCritico);
  if(!estadoCritico) {
    if(buzzerLigado){noTone(BUZZER_PIN);buzzerLigado=false;}
    atualizarBeeps(now);  // Fora da emergencia o buzzer fica com os bipes.
    return;
  }
  beepsRestantes=0;beepTocando=false;  // Emergencia tem prioridade.
  if((uint32_t)(now-ultimoBeep)>=BEEP_MS) {  // Bipe intermitente.
    ultimoBeep=now;
    buzzerLigado=!buzzerLigado;
    if(buzzerLigado)tone(BUZZER_PIN,BEEP_HZ);
    else noTone(BUZZER_PIN);
  }
}

void testarSinalizacao(uint32_t now) {
  inicioDoTeste=now;testeAtivo=true;
  ultimoBeep=now;
  aplicarLed(true,true,true);
  tone(BUZZER_PIN,BEEP_HZ);
  buzzerLigado=true;
}

void testarLed(uint32_t now,bool azul,bool verde,bool vermelho) {
  inicioDoTeste=now;testeAtivo=true;
  aplicarLed(azul,verde,vermelho);
  noTone(BUZZER_PIN);
  buzzerLigado=false;
}

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

// Executada independentemente das operacoes de rede potencialmente bloqueantes.
void tarefaSensores(void*) {
  uint32_t ultimaJanela=millis();
  for(;;) {
    const uint32_t now=millis();
    xSemaphoreTake(sensoresMutex,portMAX_DELAY);
    if((uint32_t)(now-lastSample)>=SAMPLE_MS){lastSample=now;sampleMpu();}
    if(!mpuReady&&(uint32_t)(now-lastMpuRetry)>=MPU_RETRY_MS) {
      lastMpuRetry=now;
      mpuReady=initMpu(false);
    }
    pollTemperature(now);
    if((uint32_t)(now-ultimaJanela)>=PUBLISH_MS) {
      ultimaJanela=now;
      amostrasAtuais=mpuReady?sampleCount:0;
      picoAtual=amostrasAtuais>=10?vibrationPeak:0.0f;
      rmsAtual=amostrasAtuais>=10?sqrtf(vibrationSquares/amostrasAtuais):0.0f;
      vibrationSquares=0.0f;vibrationPeak=0.0f;sampleCount=0;
    }
    atualizarSinalizacao(now,fmaxf(picoAtual,vibrationPeak));
    xSemaphoreGive(sensoresMutex);
    vTaskDelay(pdMS_TO_TICKS(2));
  }
}

void publishCapabilities() {
  StaticJsonDocument<384> doc;
  doc["device_id"]=DEVICE_ID;
  doc["firmware_version"]="s3-sensors-1.4-alarmes";
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
  StaticJsonDocument<1024> doc;
  xSemaphoreTake(sensoresMutex,portMAX_DELAY);
  doc["device_id"]=DEVICE_ID;
  doc["seq"]=++sequence;
  doc["demo"]=false;
  doc["data_source"]="mpu6050_ds18b20";
  doc["mpu_ok"]=mpuReady;
  doc["temperature_ok"]=tempReady;
  doc["sample_count"]=amostrasAtuais;
  doc["secure"]=comandoseguro::ligado;
  // Hora da medicao, em segundos UTC. Ausente enquanto o NTP nao responde.
  if(const uint32_t carimbo=relogio::agoraUtc())doc["ts"]=carimbo;
  doc["alarm_enabled"]=alarmeHabilitado;
  doc["event_sounds"]=sonsDeEventos;
  doc["alarm_active"]=estadoCritico;
  if(mpuReady && amostrasAtuais>=10) {
    doc["vibration"]=rmsAtual; // RMS de aceleracao dinamica, g
    doc["vibration_peak"]=picoAtual;
  }
  if(tempReady && isfinite(temperatureC))doc["temperature"]=temperatureC;
  JsonArray disparados=doc.createNestedArray("alarms_firing");
  for(uint8_t i=0;i<alarmes::total;i++)
    if(alarmes::lista[i].disparado)disparados.add(alarmes::lista[i].id);
  xSemaphoreGive(sensoresMutex);
  char payload[1024];size_t n=serializeJson(doc,payload,sizeof(payload));
  if(!n||!mqtt.publish(telemetryTopic,(const uint8_t*)payload,(unsigned int)n,false))
    Serial.printf("[S3/MQTT] falha publicando, state=%d bytes=%u\n",mqtt.state(),(unsigned int)n);
  else if(sequence%10==1)Serial.printf("[S3/MQTT] telemetria seq=%lu, amostras=%lu, temp_ok=%d\n",(unsigned long)sequence,doc["sample_count"].as<unsigned long>(),doc["temperature_ok"].as<bool>());
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

// Comandos aceitos: alarme, lista de redes Wi-Fi, portal e atualizacao.
void onCommand(char* topic, uint8_t* payload, unsigned int length) {
  if(!topic || !length)return;
  if(!strcmp(topic,quadroTelemetryTopic)) {  // Medidas eletricas do outro ESP32.
    if(length<=900) {
      xSemaphoreTake(sensoresMutex,portMAX_DELAY);
      alarmes::receberMedidasDoQuadro(payload,length,millis());
      xSemaphoreGive(sensoresMutex);
    }
    return;
  }
  if(strcmp(topic,commandTopic) || length>1400)return;
  StaticJsonDocument<768> doc;
  if(deserializeJson(doc,payload,length) || doc["v"].as<int>()!=1 ||
     strcmp(doc["device_id"] | "",DEVICE_ID))return;

  // Com senha configurada, so passa comando cifrado e com o desafio da vez.
  if(comandoseguro::ligado) {
    static char aberto[comandoseguro::MAX_ABERTO];
    const char* motivoSelo="";
    if(!(doc["sealed"] | "")[0]) {
      publishAck(doc["seq"] | "",doc["action"] | "sealed",false,
                 "comando sem selo: configure a senha de comando");
      return;
    }
    if(!comandoseguro::abrir(doc["sealed"] | "",DEVICE_ID,aberto,sizeof(aberto),motivoSelo)) {
      publishAck(doc["seq"] | "","sealed",false,motivoSelo);
      return;
    }
    doc.clear();
    if(deserializeJson(doc,aberto) || doc["v"].as<int>()!=1 ||
       strcmp(doc["device_id"] | "",DEVICE_ID))return;
    if(!comandoseguro::confereDesafio(doc["ch"] | "")) {
      publishAck(doc["seq"] | "",doc["action"] | "sealed",false,"desafio vencido: envie de novo");
      return;
    }
    comandoseguro::usar();  // Comando repetido do ar nao vale mais.
    publishAuth();
  }

  const char* acao=doc["action"] | "";
  const char* seq=doc["seq"] | "";
  beepDeEvento(1);  // Confirma na bancada que o comando chegou.
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
  if(!strcmp(acao,"led_probe")) {  // Procura os canais do LED RGB.
    ledProbeSeq=seq;
    ledProbePasso=constrain((long)(doc["ms"] | 900),300,2500);
    ledProbeIndice=0;ledProbeModo=0;ledProbeLigado=false;ledProbeProximo=millis();ledProbeAtivo=true;
    // Evita que o buzzer ou outro teste concorram com a varredura.
    probeAtivo=false;testeAtivo=false;noTone(BUZZER_PIN);buzzerLigado=false;
    aplicarLed(false,false,false);
    publishAck(seq,acao,true,"procurando canais do LED: observe as cores");
    return;
  }
  if(!strcmp(acao,"buzzer_probe")) {  // Procura o buzzer; anda no laco principal.
    probeSeq=seq;
    probePasso=constrain((long)(doc["ms"] | 700),200,2000);
    probeIndice=0;probeModo=0;probeTocando=false;probeProximo=millis();probeAtivo=true;
    publishAck(seq,acao,true,"procurando o buzzer: ouca a placa");
    return;
  }
  if(!strcmp(acao,"buzzer_beep")) {  // Bipe pedido pelo painel ou pelo app.
    const uint16_t frequencia=constrain((int)(doc["freq"] | BEEP_HZ),200,5000);
    const uint32_t duracao=constrain((long)(doc["ms"] | 120),20,2000);
    const uint8_t vezes=constrain((int)(doc["count"] | 1),1,5);
    pedirBeep(vezes,frequencia,duracao);
    publishAck(seq,acao,true,"bipe acionado");
    return;
  }
  if(!strcmp(acao,"alarm_test")) {  // Acende tudo e apita por 1,5 s.
    xSemaphoreTake(sensoresMutex,portMAX_DELAY);
    testarSinalizacao(millis());
    xSemaphoreGive(sensoresMutex);
    publishAck(seq,acao,true,"LED e buzzer acionados por 1,5 s");
    return;
  }
  if(!strcmp(acao,"led_test")) {  // Testa uma cor do RGB por 1,5 s.
    const char* cor=doc["color"] | "";
    bool azul=false,verde=false,vermelho=false;
    if(!strcmp(cor,"blue"))azul=true;
    else if(!strcmp(cor,"green"))verde=true;
    else if(!strcmp(cor,"red"))vermelho=true;
    else {
      publishAck(seq,acao,false,"cor invalida: use blue, green ou red");
      return;
    }
    xSemaphoreTake(sensoresMutex,portMAX_DELAY);
    testarLed(millis(),azul,verde,vermelho);
    xSemaphoreGive(sensoresMutex);
    publishAck(seq,acao,true,cor);
    return;
  }
  if(!strcmp(acao,"alarm_set")) {  // Interruptor geral e bipes de evento.
    if(!doc["enabled"].is<bool>()) {
      publishAck(seq,acao,false,"campo enabled ausente");
      return;
    }
    const bool ok=salvarConfigDoAlarme(doc["enabled"].as<bool>(),
                                       doc["sounds"] | sonsDeEventos);
    publishAck(seq,acao,ok,ok?"alarme configurado":"falha ao gravar");
    if(ok)publishAlarms();
    return;
  }
  if(!strcmp(acao,"alarm_list")) {  // O painel pedindo a lista atual.
    publishAck(seq,acao,true,"lista publicada");
    publishAlarms();
    publishAlarmLog();
    return;
  }
  if(!strcmp(acao,"alarm_save")) {  // Cria ou edita um alarme da lista.
    const char* motivo="";
    xSemaphoreTake(sensoresMutex,portMAX_DELAY);
    const bool ok=alarmes::salvar(doc["alarm"],motivo);
    xSemaphoreGive(sensoresMutex);
    publishAck(seq,acao,ok,motivo);
    if(ok)publishAlarms();
    return;
  }
  if(!strcmp(acao,"alarm_remove")) {  // Tira um alarme da lista.
    const char* motivo="";
    xSemaphoreTake(sensoresMutex,portMAX_DELAY);
    const bool ok=alarmes::remover(doc["id"] | "",motivo);
    xSemaphoreGive(sensoresMutex);
    publishAck(seq,acao,ok,motivo);
    if(ok)publishAlarms();
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
  pinMode(LED_AZUL_PIN,OUTPUT);pinMode(LED_VERDE_PIN,OUTPUT);pinMode(LED_VERM_PIN,OUTPUT);
  pinMode(BUZZER_PIN,OUTPUT);noTone(BUZZER_PIN);
  comandoseguro::iniciar(DEVICE_ID);
  carregarConfigDoAlarme();
  alarmes::carregar(VIBRACAO_LIMITE_PADRAO,TEMPERATURA_LIMITE_PADRAO);
  aplicarLed(true,false,false);  // Azul ate haver sensor valido.
  mpuReady=initMpu(true);
  lastMpuRetry=millis();
  procurarDs18b20();
  sensoresMutex=xSemaphoreCreateMutex();
  if(!sensoresMutex||xTaskCreate(tarefaSensores,"sensores",4096,nullptr,1,nullptr)!=pdPASS) {
    Serial.println("[S3/alarme] falha ao iniciar tarefa de sensores");
    for(;;)delay(1000);
  }
  snprintf(telemetryTopic,sizeof(telemetryTopic),"%s/%s/telemetry",TOPIC_PREFIX,DEVICE_ID);
  snprintf(statusTopic,sizeof(statusTopic),"%s/%s/status",TOPIC_PREFIX,DEVICE_ID);
  snprintf(capabilitiesTopic,sizeof(capabilitiesTopic),"%s/%s/capabilities",TOPIC_PREFIX,DEVICE_ID);
  snprintf(commandTopic,sizeof(commandTopic),"%s/%s/command",TOPIC_PREFIX,DEVICE_ID);
  snprintf(ackTopic,sizeof(ackTopic),"%s/%s/command_ack",TOPIC_PREFIX,DEVICE_ID);
  mqtt.setServer(MQTT_HOST,MQTT_PORT);
  snprintf(wifiTopic,sizeof(wifiTopic),"%s/%s/wifi",TOPIC_PREFIX,DEVICE_ID);
  snprintf(alarmsTopic,sizeof(alarmsTopic),"%s/%s/alarms",TOPIC_PREFIX,DEVICE_ID);
  snprintf(authTopic,sizeof(authTopic),"%s/%s/auth",TOPIC_PREFIX,DEVICE_ID);
  snprintf(alarmLogTopic,sizeof(alarmLogTopic),"%s/%s/alarm_log",TOPIC_PREFIX,DEVICE_ID);
  // Alarmes de tensao e corrente leem a telemetria do quadro de comando.
  snprintf(quadroTelemetryTopic,sizeof(quadroTelemetryTopic),"%s/esp32-01/telemetry",TOPIC_PREFIX);
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
        mqtt.subscribe(quadroTelemetryTopic,0);publishAlarms();publishAuth();publishAlarmLog();
        pedirBeep(2,BEEP_HZ,70);  // Dois bipes sempre: placa conectada ao broker.
        Serial.printf("[S3/MQTT] conectado, publicando %s\n",telemetryTopic);
      } else Serial.printf("[S3/MQTT] falha state=%d\n",mqtt.state());
    }
    delay(2);return;
  }

  mqtt.loop();
  relogio::manter(now);  // Hora real para carimbar as medicoes.
  now=millis();
  if(lastPublish==0 || (uint32_t)(now-lastPublish)>=PUBLISH_MS) {
    lastPublish=now;publishTelemetry();
  }
  if(alarmes::eventosMudaram)publishAlarmLog();
  delay(2);
}
