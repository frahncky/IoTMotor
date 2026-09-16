#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <math.h>

// Connection defaults (adjust as needed)
static const char* WIFI_SSID = "IFMA_IOT";
static const char* WIFI_PASS = "";

static const char* MQTT_HOST = "test.mosquitto.org";
static const uint16_t MQTT_PORT = 1883;
static const char* MQTT_USER = "";
static const char* MQTT_PASS = "";

static const char* TOPIC_PREFIX = "iotmotor";
static const char* DEVICE_ID = "esp32-01";

static const bool ACCEPT_COMMAND_REQUEST = true;
static const bool ACCEPT_DIRECT_COMMAND = true;

static const int PIN_RELAY = 2;
static const unsigned long TELEMETRY_INTERVAL_MS = 1000;

WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

char topicTelemetry[96];
char topicStatus[96];
char topicCommand[96];
char topicTelemetryRequest[96];
char topicCommandRequest[96];
char topicCapabilities[96];

unsigned long lastTelemetryMs = 0;
bool motorEnabled = false;
String lastMode = "manual_stop";

struct TelemetrySample {
  float voltage;
  float current;
};

static float simPhase = 0.0f;

float randomRange(float minValue, float maxValue) {
  return minValue + (maxValue - minValue) * (random(0, 10001) / 10000.0f);
}

float clampValue(float value, float minValue, float maxValue) {
  if (value < minValue) {
    return minValue;
  }
  if (value > maxValue) {
    return maxValue;
  }
  return value;
}

void buildTopics() {
  snprintf(topicTelemetry, sizeof(topicTelemetry), "%s/%s/telemetry", TOPIC_PREFIX, DEVICE_ID);
  snprintf(topicStatus, sizeof(topicStatus), "%s/%s/status", TOPIC_PREFIX, DEVICE_ID);
  snprintf(topicCommand, sizeof(topicCommand), "%s/%s/command", TOPIC_PREFIX, DEVICE_ID);
  snprintf(topicTelemetryRequest, sizeof(topicTelemetryRequest), "%s/request/telemetry", TOPIC_PREFIX);
  snprintf(topicCommandRequest, sizeof(topicCommandRequest), "%s/request/command", TOPIC_PREFIX);
  snprintf(topicCapabilities, sizeof(topicCapabilities), "%s/%s/capabilities", TOPIC_PREFIX, DEVICE_ID);
}

void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
  }
}

void publishStatus(const char* value) {
  mqttClient.publish(topicStatus, value, true);
}

void publishCapabilities() {
  StaticJsonDocument<384> doc;
  doc["device_id"] = DEVICE_ID;
  JsonArray fields = doc.createNestedArray("fields");
  fields.add("voltage");
  fields.add("current");
  doc["accepts_command_request"] = ACCEPT_COMMAND_REQUEST;
  doc["accepts_direct_command"] = ACCEPT_DIRECT_COMMAND;
  doc["request_telemetry_topic"] = topicTelemetryRequest;
  doc["request_command_topic"] = topicCommandRequest;
  doc["command_topic"] = topicCommand;
  doc["telemetry_topic"] = topicTelemetry;
  doc["timestamp"] = millis();

  char payload[384];
  size_t n = serializeJson(doc, payload, sizeof(payload));
  mqttClient.publish(topicCapabilities, (const uint8_t*)payload, n, true);
}

void applyCommand(const char* command, const char* mode) {
  if (strcmp(command, "start") == 0) {
    motorEnabled = true;
    lastMode = mode;
    digitalWrite(PIN_RELAY, HIGH);
    publishStatus("motor_started");
    return;
  }

  if (strcmp(command, "stop") == 0) {
    motorEnabled = false;
    lastMode = "manual_stop";
    digitalWrite(PIN_RELAY, LOW);
    publishStatus("motor_stopped");
    return;
  }

  publishStatus("unknown_command");
}

TelemetrySample generateTelemetrySample() {
  TelemetrySample sample;

  simPhase += 0.22f;
  if (simPhase >= 2.0f * PI) {
    simPhase -= 2.0f * PI;
  }

  float voltageWave = sinf(simPhase) * 3.2f + sinf(simPhase * 0.5f) * 1.1f;
  float voltageDrop = motorEnabled ? 1.2f : 0.0f;
  sample.voltage = clampValue(220.0f + voltageWave - voltageDrop + randomRange(-0.5f, 0.5f), 210.0f, 230.0f);

  if (motorEnabled) {
    sample.current = clampValue(5.5f + sinf(simPhase * 1.7f) * 1.2f + randomRange(-0.25f, 0.25f), 3.8f, 8.5f);
  } else {
    sample.current = clampValue(0.12f + randomRange(-0.03f, 0.03f), 0.02f, 0.25f);
  }

  return sample;
}

bool isFieldRequested(JsonVariantConst fieldsVariant, const char* fieldName) {
  if (fieldsVariant.isNull()) {
    return true;
  }

  JsonArrayConst fields = fieldsVariant.as<JsonArrayConst>();
  if (fields.isNull() || fields.size() == 0) {
    return true;
  }

  for (JsonVariantConst item : fields) {
    const char* name = item.as<const char*>();
    if (name != nullptr && strcmp(name, fieldName) == 0) {
      return true;
    }
  }

  return false;
}

void publishTelemetry(bool includeVoltage, bool includeCurrent, const char* requestId) {
  if (!includeVoltage && !includeCurrent) {
    return;
  }

  TelemetrySample sample = generateTelemetrySample();

  StaticJsonDocument<256> doc;
  doc["device_id"] = DEVICE_ID;
  if (includeVoltage) {
    doc["voltage"] = sample.voltage;
  }
  if (includeCurrent) {
    doc["current"] = sample.current;
  }
  doc["motor_on"] = motorEnabled;
  doc["mode"] = lastMode;
  if (requestId != nullptr && strlen(requestId) > 0) {
    doc["request_id"] = requestId;
  }

  char payload[256];
  size_t n = serializeJson(doc, payload, sizeof(payload));
  mqttClient.publish(topicTelemetry, payload, n);
}

void handleTelemetryRequest(const JsonDocument& requestDoc) {
  JsonVariantConst fieldsVariant = requestDoc["fields"];
  const char* requestId = requestDoc["request_id"] | "";

  bool includeVoltage = isFieldRequested(fieldsVariant, "voltage");
  bool includeCurrent = isFieldRequested(fieldsVariant, "current");

  publishTelemetry(includeVoltage, includeCurrent, requestId);
}

void handleCommand(const JsonDocument& commandDoc, bool fromRequestTopic) {
  if (fromRequestTopic && !ACCEPT_COMMAND_REQUEST) {
    return;
  }

  if (!fromRequestTopic && !ACCEPT_DIRECT_COMMAND) {
    return;
  }

  const char* command = commandDoc["command"] | "";
  const char* mode = commandDoc["mode"] | "direct";
  applyCommand(command, mode);
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  StaticJsonDocument<384> doc;
  DeserializationError err = deserializeJson(doc, payload, length);
  if (err) {
    if (strcmp(topic, topicCommand) == 0 || strcmp(topic, topicCommandRequest) == 0) {
      publishStatus("invalid_command_json");
    }
    return;
  }

  if (strcmp(topic, topicCommand) == 0) {
    handleCommand(doc, false);
    return;
  }

  if (strcmp(topic, topicCommandRequest) == 0) {
    handleCommand(doc, true);
    return;
  }

  if (strcmp(topic, topicTelemetryRequest) == 0) {
    handleTelemetryRequest(doc);
  }
}

void connectMqtt() {
  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);

  while (!mqttClient.connected()) {
    String clientId = String("esp32_cmd_") + String(DEVICE_ID);

    bool ok;
    if (strlen(MQTT_USER) > 0) {
      ok = mqttClient.connect(clientId.c_str(), MQTT_USER, MQTT_PASS, topicStatus, 0, true, "offline");
    } else {
      ok = mqttClient.connect(clientId.c_str(), topicStatus, 0, true, "offline");
    }

    if (!ok) {
      delay(1500);
      continue;
    }

    mqttClient.subscribe(topicCommand);
    mqttClient.subscribe(topicCommandRequest);
    mqttClient.subscribe(topicTelemetryRequest);

    publishStatus("online");
    publishCapabilities();
  }
}

void setup() {
  pinMode(PIN_RELAY, OUTPUT);
  digitalWrite(PIN_RELAY, LOW);
  randomSeed((uint32_t)(ESP.getEfuseMac() ^ micros()));

  buildTopics();
  connectWiFi();
  connectMqtt();
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    connectWiFi();
  }

  if (!mqttClient.connected()) {
    connectMqtt();
  }

  mqttClient.loop();

  unsigned long now = millis();
  if (now - lastTelemetryMs >= TELEMETRY_INTERVAL_MS) {
    lastTelemetryMs = now;
    publishTelemetry(true, true, "");
  }
}
