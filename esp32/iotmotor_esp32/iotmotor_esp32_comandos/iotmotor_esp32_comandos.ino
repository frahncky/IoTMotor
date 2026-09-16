/* IoTMotor ESP32-01 — firmware de BANCADA, nao certificado para acionar motor real.
 * Broker publico e MQTT sem autenticacao: mantenha o motor fisicamente desconectado.
 * GPIO32 ligado ao GND por um jumper momentaneo autoriza SOMENTE o teste da saida
 * GPIO2. Sem jumper, o comando remoto de partida e recusado. Remover o jumper,
 * perder Wi-Fi ou perder MQTT desliga a saida imediatamente.
 * Partida estrela-triangulo exige contatores e intertravamento fisico: recusada
 * neste firmware de UM rele. NUNCA ligar o GPIO2 diretamente a um contator.
 *
 * DEMO_MODE=1: todas as grandezas sao simuladas e identificadas no JSON.
 * DEMO_MODE=0: habilite sensores reais e instale suas bibliotecas; campos sem
 * sensor/leitura valida nao sao enviados, nunca preenchidos com numeros falsos.
 * PZEM-004T v3: TX -> GPIO16 (RX2), RX -> GPIO17 (TX2), GND comum;
 * DS18B20: dados -> GPIO4, pull-up 4k7 para 3V3;
 * MPU6050: SDA -> GPIO21, SCL -> GPIO22, GND/3V3.
 */
#define DEMO_MODE 1
#define USE_PZEM 0
#define USE_DS18B20 0
#define USE_MPU6050 0

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <math.h>
#if !DEMO_MODE && USE_PZEM
#include <PZEM004Tv30.h>
#endif
#if !DEMO_MODE && USE_DS18B20
#include <OneWire.h>
#include <DallasTemperature.h>
#endif
#if !DEMO_MODE && USE_MPU6050
#include <Wire.h>
#endif

static const char* WIFI_SSID = "IFMA_IOT";
static const char* WIFI_PASS = ""; // rede aberta, sem senha; nunca grave senhas reais no GitHub
static const char* MQTT_HOST = "test.mosquitto.org";
static const uint16_t MQTT_PORT = 1883; // TCP do ESP32; o navegador usa WSS 8081
static const char* TOPIC_PREFIX = "iotmotor";
static const char* DEVICE_ID = "esp32-01";
static const uint8_t PIN_RELAY = 2;
static const uint8_t PIN_BENCH_ARM = 32; // INPUT_PULLUP: LOW = jumper local conectado ao GND
static const unsigned long TELEMETRY_INTERVAL_MS = 1000UL;
static const unsigned long WIFI_RETRY_MS = 12000UL;
static const unsigned long MQTT_RETRY_MS = 4000UL;

WiFiClient net;
PubSubClient mqtt(net);
char topicTelemetry[96], topicStatus[96], topicCommand[96], topicCapabilities[96];
unsigned long lastTelemetryMs = 0, lastWifiAttempt = 0, lastMqttAttempt = 0;
bool motorEnabled = false;
String lastMode = "manual_stop";
float phase = 0.0f, simulatedTemp = 29.0f, demoEnergyKwh = 0.0f;
uint32_t sequence = 0;
#if !DEMO_MODE && USE_PZEM
PZEM004Tv30* pzem = nullptr;
#endif
#if !DEMO_MODE && USE_DS18B20
OneWire oneWire(4);
DallasTemperature tempSensor(&oneWire);
#endif
#if !DEMO_MODE && USE_MPU6050
bool mpuReady = false;
#endif

bool benchArmed() { return digitalRead(PIN_BENCH_ARM) == LOW; }
void outputOff() {
  digitalWrite(PIN_RELAY, LOW);
  motorEnabled = false;
  lastMode = "manual_stop";
}
void publishStatus(const char* status) {
  Serial.printf("[status] %s\n", status);
  if (mqtt.connected()) mqtt.publish(topicStatus, status, true);
}
void publishCapabilities() {
  StaticJsonDocument<512> doc;
  doc["device_id"] = DEVICE_ID;
  doc["firmware_version"] = "bench-2.0";
  doc["demo"] = static_cast<bool>(DEMO_MODE);
  doc["bench_arm_required"] = true;
  doc["star_delta_supported"] = false;
  JsonArray fields = doc.createNestedArray("fields");
#if DEMO_MODE
  for (const char* name : {"voltage", "current", "power", "pf", "frequency", "energy", "vibration", "temperature"}) fields.add(name);
#else
#if USE_PZEM
  for (const char* name : {"voltage", "current", "power", "pf", "frequency", "energy"}) fields.add(name);
#endif
#if USE_DS18B20
  fields.add("temperature");
#endif
#if USE_MPU6050
  fields.add("vibration");
#endif
#endif
  char payload[512];
  size_t n = serializeJson(doc, payload, sizeof(payload));
  mqtt.publish(topicCapabilities, reinterpret_cast<const uint8_t*>(payload), static_cast<unsigned int>(n), true);
}

void publishTelemetry() {
  if (!mqtt.connected()) return;
  StaticJsonDocument<640> doc;
  doc["device_id"] = DEVICE_ID;
  doc["seq"] = ++sequence;
  doc["demo"] = static_cast<bool>(DEMO_MODE);
  doc["data_source"] = DEMO_MODE ? "simulated" : "sensors";
  doc["bench_armed"] = benchArmed();
  doc["motor_on"] = motorEnabled;
  doc["mode"] = lastMode;
#if DEMO_MODE
  phase += 0.18f;
  if (phase > 2 * PI) phase -= 2 * PI;
  const float voltage = 220.0f + 3.0f * sinf(phase);
  const float current = motorEnabled ? 5.3f + 0.6f * sinf(phase * 1.6f) : 0.08f;
  const float pf = motorEnabled ? 0.86f : 0.97f;
  const float active = voltage * current * pf;
  demoEnergyKwh += active * (TELEMETRY_INTERVAL_MS / 3600000000.0f);
  simulatedTemp += ((motorEnabled ? 46.0f : 29.0f) - simulatedTemp) * 0.025f;
  doc["voltage"] = voltage;
  doc["current"] = current;
  doc["power"] = active;
  doc["pf"] = pf;
  doc["frequency"] = 60.0f + 0.03f * sinf(phase);
  doc["energy"] = demoEnergyKwh;
  doc["vibration"] = motorEnabled ? 0.37f + 0.08f * fabsf(sinf(phase)) : 0.025f;
  doc["temperature"] = simulatedTemp;
#else
#if USE_PZEM
  if (pzem) {
    float v = pzem->voltage();
    float a = pzem->current();
    float p = pzem->power();
    float fp = pzem->pf();
    float f = pzem->frequency();
    float e = pzem->energy();
    if (isfinite(v)) doc["voltage"] = v;
    if (isfinite(a)) doc["current"] = a;
    if (isfinite(p)) doc["power"] = p;
    if (isfinite(fp)) doc["pf"] = fp;
    if (isfinite(f)) doc["frequency"] = f;
    if (isfinite(e)) doc["energy"] = e;
  }
#endif
#if USE_DS18B20
  tempSensor.requestTemperatures();
  float t = tempSensor.getTempCByIndex(0);
  if (isfinite(t) && t > -55.0f && t < 125.0f && t != 85.0f) doc["temperature"] = t;
#endif
#if USE_MPU6050
  if (mpuReady) {
    float sum = 0.0f;
    uint8_t valid = 0;
    for (uint8_t i = 0; i < 20; ++i) {
      Wire.beginTransmission(0x68);
      Wire.write(0x3B);
      if (Wire.endTransmission(false) != 0 || Wire.requestFrom(0x68, 6, true) != 6) break;
      int16_t x = (int16_t)((Wire.read() << 8) | Wire.read());
      int16_t y = (int16_t)((Wire.read() << 8) | Wire.read());
      int16_t z = (int16_t)((Wire.read() << 8) | Wire.read());
      float magnitude = sqrtf(float(x)*x + float(y)*y + float(z)*z) / 16384.0f;
      float deviation = magnitude - 1.0f;
      sum += deviation * deviation;
      ++valid;
      delay(2);
    }
    if (valid >= 10) doc["vibration"] = sqrtf(sum / valid); // estimativa RMS em g, exige calibracao
  }
#endif
#endif
  char payload[640];
  size_t n = serializeJson(doc, payload, sizeof(payload));
  bool ok = mqtt.publish(topicTelemetry, reinterpret_cast<const uint8_t*>(payload), static_cast<unsigned int>(n), false);
  if (!ok) Serial.printf("[MQTT] falha ao publicar %u bytes; verifique buffer/conexao\n", static_cast<unsigned int>(n));
  else if (sequence % 10 == 1) Serial.printf("[telemetry] seq=%lu, bytes=%u, demo=%d, armado=%d\n", static_cast<unsigned long>(sequence), static_cast<unsigned int>(n), DEMO_MODE, benchArmed());
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  if (strcmp(topic, topicCommand) != 0) return; // sem broadcast, evita acionar outros dispositivos
  StaticJsonDocument<384> cmd;
  if (deserializeJson(cmd, payload, length)) { publishStatus("invalid_command_json"); return; }
  const char* device = cmd["device_id"] | "";
  const char* command = cmd["command"] | "";
  const char* mode = cmd["mode"] | "";
  if (strcmp(device, DEVICE_ID) != 0) { publishStatus("wrong_device_id"); return; }
  if (strcmp(command, "stop") == 0) { outputOff(); publishStatus("motor_stopped"); publishTelemetry(); return; }
  if (strcmp(command, "start") != 0) { publishStatus("unknown_command"); return; }
  if (strcmp(mode, "star_delta") == 0) { publishStatus("unsupported_star_delta_hardware"); return; }
  if (strcmp(mode, "direct") != 0) { publishStatus("unsupported_start_mode"); return; }
  if (!benchArmed()) { outputOff(); publishStatus("physical_arm_required"); return; }
  if (WiFi.status() != WL_CONNECTED || !mqtt.connected()) { outputOff(); return; }
  // SOMENTE LED/rele de bancada desconectado da carga; nunca partida real sem protecoes.
  digitalWrite(PIN_RELAY, HIGH);
  motorEnabled = true;
  lastMode = "direct";
  publishStatus("motor_started");
  publishTelemetry();
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_RELAY, OUTPUT);
  pinMode(PIN_BENCH_ARM, INPUT_PULLUP);
  outputOff();
  snprintf(topicTelemetry, sizeof(topicTelemetry), "%s/%s/telemetry", TOPIC_PREFIX, DEVICE_ID);
  snprintf(topicStatus, sizeof(topicStatus), "%s/%s/status", TOPIC_PREFIX, DEVICE_ID);
  snprintf(topicCommand, sizeof(topicCommand), "%s/%s/command", TOPIC_PREFIX, DEVICE_ID);
  snprintf(topicCapabilities, sizeof(topicCapabilities), "%s/%s/capabilities", TOPIC_PREFIX, DEVICE_ID);
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(onMqttMessage);
  mqtt.setBufferSize(1024);
#if !DEMO_MODE && USE_PZEM
  pzem = new PZEM004Tv30(Serial2, 16, 17);
#endif
#if !DEMO_MODE && USE_DS18B20
  tempSensor.begin();
#endif
#if !DEMO_MODE && USE_MPU6050
  Wire.begin(21, 22);
  Wire.beginTransmission(0x68);
  Wire.write(0x6B); Wire.write(0x00);
  mpuReady = Wire.endTransmission() == 0;
#endif
  WiFi.mode(WIFI_STA);
  Serial.printf("[boot] %s, rede %s, broker %s:%u, demo=%d\n", DEVICE_ID, WIFI_SSID, MQTT_HOST, MQTT_PORT, DEMO_MODE);
}

void loop() {
  const unsigned long now = millis();
  if (motorEnabled && !benchArmed()) { outputOff(); publishStatus("bench_disarmed_stop"); }
  if (WiFi.status() != WL_CONNECTED) {
    if (motorEnabled) outputOff();
    if (now - lastWifiAttempt >= WIFI_RETRY_MS || lastWifiAttempt == 0) {
      lastWifiAttempt = now;
      Serial.printf("[WiFi] conectando: status=%d\n", WiFi.status());
      if (strlen(WIFI_PASS) == 0) WiFi.begin(WIFI_SSID); else WiFi.begin(WIFI_SSID, WIFI_PASS);
    }
    delay(10);
    return;
  }
  if (!mqtt.connected()) {
    if (motorEnabled) outputOff();
    if (now - lastMqttAttempt >= MQTT_RETRY_MS || lastMqttAttempt == 0) {
      lastMqttAttempt = now;
      Serial.printf("[MQTT] Wi-Fi IP=%s; conectando %s:%u\n", WiFi.localIP().toString().c_str(), MQTT_HOST, MQTT_PORT);
      String clientId = String("iotmotor_bench_") + String((uint32_t)ESP.getEfuseMac(), HEX);
      bool ok = mqtt.connect(clientId.c_str(), topicStatus, 0, true, "offline");
      if (!ok) Serial.printf("[MQTT] falha estado=%d\n", mqtt.state());
      else {
        mqtt.subscribe(topicCommand);
        publishStatus("online");
        publishCapabilities();
        Serial.printf("[MQTT] conectado; recebendo em %s\n", topicCommand);
      }
    }
    delay(10);
    return;
  }
  mqtt.loop();
  if (now - lastTelemetryMs >= TELEMETRY_INTERVAL_MS) {
    lastTelemetryMs = now;
    publishTelemetry();
  }
  delay(5);
}
