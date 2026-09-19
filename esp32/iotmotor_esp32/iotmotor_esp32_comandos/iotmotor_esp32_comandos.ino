/*
  IoTMotor — ESP32-01 (DevKit V1)
  Hardware do sketch de bancada funcional:
    PZEM-004T TX -> GPIO16 (RX2), RX -> GPIO17 (TX2)
    LCD I2C 20x4 SDA -> GPIO21, SCL -> GPIO22, endereco 0x27
    Reles K1..K4 -> GPIO19, GPIO18, GPIO23, GPIO27

  Nao hospeda pagina web, nao exige chave de comando nem jumper GPIO32.
  Painel Cloudflare usa MQTT WSS; ESP32 usa MQTT sobre WebSocket na porta 8080,
  porque a rede IFMA_IOT bloqueia as portas MQTT 1883 e 8883.
  APENAS para ensaios de reles sem motor ou contatores no broker publico.
  Bibliotecas: PZEM004Tv30, LiquidCrystal I2C, PubSubClient, ArduinoJson 6.
*/
#include <WiFi.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <PZEM004Tv30.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <math.h>
#include <esp_system.h>
#include "mqtt_websocket_client.h"

// Rede local: crie wifi_local.h na pasta do sketch (fora do Git) a partir de
// wifi_local.exemplo.h para usar outra rede sem publicar a senha no GitHub.
#if __has_include("wifi_local.h")
#include "wifi_local.h"
#endif
#ifndef WIFI_SSID_LOCAL
#define WIFI_SSID_LOCAL "IFMA_IOT"
#define WIFI_PASSWORD_LOCAL ""
#endif
// Redes de wifi_local.h: so semeiam a lista gravada na placa no primeiro boot.
// Depois, a lista e a ordem sao definidas pela aba "Wi-Fi" do painel.
const char* const REDES_INICIAIS[] = {
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
const char* const SENHAS_INICIAIS[] = {
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
constexpr unsigned long WIFI_RETRY_MS = 10000UL;
unsigned long ultimaTentativaWifi = 0;

constexpr uint8_t NUM_RELES = 4;
const uint8_t PINOS_RELES[NUM_RELES] = {19, 18, 23, 27};
bool estadoReles[NUM_RELES] = {false, false, false, false};
// Preserva a polaridade do sketch funcional; altere apenas se o modulo for ativo em LOW.
const bool RELE_ATIVO_EM_NIVEL_BAIXO = false;
constexpr uint8_t nivelLigado() { return RELE_ATIVO_EM_NIVEL_BAIXO ? LOW : HIGH; }
constexpr uint8_t nivelDesligado() { return RELE_ATIVO_EM_NIVEL_BAIXO ? HIGH : LOW; }

constexpr uint8_t LCD_ENDERECO = 0x27;
constexpr uint8_t LCD_COLUNAS = 20;
constexpr uint8_t LCD_LINHAS = 4;
constexpr uint8_t LCD_SDA = 21;
constexpr uint8_t LCD_SCL = 22;
// Criado apos a varredura I2C: modulos PCF8574 usam 0x27 ou 0x3F conforme o fabricante.
LiquidCrystal_I2C* lcd = nullptr;
char lcdCache[LCD_LINHAS][LCD_COLUNAS + 1];
bool lcdPrecisaAtualizar = true;
unsigned long ultimaAtualizacaoLcd = 0;
constexpr unsigned long INTERVALO_LCD_MS = 1000UL;

constexpr uint8_t PZEM_RX_PIN = 16;
constexpr uint8_t PZEM_TX_PIN = 17;
PZEM004Tv30* pzem = nullptr;
float ultimaTensao = 0, ultimaCorrente = 0, ultimaPotencia = 0;
float ultimaEnergia = 0, ultimaFrequencia = 0, ultimoFatorPotencia = 0;
bool pzemOk = false;
unsigned long ultimaLeituraPzem = 0;
constexpr unsigned long INTERVALO_PZEM_MS = 3000UL;

static const char* MQTT_HOST = "test.mosquitto.org";
static const uint16_t MQTT_PORT = 8080;  // MQTT sobre WebSocket (ws://)
static const char* DEVICE_ID = "esp32-01";
MqttWebSocketClient mqttTransport;
PubSubClient mqttClient(mqttTransport);
char topicoTelemetria[80], topicoStatus[80], topicoCapacidades[80];
char topicoComandos[80], topicoResposta[80], topicoWifi[80];
constexpr unsigned long MQTT_RETRY_MS = 6000UL;
constexpr unsigned long MQTT_PUBLISH_MS = 1000UL;
unsigned long ultimaTentativaMqtt = 0, ultimaPublicacaoMqtt = 0;
uint32_t sequenciaMqtt = 0;

// Ajuda a separar queda de tensao (brownout) de travamento (watchdog/panico).
const char* motivoReinicio() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return "energizacao";
    case ESP_RST_EXT: return "reset externo";
    case ESP_RST_SW: return "reinicio por software";
    case ESP_RST_PANIC: return "travamento (panico)";
    case ESP_RST_INT_WDT: return "watchdog de interrupcao";
    case ESP_RST_TASK_WDT: return "watchdog de tarefa";
    case ESP_RST_WDT: return "watchdog";
    case ESP_RST_BROWNOUT: return "QUEDA DE TENSAO (brownout)";
    case ESP_RST_DEEPSLEEP: return "saida de deep sleep";
    default: return "desconhecido";
  }
}

void aplicarEstadoRele(uint8_t indice) {
  if (indice >= NUM_RELES) return;
  digitalWrite(PINOS_RELES[indice], estadoReles[indice] ? nivelLigado() : nivelDesligado());
}

#define OTA_ARQUIVO "esp32-01.bin"
#define PORTAL_NOME "IoTMotor-esp32-01"
constexpr uint16_t PORTAL_SEGUNDOS = 180;
#include "ota_update.h"
#include "wifi_portal.h"
#include "iotmotor_profiles.h"
#include "iotmotor_mqtt_control.h"

void imprimirLinhaCompleta(uint8_t linha, const char* texto) {
  if (linha >= LCD_LINHAS) return;
  char buffer[LCD_COLUNAS + 1];
  snprintf(buffer, sizeof(buffer), "%-*.*s", LCD_COLUNAS, LCD_COLUNAS, texto);
  if (!strcmp(buffer, lcdCache[linha])) return;
  strcpy(lcdCache[linha], buffer);
  if (!lcd) return;  // Cache segue para a telemetria mesmo sem display.
  lcd->setCursor(0, linha);
  lcd->print(buffer);
}

// Varre o barramento I2C e retorna o endereco do LCD (prefere LCD_ENDERECO), ou 0.
uint8_t detectarLcd() {
  uint8_t achado = 0;
  Serial.print("[I2C] dispositivos:");
  for (uint8_t endereco = 1; endereco < 127; ++endereco) {
    Wire.beginTransmission(endereco);
    if (Wire.endTransmission() != 0) continue;
    Serial.printf(" 0x%02X", endereco);
    const bool pcf8574 = (endereco >= 0x20 && endereco <= 0x27) || (endereco >= 0x38 && endereco <= 0x3F);
    if (pcf8574 && (!achado || endereco == LCD_ENDERECO)) achado = endereco;
  }
  if (achado) Serial.printf("\n[LCD] usando endereco 0x%02X\n", achado);
  else Serial.println(" nenhum\n[LCD] nao encontrado: confira VCC 5V, GND, SDA GPIO21 e SCL GPIO22");
  return achado;
}

void atualizarLcd() {
  char buffer[48];
  if (WiFi.status() == WL_CONNECTED)
    snprintf(buffer, sizeof(buffer), "IP:%s", WiFi.localIP().toString().c_str());
  else snprintf(buffer, sizeof(buffer), "WiFi desconectado");
  imprimirLinhaCompleta(0, buffer);
  if (pzemOk) snprintf(buffer, sizeof(buffer), "V:%5.1f  I:%6.2fA", ultimaTensao, ultimaCorrente);
  else snprintf(buffer, sizeof(buffer), "PZEM sem leitura");
  imprimirLinhaCompleta(1, buffer);
  if (pzemOk) snprintf(buffer, sizeof(buffer), "P:%4.0fW E:%7.2fkWh", ultimaPotencia, ultimaEnergia);
  else buffer[0] = '\0';
  imprimirLinhaCompleta(2, buffer);
  snprintf(buffer, sizeof(buffer), "R1:%c R2:%c R3:%c R4:%c",
           estadoReles[0] ? 'L' : 'D', estadoReles[1] ? 'L' : 'D',
           estadoReles[2] ? 'L' : 'D', estadoReles[3] ? 'L' : 'D');
  imprimirLinhaCompleta(3, buffer);
  lcdPrecisaAtualizar = false;
}

void manterWifi(unsigned long agora) {
  static bool estavaConectado = false;
  if (WiFi.status() == WL_CONNECTED) {
    if (!estavaConectado) {
      estavaConectado = true;
      Serial.print("[WiFi] IP: ");
      Serial.println(WiFi.localIP());
      lcdPrecisaAtualizar = true;
    }
    return;
  }
  if (estavaConectado) {
    estavaConectado = false;
    Serial.println("[WiFi] desconectado");
    lcdPrecisaAtualizar = true;
  }
  if (agora - ultimaTentativaWifi < WIFI_RETRY_MS) return;
  ultimaTentativaWifi = agora;
  wifistore::conectarEmOrdem(8000);  // Redes visiveis, na ordem da lista.
}

void lerPzem() {
  if (!pzem) {pzemOk = false; return;}
  const float tensao = pzem->voltage();
  // Evita encadear varios timeouts Modbus se o primeiro registrador falhar.
  if (!isfinite(tensao)) {
    if (pzemOk) Serial.println("[PZEM] leitura perdida");
    pzemOk = false;
    lcdPrecisaAtualizar = true;
    return;
  }
  const float corrente = pzem->current();
  const float potencia = pzem->power();
  const float energia = pzem->energy();
  const float frequencia = pzem->frequency();
  const float fp = pzem->pf();
  if (!isfinite(corrente) || !isfinite(potencia) || !isfinite(energia) ||
      !isfinite(frequencia) || !isfinite(fp)) {
    pzemOk = false;
    lcdPrecisaAtualizar = true;
    return;
  }
  ultimaTensao = tensao; ultimaCorrente = corrente; ultimaPotencia = potencia;
  ultimaEnergia = energia; ultimaFrequencia = frequencia; ultimoFatorPotencia = fp;
  if (!pzemOk) Serial.println("[PZEM] conectado");
  pzemOk = true;
  lcdPrecisaAtualizar = true;
}

void publicarCapacidades() {
  if (!mqttClient.connected()) return;
  StaticJsonDocument<384> doc;
  doc["device_id"] = DEVICE_ID;
  doc["role"] = "actuator_mqtt";
  doc["firmware_version"] = "v10-mqtt-websocket";
  doc["accepts_direct_command"] = true;
  doc["accepts_command_request"] = false;
  doc["command_auth"] = "none";
  doc["relay_commanded_only"] = true;
  doc["requires_gpio32_arm"] = false;
  JsonArray fields = doc.createNestedArray("fields");
  for (const char* field : {"voltage", "current", "power", "energy", "frequency", "pf"})
    fields.add(field);
  char payload[384];
  size_t len = serializeJson(doc, payload, sizeof(payload));
  if (len) mqttClient.publish(topicoCapacidades, reinterpret_cast<const uint8_t*>(payload),
                              static_cast<unsigned int>(len), true);
}

void publicarTelemetriaMqtt() {
  if (!mqttClient.connected()) return;
  StaticJsonDocument<1024> doc;
  doc["device_id"] = DEVICE_ID;
  doc["seq"] = ++sequenciaMqtt;
  doc["boot"] = sessaoControle;
  doc["remote_control_ready"] = controleMqttConfigurado;
  // Campo de compatibilidade: pronto para comandos; NAO representa jumper fisico.
  doc["bench_armed"] = true;
  doc["start_phase"] = nomeEtapa();
  doc["reset_reason"] = motivoReinicio();
  if (WiFi.status() == WL_CONNECTED) doc["wifi_ip"] = WiFi.localIP().toString();
  doc["demo"] = false;
  doc["data_source"] = "pzem004t";
  doc["pzem_ok"] = pzemOk;
  doc["sensor_ok"] = pzemOk;
  doc["relay_commanded_only"] = true;
  doc["state"] = "manual_relays";
  doc["mode"] = etapaPartida ? (modoPartida == 1 ? "star_delta_bench" : "direct_bench") : "manual_relays";
  if (pzemOk) {
    doc["voltage"] = ultimaTensao;
    doc["current"] = ultimaCorrente;
    doc["power"] = ultimaPotencia;
    doc["energy"] = ultimaEnergia;
    doc["frequency"] = ultimaFrequencia;
    doc["pf"] = ultimoFatorPotencia;
  }
  JsonArray pins = doc.createNestedArray("relay_pins");
  JsonArray relays = doc.createNestedArray("relays");
  for (uint8_t i = 0; i < NUM_RELES; ++i) {
    pins.add(PINOS_RELES[i]);
    relays.add(estadoReles[i]);
  }
  JsonArray lines = doc.createNestedArray("lcd");
  for (uint8_t i = 0; i < LCD_LINHAS; ++i) lines.add(lcdCache[i]);
  char payload[1024];
  size_t len = serializeJson(doc, payload, sizeof(payload));
  if (!len || !mqttClient.publish(topicoTelemetria, reinterpret_cast<const uint8_t*>(payload),
                                   static_cast<unsigned int>(len), false))
    Serial.printf("[MQTT] falha telemetria, bytes=%u rc=%d\n", (unsigned int)len, mqttClient.state());
}

void manterMqtt(unsigned long agora) {
  if (WiFi.status() != WL_CONNECTED) return;
  if (mqttClient.connected()) {mqttClient.loop();return;}
  if (ultimaTentativaMqtt && agora - ultimaTentativaMqtt < MQTT_RETRY_MS) return;
  ultimaTentativaMqtt = agora;
  const String clientId = String("iotmotor_v9_") + String((uint32_t)ESP.getEfuseMac(), HEX);
  if (mqttClient.connect(clientId.c_str(), topicoStatus, 0, true, "offline")) {
    mqttClient.publish(topicoStatus, "online", true);
    if (!mqttClient.subscribe(topicoComandos, 1))
      Serial.println("[MQTT] falha ao assinar comandos");
    publicarCapacidades();
    publicarRedes();
    Serial.println("[MQTT] conectado: comandos e telemetria ativos");
  } else Serial.printf("[MQTT] falha rc=%d\n", mqttClient.state());
}

void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println("=== IoTMotor ESP32-01 / MQTT sem chave e sem jumper ===");
  Serial.printf("[BOOT] motivo do ultimo reinicio: %s\n", motivoReinicio());
  // Repouso ANTES de configurar saidas para evitar pulso no boot.
  for (uint8_t i = 0; i < NUM_RELES; ++i) {
    digitalWrite(PINOS_RELES[i], nivelDesligado());
    pinMode(PINOS_RELES[i], OUTPUT);
    digitalWrite(PINOS_RELES[i], nivelDesligado());
    estadoReles[i] = false;
  }
  for (uint8_t i = 0; i < LCD_LINHAS; ++i) lcdCache[i][0] = '\0';
  Wire.begin(LCD_SDA, LCD_SCL);
  if (const uint8_t endereco = detectarLcd()) {
    lcd = new LiquidCrystal_I2C(endereco, LCD_COLUNAS, LCD_LINHAS);
    lcd->init();
    lcd->backlight();
    lcd->clear();
  }
  imprimirLinhaCompleta(0, "Iniciando ESP32...");
  imprimirLinhaCompleta(1, "Conectando WiFi...");
  // PZEM criado depois da inicializacao do core.
  pzem = new PZEM004Tv30(Serial2, PZEM_RX_PIN, PZEM_TX_PIN);
  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);
  WiFi.setSleep(false);
  wifistore::carregar(REDES_INICIAIS, SENHAS_INICIAIS,
                      sizeof(REDES_INICIAIS) / sizeof(REDES_INICIAIS[0]));
  wifistore::prepararChaves();
  Serial.printf("[WiFi] %u rede(s) na lista da placa\n", wifistore::total);
  ultimaTentativaWifi = millis();
  // Nenhuma rede da lista respondeu: so o portal permite cadastrar sem cabo.
  if (!wifistore::conectarEmOrdem(10000)) {
    imprimirLinhaCompleta(1, "Config WiFi: " PORTAL_NOME);
    abrirPortalDeRede(PORTAL_NOME, PORTAL_SEGUNDOS);
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("[WiFi] IP: ");
    Serial.println(WiFi.localIP());
  } else Serial.println("[WiFi] aguardando reconexao");
  iniciarControleMqtt();
  snprintf(topicoTelemetria, sizeof(topicoTelemetria), "iotmotor/%s/telemetry", DEVICE_ID);
  snprintf(topicoStatus, sizeof(topicoStatus), "iotmotor/%s/status", DEVICE_ID);
  snprintf(topicoCapacidades, sizeof(topicoCapacidades), "iotmotor/%s/capabilities", DEVICE_ID);
  snprintf(topicoComandos, sizeof(topicoComandos), "iotmotor/%s/command", DEVICE_ID);
  snprintf(topicoResposta, sizeof(topicoResposta), "iotmotor/%s/command_ack", DEVICE_ID);
  snprintf(topicoWifi, sizeof(topicoWifi), "iotmotor/%s/wifi", DEVICE_ID);
  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setBufferSize(1536);
  mqttClient.setCallback(receberComandoMqtt);
  lerPzem();
  ultimaLeituraPzem = millis();
  if (lcd) lcd->clear();
  for (uint8_t i = 0; i < LCD_LINHAS; ++i) lcdCache[i][0] = '\0';
  atualizarLcd();
  ultimaAtualizacaoLcd = millis();
}

void loop() {
  const unsigned long agora = millis();
  manterWifi(agora);
  manterMqtt(agora);
  // Perda de MQTT/Wi-Fi desliga as saidas, mas so apos TOLERANCIA_SEM_LINK_MS,
  // para nao desarmar o ensaio em quedas curtas do broker publico.
  const bool comLink = mqttClient.connected() && WiFi.status() == WL_CONNECTED;
  if (comLink) inicioSemLink = 0;
  else if (!inicioSemLink) inicioSemLink = agora;
  const bool saidasAtivas = etapaPartida || estadoReles[0] || estadoReles[1] ||
                            estadoReles[2] || estadoReles[3];
  if (!comLink && saidasAtivas && decorrido(agora, inicioSemLink) > (int32_t)TOLERANCIA_SEM_LINK_MS) {
    pararBancada();
    Serial.printf("[BANCADA] saidas desligadas: %lu s sem MQTT/Wi-Fi\n",
                  TOLERANCIA_SEM_LINK_MS / 1000UL);
  }
  manterPartidaBancada(agora);
  if (agora - ultimaLeituraPzem >= INTERVALO_PZEM_MS) {
    ultimaLeituraPzem = agora;
    lerPzem();
  }
  if (lcdPrecisaAtualizar || agora - ultimaAtualizacaoLcd >= INTERVALO_LCD_MS) {
    ultimaAtualizacaoLcd = agora;
    atualizarLcd();
  }
  if (mqttClient.connected() && (!ultimaPublicacaoMqtt || agora - ultimaPublicacaoMqtt >= MQTT_PUBLISH_MS)) {
    ultimaPublicacaoMqtt = agora;
    publicarTelemetriaMqtt();
  }
  delay(2);
}
