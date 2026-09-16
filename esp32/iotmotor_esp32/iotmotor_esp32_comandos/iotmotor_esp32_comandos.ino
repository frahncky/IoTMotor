/*
  Módulo 1 — ESP32 DevKit V1
  Fonte: sketch v6 funcional fornecido pelo autor; acrescenta espelho MQTT SOMENTE LEITURA.
  Web local, PZEM-004T v3/v4, LCD I2C 20x4 e 4 reles.
  Nao aceita comandos MQTT no broker publico; /rele so funciona na rede local.
  O estado MQTT dos pinos e LOGICO, nao feedback de contator.

  Correções em relação à v5:
    1.  PZEM deixou de ser objeto global (Serial2.begin() era chamado antes do
        boot do core). Agora é criado dentro do setup().
    2.  lerPzem() aborta na primeira leitura inválida, evitando até 6 timeouts
        seriais encadeados travando o loop por mais de 1 s.
    3.  Relés não dão mais pulso indesejado no boot (nível é escrito antes de
        pinMode(OUTPUT)).
    4.  LCD não é mais atualizado de dentro do handler HTTP (I2C lento dentro
        da resposta). Usa-se um pedido de atualização.
    5.  LCD só reescreve linhas que realmente mudaram — acabou o flicker.
    6.  Linha 2 do LCD reformatada para caber em 20 colunas.
    7.  manterWifi() não briga mais com setAutoReconnect() e trata o estado
        anterior corretamente.

  Bibliotecas:
    - PZEM004Tv30 (Jakub Mandula) — versão 1.1.2 ou superior
    - LiquidCrystal I2C (Frank de Brabander)
    - WiFi, WebServer e ESPmDNS (incluídas no core ESP32)

  Ligações:
    PZEM TX  -> ESP32 GPIO16 (RX2)
    PZEM RX  -> ESP32 GPIO17 (TX2)
    PZEM VCC -> ESP32 5V/VIN
    PZEM GND -> ESP32 GND

    LCD SDA  -> GPIO21
    LCD SCL  -> GPIO22

    Relé 1   -> GPIO19
    Relé 2   -> GPIO18
    Relé 3   -> GPIO23
    Relé 4   -> GPIO27

  Dashboard:
    http://<IP-do-ESP32>/
    http://modulo1.local/   (se mDNS funcionar na rede)
*/

#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <PZEM004Tv30.h>
#include <math.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// -----------------------------------------------------------------------------
// Wi-Fi
// -----------------------------------------------------------------------------
const char* WIFI_SSID     = "IFMA_IOT";
const char* WIFI_PASSWORD = "";
const char* NOME_MDNS     = "modulo1";

const unsigned long TEMPO_MAX_CONEXAO_WIFI   = 15000UL;
const unsigned long INTERVALO_RECONEXAO_WIFI = 10000UL;
unsigned long ultimaTentativaWifi = 0;
bool mdnsAtivo = false;

// -----------------------------------------------------------------------------
// Relés
// -----------------------------------------------------------------------------
constexpr uint8_t NUM_RELES = 4;
const uint8_t PINOS_RELES[NUM_RELES] = {19, 18, 23, 27};
bool estadoReles[NUM_RELES] = {false, false, false, false};

// Ajuste conforme o seu módulo de relé:
// false -> HIGH liga o relé
// true  -> LOW liga o relé (muito comum em módulos prontos com optoacoplador)
const bool RELE_ATIVO_EM_NIVEL_BAIXO = false;

constexpr uint8_t nivelLigado()    { return RELE_ATIVO_EM_NIVEL_BAIXO ? LOW : HIGH; }
constexpr uint8_t nivelDesligado() { return RELE_ATIVO_EM_NIVEL_BAIXO ? HIGH : LOW; }

// -----------------------------------------------------------------------------
// LCD I2C 20x4
// -----------------------------------------------------------------------------
constexpr uint8_t LCD_ENDERECO = 0x27;
constexpr uint8_t LCD_COLUNAS  = 20;
constexpr uint8_t LCD_LINHAS   = 4;
constexpr uint8_t LCD_SDA      = 21;
constexpr uint8_t LCD_SCL      = 22;
LiquidCrystal_I2C lcd(LCD_ENDERECO, LCD_COLUNAS, LCD_LINHAS);

// Cache do conteúdo mostrado, para reescrever só o que mudou.
char lcdCache[LCD_LINHAS][LCD_COLUNAS + 1];

// -----------------------------------------------------------------------------
// PZEM-004T
// -----------------------------------------------------------------------------
constexpr uint8_t PZEM_RX_PIN = 16;   // pino de RECEPÇÃO do ESP32 (vai no TX do PZEM)
constexpr uint8_t PZEM_TX_PIN = 17;   // pino de TRANSMISSÃO do ESP32 (vai no RX do PZEM)
const bool PZEM_HABILITADO = true;

// Criado no setup(): construir globalmente faz a biblioteca chamar
// Serial2.begin() durante a inicialização dos objetos estáticos, antes de o
// core do ESP32 estar pronto.
PZEM004Tv30* pzem = nullptr;

float ultimaTensao        = 0.0f;
float ultimaCorrente      = 0.0f;
float ultimaPotencia      = 0.0f;
float ultimaEnergia       = 0.0f;
float ultimaFrequencia    = 0.0f;
float ultimoFatorPotencia = 0.0f;
bool pzemOk = false;

unsigned long ultimaLeituraPzem = 0;
const unsigned long INTERVALO_LEITURA_PZEM = 3000UL;

unsigned long ultimaAtualizacaoLcd = 0;
const unsigned long INTERVALO_LCD = 1000UL;
volatile bool lcdPrecisaAtualizar = false;

// MQTT exclusivamente para espelhar telemetria. Nenhuma assinatura de comandos.
static const char* MQTT_HOST = "test.mosquitto.org";
static const uint16_t MQTT_PORT = 1883;
static const char* DEVICE_ID = "esp32-01";
WiFiClient mqttTransport;
PubSubClient mqttClient(mqttTransport);
static const unsigned long MQTT_RETRY_MS = 6000UL;
static const unsigned long MQTT_PUBLISH_MS = 1000UL;
unsigned long ultimaTentativaMqtt = 0, ultimaPublicacaoMqtt = 0;
uint32_t sequenciaMqtt = 0;
char topicoTelemetria[80], topicoStatus[80], topicoCapacidades[80];

// -----------------------------------------------------------------------------
// Servidor web
// -----------------------------------------------------------------------------
WebServer server(80);

#include "iotmotor_site.h"

// -----------------------------------------------------------------------------
// Utilidades
// -----------------------------------------------------------------------------
void aplicarEstadoRele(uint8_t indice) {
  if (indice >= NUM_RELES) return;
  digitalWrite(PINOS_RELES[indice],
               estadoReles[indice] ? nivelLigado() : nivelDesligado());
}

#include "iotmotor_profiles.h"

void imprimirLinhaCompleta(uint8_t linha, const char* texto) {
  if (linha >= LCD_LINHAS) return;

  char buffer[LCD_COLUNAS + 1];
  snprintf(buffer, sizeof(buffer), "%-*.*s", LCD_COLUNAS, LCD_COLUNAS, texto);

  // Evita reescrever (e piscar) uma linha que não mudou.
  if (strcmp(buffer, lcdCache[linha]) == 0) return;
  strcpy(lcdCache[linha], buffer);

  lcd.setCursor(0, linha);
  lcd.print(buffer);
}

void iniciarMdns() {
  if (WiFi.status() != WL_CONNECTED || mdnsAtivo) return;

  if (MDNS.begin(NOME_MDNS)) {
    mdnsAtivo = true;
    MDNS.addService("http", "tcp", 80);
    Serial.print("mDNS ativo: http://");
    Serial.print(NOME_MDNS);
    Serial.println(".local/");
  } else {
    Serial.println("Falha ao iniciar mDNS. Use o endereço IP.");
  }
}

void manterWifi() {
  static bool estavaConectado = false;
  const bool conectado = (WiFi.status() == WL_CONNECTED);

  if (conectado) {
    if (!estavaConectado) {
      estavaConectado = true;
      Serial.print("Wi-Fi conectado. IP: ");
      Serial.println(WiFi.localIP());
      lcdPrecisaAtualizar = true;
    }
    iniciarMdns();
    return;
  }

  if (estavaConectado) {
    estavaConectado = false;
    Serial.println("Wi-Fi desconectado.");
    if (mdnsAtivo) {
      MDNS.end();
      mdnsAtivo = false;
    }
    lcdPrecisaAtualizar = true;
  }

  const unsigned long agora = millis();
  if (agora - ultimaTentativaWifi >= INTERVALO_RECONEXAO_WIFI) {
    ultimaTentativaWifi = agora;
    Serial.println("Tentando reconectar ao Wi-Fi...");
    // false/false: não desliga o rádio nem apaga as credenciais salvas.
    WiFi.disconnect(false, false);
    if (strlen(WIFI_PASSWORD)) WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    else WiFi.begin(WIFI_SSID);
  }
}

// -----------------------------------------------------------------------------
// PZEM
// -----------------------------------------------------------------------------
void marcarPzemIndisponivel() {
  if (pzemOk) Serial.println("PZEM perdeu comunicação.");
  pzemOk = false;
  lcdPrecisaAtualizar = true;
}

void lerPzem() {
  if (!PZEM_HABILITADO || pzem == nullptr) {
    pzemOk = false;
    return;
  }

  // A primeira chamada dispara a leitura Modbus. Se ela falhar, sai imediatamente
  // em vez de encadear mais cinco timeouts seriais no loop.
  const float tensao = pzem->voltage();
  if (!isfinite(tensao)) {
    marcarPzemIndisponivel();
    return;
  }

  const float corrente   = pzem->current();
  const float potencia   = pzem->power();
  const float energia    = pzem->energy();
  const float frequencia = pzem->frequency();
  const float fp         = pzem->pf();

  if (!isfinite(corrente) || !isfinite(potencia) || !isfinite(energia) ||
      !isfinite(frequencia) || !isfinite(fp)) {
    marcarPzemIndisponivel();
    return;
  }

  const bool primeiraLeituraValida = !pzemOk;

  ultimaTensao        = tensao;
  ultimaCorrente      = corrente;
  ultimaPotencia      = potencia;
  ultimaEnergia       = energia;
  ultimaFrequencia    = frequencia;
  ultimoFatorPotencia = fp;
  pzemOk = true;
  lcdPrecisaAtualizar = true;

  if (primeiraLeituraValida) {
    Serial.println("PZEM conectado e respondendo.");
  }
}

// -----------------------------------------------------------------------------
// LCD
// -----------------------------------------------------------------------------
void atualizarLcd() {
  char buffer[48];

  if (WiFi.status() == WL_CONNECTED) {
    snprintf(buffer, sizeof(buffer), "IP:%s", WiFi.localIP().toString().c_str());
  } else {
    snprintf(buffer, sizeof(buffer), "WiFi desconectado");
  }
  imprimirLinhaCompleta(0, buffer);

  if (pzemOk) {
    snprintf(buffer, sizeof(buffer), "V:%5.1f  I:%6.2fA", ultimaTensao, ultimaCorrente);
  } else {
    snprintf(buffer, sizeof(buffer), "PZEM sem leitura");
  }
  imprimirLinhaCompleta(1, buffer);

  if (pzemOk) {
    // Cabe em 20 colunas mesmo com potência de 4 dígitos e energia alta.
    snprintf(buffer, sizeof(buffer), "P:%4.0fW E:%8.2fkWh", ultimaPotencia, ultimaEnergia);
  } else {
    buffer[0] = '\0';
  }
  imprimirLinhaCompleta(2, buffer);

  snprintf(buffer, sizeof(buffer), "R1:%c R2:%c R3:%c R4:%c",
           estadoReles[0] ? 'L' : 'D',
           estadoReles[1] ? 'L' : 'D',
           estadoReles[2] ? 'L' : 'D',
           estadoReles[3] ? 'L' : 'D');
  imprimirLinhaCompleta(3, buffer);

  lcdPrecisaAtualizar = false;
}

// -----------------------------------------------------------------------------
// Rotas HTTP
// -----------------------------------------------------------------------------
void adicionarCabecalhosComuns() {
  server.sendHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
  server.sendHeader("Pragma", "no-cache");
  server.sendHeader("X-Frame-Options", "DENY");
}

void tratarIndex() {
  adicionarCabecalhosComuns();
  server.send_P(200, "text/html; charset=utf-8", INDEX_HTML);
}

void tratarDualJs() {
  adicionarCabecalhosComuns();
  server.send_P(200,"application/javascript; charset=utf-8",IOTMOTOR_DUAL_JS);
}
void tratarLocalJs() {
  adicionarCabecalhosComuns();
  server.send_P(200,"application/javascript; charset=utf-8",IOTMOTOR_LOCAL_JS);
}

void tratarDados() {
  StaticJsonDocument<1024> doc;
  doc["pzem_ok"] = pzemOk;
  if (pzemOk) {
    doc["tensao"] = ultimaTensao; doc["corrente"] = ultimaCorrente;
    doc["potencia"] = ultimaPotencia; doc["energia"] = ultimaEnergia;
    doc["frequencia"] = ultimaFrequencia; doc["fator_potencia"] = ultimoFatorPotencia;
  }
  doc["wifi_ok"] = WiFi.status()==WL_CONNECTED;
  if (WiFi.status()==WL_CONNECTED) doc["wifi_ip"] = WiFi.localIP().toString();
  doc["armado"] = bancadaHabilitada();
  doc["partida_etapa"] = nomeEtapa();
  doc["partida_modo"] = modoPartida==1?"sequence":"direct";
  JsonArray reles=doc.createNestedArray("reles");
  JsonArray pinos=doc.createNestedArray("relay_pins");
  for (uint8_t i=0;i<NUM_RELES;i++) { reles.add(estadoReles[i]);pinos.add(PINOS_RELES[i]); }
  JsonArray lcdLines=doc.createNestedArray("lcd");
  for (uint8_t i=0;i<LCD_LINHAS;i++) lcdLines.add(lcdCache[i]);
  String resposta; serializeJson(doc,resposta);
  adicionarCabecalhosComuns();
  server.send(200,"application/json; charset=utf-8",resposta);
}

void tratarNaoEncontrado() {
  adicionarCabecalhosComuns();
  server.send(404, "text/plain; charset=utf-8", "Rota nao encontrada.");
}

// -----------------------------------------------------------------------------
// MQTT: apenas leitura do estado da bancada e copia do buffer do LCD fisico.
// -----------------------------------------------------------------------------
void publicarCapacidades() {
  if (!mqttClient.connected()) return;
  StaticJsonDocument<384> doc;
  doc["device_id"] = DEVICE_ID;
  doc["role"] = "actuator_local_only";
  doc["firmware_version"] = "v6-lan-profiles-1.0";
  doc["accepts_direct_command"] = false;
  doc["accepts_command_request"] = false;
  doc["relay_commanded_only"] = true;
  doc["lan_start_profiles"] = true;
  doc["requires_gpio32_arm"] = true;
  JsonArray fields = doc.createNestedArray("fields");
  for (const char* key : {"voltage", "current", "power", "energy", "frequency", "pf"}) fields.add(key);
  char payload[384];
  size_t bytes = serializeJson(doc, payload, sizeof(payload));
  if (bytes) mqttClient.publish(topicoCapacidades, reinterpret_cast<const uint8_t*>(payload),
                                static_cast<unsigned int>(bytes), true);
}

void publicarTelemetriaMqtt() {
  if (!mqttClient.connected()) return;
  StaticJsonDocument<1024> doc;
  doc["device_id"] = DEVICE_ID;
  doc["seq"] = ++sequenciaMqtt;
  doc["bench_armed"] = bancadaHabilitada();
  doc["start_phase"] = nomeEtapa();
  if (WiFi.status()==WL_CONNECTED) doc["wifi_ip"] = WiFi.localIP().toString();
  doc["demo"] = false;
  doc["data_source"] = "pzem004t";
  doc["pzem_ok"] = pzemOk;
  doc["sensor_ok"] = pzemOk;
  doc["relay_commanded_only"] = true;
  doc["state"] = "manual_relays";
  doc["mode"] = etapaPartida? (modoPartida==1?"star_delta_bench":"direct_bench") : "manual_relays";
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
  JsonArray lcdLines = doc.createNestedArray("lcd");
  for (uint8_t i = 0; i < LCD_LINHAS; ++i) lcdLines.add(lcdCache[i]);
  char payload[1024];
  size_t bytes = serializeJson(doc, payload, sizeof(payload));
  if (!bytes || !mqttClient.publish(topicoTelemetria, reinterpret_cast<const uint8_t*>(payload),
                                     static_cast<unsigned int>(bytes), false)) {
    Serial.printf("[MQTT] falha publicando, bytes=%u rc=%d\n", (unsigned int)bytes, mqttClient.state());
  }
}

void manterMqtt(unsigned long agora) {
  if (WiFi.status() != WL_CONNECTED) return;
  if (mqttClient.connected()) { mqttClient.loop(); return; }
  if (ultimaTentativaMqtt && agora - ultimaTentativaMqtt < MQTT_RETRY_MS) return;
  ultimaTentativaMqtt = agora;
  const String clientId = String("iotmotor_v6_") + String((uint32_t)ESP.getEfuseMac(), HEX);
  if (mqttClient.connect(clientId.c_str(), topicoStatus, 0, true, "offline")) {
    mqttClient.publish(topicoStatus, "online", true);
    publicarCapacidades();
    Serial.println("[MQTT] conectado; publicacao somente leitura");
  } else Serial.printf("[MQTT] falha rc=%d\n", mqttClient.state());
}

// -----------------------------------------------------------------------------
// Setup
// -----------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println();
  Serial.println("=== Modulo 1 / ESP32 v6 ===");
  pinMode(PINO_HABILITACAO_BANCADA, INPUT_PULLUP);

  // Relés: escreve o nível de repouso ANTES de configurar como saída, para não
  // dar pulso nos relés durante o boot (crítico em módulos ativos em nível baixo).
  for (uint8_t i = 0; i < NUM_RELES; i++) {
    digitalWrite(PINOS_RELES[i], nivelDesligado());
    pinMode(PINOS_RELES[i], OUTPUT);
    digitalWrite(PINOS_RELES[i], nivelDesligado());
    estadoReles[i] = false;
  }

  // LCD
  for (uint8_t i = 0; i < LCD_LINHAS; i++) lcdCache[i][0] = '\0';
  Wire.begin(LCD_SDA, LCD_SCL);
  lcd.init();
  lcd.backlight();
  lcd.clear();
  imprimirLinhaCompleta(0, "Iniciando ESP32...");
  imprimirLinhaCompleta(1, "Conectando WiFi...");

  // PZEM — criado aqui, com o core já inicializado.
  if (PZEM_HABILITADO) {
    pzem = new PZEM004Tv30(Serial2, PZEM_RX_PIN, PZEM_TX_PIN);
  }

  // Wi-Fi em modo estação. O programa não trava indefinidamente se a rede falhar.
  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);
  WiFi.setSleep(false);            // evita latência alta no servidor web
  if (strlen(WIFI_PASSWORD)) WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  else WiFi.begin(WIFI_SSID);
  ultimaTentativaWifi = millis();

  Serial.print("Conectando ao Wi-Fi");
  const unsigned long inicioConexao = millis();
  while (WiFi.status() != WL_CONNECTED &&
         (millis() - inicioConexao) < TEMPO_MAX_CONEXAO_WIFI) {
    delay(250);
    Serial.print('.');
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("Wi-Fi conectado. IP: ");
    Serial.println(WiFi.localIP());
    iniciarMdns();
  } else {
    Serial.println("Wi-Fi nao conectado. O ESP32 continuara funcionando e tentara reconectar.");
  }

  // Configura publicacao MQTT em topicos exclusivos deste modulo.
  snprintf(topicoTelemetria, sizeof(topicoTelemetria), "iotmotor/%s/telemetry", DEVICE_ID);
  snprintf(topicoStatus, sizeof(topicoStatus), "iotmotor/%s/status", DEVICE_ID);
  snprintf(topicoCapacidades, sizeof(topicoCapacidades), "iotmotor/%s/capabilities", DEVICE_ID);
  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setBufferSize(1536);
  // Inspecionar Origin em POSTs de energizacao, sem abrir CORS.
  const char* headerNames[] = {"Origin"};
  server.collectHeaders(headerNames, 1);
  // Servidor web
  server.on("/", HTTP_GET, tratarIndex);
  server.on("/dados", HTTP_GET, tratarDados);
  server.on("/dual-dashboard.js", HTTP_GET, tratarDualJs);
  server.on("/local-controls.js", HTTP_GET, tratarLocalJs);
  server.on("/partida", HTTP_POST, tratarPartidaBancada);
  server.on("/parar", HTTP_POST, tratarPararBancada);
  server.on("/canal", HTTP_POST, tratarCanalBancada);
  server.onNotFound(tratarNaoEncontrado);
  server.begin();
  Serial.println("Servidor HTTP iniciado na porta 80.");

  // Primeira leitura imediata, sem esperar o primeiro intervalo.
  lerPzem();
  ultimaLeituraPzem = millis();

  lcd.clear();
  for (uint8_t i = 0; i < LCD_LINHAS; i++) lcdCache[i][0] = '\0';
  atualizarLcd();
  ultimaAtualizacaoLcd = millis();
}

// -----------------------------------------------------------------------------
// Loop
// -----------------------------------------------------------------------------
void loop() {
  server.handleClient();
  manterWifi();

  const unsigned long agora = millis();
  manterPartidaBancada(agora);

  if (agora - ultimaLeituraPzem >= INTERVALO_LEITURA_PZEM) {
    ultimaLeituraPzem = agora;
    lerPzem();
  }

  if (lcdPrecisaAtualizar || (agora - ultimaAtualizacaoLcd >= INTERVALO_LCD)) {
    ultimaAtualizacaoLcd = agora;
    atualizarLcd();
  }

  manterMqtt(agora);
  if (mqttClient.connected() && (ultimaPublicacaoMqtt == 0 || agora - ultimaPublicacaoMqtt >= MQTT_PUBLISH_MS)) {
    ultimaPublicacaoMqtt = agora;
    publicarTelemetriaMqtt();
  }
  delay(2);
}
