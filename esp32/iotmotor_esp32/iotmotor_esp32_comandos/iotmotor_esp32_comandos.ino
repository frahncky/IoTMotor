/* IoTMotor — ESP32-01: modulo de comandos e medicao eletrica com PZEM-004T v3.
 * Este sketch de UM rele e destinado apenas a ensaios com motor DESCONECTADO.
 * Broker MQTT publico nao autentica comandos. GPIO32 aterrado por jumper local
 * habilita exclusivamente o teste da saida GPIO2. Remover o jumper ou perder
 * conectividade desliga a saida. NAO substitui intertravamentos/protecao fisica.
 * Partida estrela-triangulo e recusada: requer contatores e intertravamento.
 * PZEM TX -> GPIO16 (RX2); PZEM RX -> GPIO17 (TX2); GND comum; alimente o
 * modulo segundo as especificacoes do fabricante e com seguranca eletrica.
 * REAIS por padrao; DEMO_MODE=1 permite testar graficos com simulacao marcada.
 * Bibliotecas: PubSubClient, ArduinoJson 6.x, PZEM004Tv30.
 */
#define DEMO_MODE 0
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <math.h>
#if !DEMO_MODE
#include <PZEM004Tv30.h>
#endif

static const char* WIFI_SSID = "IFMA_IOT";
static const char* WIFI_PASS = ""; // rede aberta
static const char* MQTT_HOST = "test.mosquitto.org";
static const uint16_t MQTT_PORT = 1883;
static const char* TOPIC_PREFIX = "iotmotor";
static const char* DEVICE_ID = "esp32-01";
static const uint8_t PIN_TEST_OUTPUT = 2;
static const uint8_t PIN_BENCH_ARM = 32; // jumper GPIO32 -> GND; NUNCA aplicar tensao externa
static const unsigned long MQTT_RETRY_MS = 4000UL;
static const unsigned long WIFI_RETRY_MS = 12000UL;
static const unsigned long TELEMETRY_MS = 1000UL;
static const unsigned long PZEM_POLL_MS = 3000UL;

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
char telemetryTopic[96], statusTopic[96], commandTopic[96], capabilitiesTopic[96];
unsigned long lastWifiAttempt = 0, lastMqttAttempt = 0, lastTelemetry = 0, lastPzemPoll = 0;
bool outputEnabled = false, pzemOk = false;
String currentMode = "manual_stop";
uint32_t sequence = 0;

struct ElectricalReading {
  float voltage = NAN, current = NAN, power = NAN;
  float pf = NAN, frequency = NAN, energy = NAN;
} electrical;
#if !DEMO_MODE
PZEM004Tv30* pzem = nullptr;
#else
float demoPhase = 0.0f, demoEnergy = 0.0f;
#endif

bool benchArmed() { return digitalRead(PIN_BENCH_ARM) == LOW; }
void off() {
  digitalWrite(PIN_TEST_OUTPUT, LOW);
  outputEnabled = false;
  currentMode = "manual_stop";
}
void status(const char* message) {
  Serial.printf("[status] %s\n", message);
  if (mqtt.connected()) mqtt.publish(statusTopic, message, true);
}

void pollPzem() {
#if DEMO_MODE
  demoPhase += 0.18f;
  if (demoPhase >= 2.0f * PI) demoPhase -= 2.0f * PI;
  electrical.voltage = 220.0f + 3.0f * sinf(demoPhase);
  electrical.current = outputEnabled ? 5.0f + 0.3f * sinf(demoPhase) : 0.08f;
  electrical.pf = outputEnabled ? 0.86f : 0.97f;
  electrical.power = electrical.voltage * electrical.current * electrical.pf;
  electrical.frequency = 60.0f;
  demoEnergy += electrical.power * PZEM_POLL_MS / 3600000000.0f;
  electrical.energy = demoEnergy;
  pzemOk = true;
#else
  if (!pzem) { pzemOk = false; return; }
  ElectricalReading next;
  next.voltage = pzem->voltage();
  next.current = pzem->current();
  next.power = pzem->power();
  next.pf = pzem->pf();
  next.frequency = pzem->frequency();
  next.energy = pzem->energy();
  // Tensao e corrente validas comprovam que o instrumento respondeu; zero V
  // nao autoriza acionamento. Em falha, descarta leitura anterior (nao congela).
  pzemOk = isfinite(next.voltage) && next.voltage > 0.0f &&
           isfinite(next.current) && next.current >= 0.0f;
  electrical = pzemOk ? next : ElectricalReading{};
#endif
  Serial.printf("[PZEM] leitura %s, tensao=%.1f V, corrente=%.3f A\n",
                pzemOk ? "valida" : "indisponivel", electrical.voltage, electrical.current);
  if (outputEnabled && !pzemOk) { off(); status("sensor_unavailable_stop"); }
}

void publishCapabilities() {
  StaticJsonDocument<384> doc;
  doc["device_id"] = DEVICE_ID;
  doc["firmware_version"] = "bench-pzem-2.1";
  doc["demo"] = (DEMO_MODE != 0);
  doc["bench_arm_required"] = true;
  doc["star_delta_supported"] = false;
  JsonArray fields = doc.createNestedArray("fields");
  for (const char* field : {"voltage","current","power","pf","frequency","energy"}) fields.add(field);
  char buffer[384];
  const size_t n = serializeJson(doc, buffer, sizeof(buffer));
  if (n) mqtt.publish(capabilitiesTopic, (const uint8_t*)buffer, (unsigned int)n, true);
}

void publishTelemetry() {
  if (!mqtt.connected()) return;
  StaticJsonDocument<512> doc;
  doc["device_id"] = DEVICE_ID;
  doc["seq"] = ++sequence;
  doc["demo"] = (DEMO_MODE != 0);
  doc["data_source"] = DEMO_MODE ? "simulated" : "pzem004t";
  doc["sensor_ok"] = pzemOk;
  doc["bench_armed"] = benchArmed();
  doc["motor_on"] = outputEnabled; // estado solicitado da saida; NAO feedback de contator
  doc["mode"] = currentMode;
  if (pzemOk) {
    if (isfinite(electrical.voltage)) doc["voltage"] = electrical.voltage;
    if (isfinite(electrical.current)) doc["current"] = electrical.current;
    if (isfinite(electrical.power)) doc["power"] = electrical.power;
    if (isfinite(electrical.pf)) doc["pf"] = electrical.pf;
    if (isfinite(electrical.frequency)) doc["frequency"] = electrical.frequency;
    if (isfinite(electrical.energy)) doc["energy"] = electrical.energy;
  }
  char buffer[512];
  size_t n = serializeJson(doc, buffer, sizeof(buffer));
  bool ok = n && mqtt.publish(telemetryTopic, (const uint8_t*)buffer, (unsigned int)n, false);
  if (!ok) Serial.printf("[MQTT] erro publicando telemetria (%u bytes), state=%d\n", (unsigned int)n, mqtt.state());
  else if (sequence % 10 == 1) Serial.printf("[telemetry] seq=%lu, sensor_ok=%d, demo=%d\n", (unsigned long)sequence, pzemOk, DEMO_MODE);
}

void onMessage(char* topic, byte* payload, unsigned int length) {
  if (strcmp(topic, commandTopic) != 0) return; // nao aceita broadcast
  StaticJsonDocument<384> data;
  if (deserializeJson(data, payload, length)) { status("invalid_command_json"); return; }
  const char* device = data["device_id"] | "";
  const char* command = data["command"] | "";
  const char* mode = data["mode"] | "";
  if (strcmp(device, DEVICE_ID) != 0) { status("wrong_device_id"); return; }
  if (strcmp(command, "stop") == 0) { off(); status("motor_stopped"); publishTelemetry(); return; }
  if (strcmp(command, "start") != 0) { status("unknown_command"); return; }
  if (strcmp(mode, "star_delta") == 0) { status("unsupported_star_delta_hardware"); return; }
  if (strcmp(mode, "direct") != 0) { status("unsupported_start_mode"); return; }
  if (!benchArmed()) { off(); status("physical_arm_required"); return; }
  if (!pzemOk) { off(); status("pzem_unavailable_start_blocked"); return; }
  if (!mqtt.connected() || WiFi.status() != WL_CONNECTED) { off(); return; }
  // Apenas LED/rele SEM motor ligado; nunca controle real pelo broker publico.
  digitalWrite(PIN_TEST_OUTPUT, HIGH);
  outputEnabled = true;
  currentMode = "direct";
  status("motor_started");
  publishTelemetry();
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_TEST_OUTPUT, OUTPUT);
  pinMode(PIN_BENCH_ARM, INPUT_PULLUP);
  off();
  snprintf(telemetryTopic,sizeof(telemetryTopic),"%s/%s/telemetry",TOPIC_PREFIX,DEVICE_ID);
  snprintf(statusTopic,sizeof(statusTopic),"%s/%s/status",TOPIC_PREFIX,DEVICE_ID);
  snprintf(commandTopic,sizeof(commandTopic),"%s/%s/command",TOPIC_PREFIX,DEVICE_ID);
  snprintf(capabilitiesTopic,sizeof(capabilitiesTopic),"%s/%s/capabilities",TOPIC_PREFIX,DEVICE_ID);
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(onMessage);
  mqtt.setBufferSize(1024);
#if !DEMO_MODE
  pzem = new PZEM004Tv30(Serial2, 16, 17);
#endif
  WiFi.mode(WIFI_STA);
  Serial.printf("[boot] %s Wi-Fi=%s MQTT=%s:%u PZEM=%s\n", DEVICE_ID, WIFI_SSID, MQTT_HOST, MQTT_PORT, DEMO_MODE ? "simulado" : "real");
}

void loop() {
  unsigned long now = millis();
  if (outputEnabled && !benchArmed()) { off(); status("bench_disarmed_stop"); }
  if (WiFi.status() != WL_CONNECTED) {
    if (outputEnabled) off();
    if (lastWifiAttempt == 0 || now - lastWifiAttempt >= WIFI_RETRY_MS) {
      lastWifiAttempt = now;
      Serial.printf("[WiFi] conectando; status=%d\n", WiFi.status());
      if (strlen(WIFI_PASS)) WiFi.begin(WIFI_SSID,WIFI_PASS);
      else WiFi.begin(WIFI_SSID);
    }
    delay(10);
    return;
  }
  if (!mqtt.connected()) {
    if (outputEnabled) off();
    if (lastMqttAttempt == 0 || now - lastMqttAttempt >= MQTT_RETRY_MS) {
      lastMqttAttempt = now;
      Serial.printf("[MQTT] IP=%s, conectando %s:%u\n",WiFi.localIP().toString().c_str(),MQTT_HOST,MQTT_PORT);
      String id = String("iotmotor_bench_") + String((uint32_t)ESP.getEfuseMac(), HEX);
      if (mqtt.connect(id.c_str(),statusTopic,0,true,"offline")) {
        mqtt.subscribe(commandTopic);
        status("online");
        publishCapabilities();
        Serial.printf("[MQTT] conectado, topico %s\n",commandTopic);
      } else Serial.printf("[MQTT] falha state=%d\n",mqtt.state());
    }
    delay(10);
    return;
  }
  mqtt.loop();
  now = millis();
  if (lastPzemPoll == 0 || now - lastPzemPoll >= PZEM_POLL_MS) {
    lastPzemPoll = now;
    pollPzem();
  }
  if (lastTelemetry == 0 || now - lastTelemetry >= TELEMETRY_MS) {
    lastTelemetry = now;
    publishTelemetry();
  }
  delay(5);
}
