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
char topicoComandos[80], topicoResposta[80], topicoWifi[80], topicoPerfis[80], topicoAuth[80];
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
// Modo instrumentacao: o LCD e os comandos consultam o estado, entao ele e
// declarado antes dos cabecalhos que o usam.
extern bool acionamentoLigado;
bool salvarAcionamento(bool ligado);
extern uint32_t toleranciaSemLinkMs;
bool salvarLimiteDoEnsaio(long segundos);
constexpr long MAX_TOLERANCIA_S = 3600;  // Teto do que da para configurar.
constexpr long MAX_ENSAIO_S = 7200;      // Teto do ensaio configuravel.
bool salvarToleranciaSemLink(long segundos);

#include "comando_seguro.h"
#include "relogio.h"
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

// O LCD nao entende UTF-8: um acento vale dois bytes e sai como dois simbolos
// estranhos, que ainda empurram o resto da linha para fora das 20 colunas. Os
// nomes das partidas continuam com acento no painel, no app e na telemetria; a
// troca acontece so aqui, na ida para o display.
void semAcento(const char* origem, char* destino, size_t tamanho) {
  if (!tamanho) return;
  size_t escritos = 0;
  for (const unsigned char* p = (const unsigned char*)origem;
       *p && escritos + 1 < tamanho; ++p) {
    if (*p < 0x80) {  // ASCII puro passa direto.
      destino[escritos++] = (char)*p;
      continue;
    }
    if (*p != 0xC3 || !p[1]) {  // Fora do latim acentuado: um lugar, sem lixo.
      destino[escritos++] = '?';
      if (*p >= 0xC0 && p[1]) ++p;
      continue;
    }
    const unsigned char segundo = *++p;
    char letra;
    if (segundo >= 0x80 && segundo <= 0x85) letra = 'A';
    else if (segundo == 0x87) letra = 'C';
    else if (segundo >= 0x88 && segundo <= 0x8B) letra = 'E';
    else if (segundo >= 0x8C && segundo <= 0x8F) letra = 'I';
    else if (segundo == 0x91) letra = 'N';
    else if (segundo >= 0x92 && segundo <= 0x96) letra = 'O';
    else if (segundo >= 0x99 && segundo <= 0x9C) letra = 'U';
    else if (segundo == 0x9D) letra = 'Y';
    else if (segundo >= 0xA0 && segundo <= 0xA5) letra = 'a';
    else if (segundo == 0xA7) letra = 'c';
    else if (segundo >= 0xA8 && segundo <= 0xAB) letra = 'e';
    else if (segundo >= 0xAC && segundo <= 0xAF) letra = 'i';
    else if (segundo == 0xB1) letra = 'n';
    else if (segundo >= 0xB2 && segundo <= 0xB6) letra = 'o';
    else if (segundo >= 0xB9 && segundo <= 0xBC) letra = 'u';
    else if (segundo == 0xBD || segundo == 0xBF) letra = 'y';
    else letra = '?';
    destino[escritos++] = letra;
  }
  destino[escritos] = '\0';
}

// LCD 20x4. Cada linha cabe nas 20 colunas: acima disso o display corta o
// texto e as informacoes aparecem coladas.
//   L0  Estrela-triangulo      (ou a ultima partida/estado da conexao)
//   L1  V:220.1 I:  2.30A
//   L2  P:  420W FP:0.81
//   L3  CNT 1-2    60.0Hz
void atualizarLcd() {
  char buffer[48];
  const bool comWifi = WiFi.status() == WL_CONNECTED;
  const bool comMqtt = mqttClient.connected();

  char nome[sizeof(perfilEmExecucao.nome)];
  semAcento(perfilEmExecucao.nome, nome, sizeof(nome));

  if (partidaAtiva) {  // Em ensaio, o nome da partida ocupa a linha inteira.
    snprintf(buffer, sizeof(buffer), "%-20.20s", nome);
  } else if (!comWifi) {
    snprintf(buffer, sizeof(buffer), "WiFi: procurando");
  } else if (!comMqtt) {
    snprintf(buffer, sizeof(buffer), "MQTT reconectando");
  } else if (!acionamentoLigado) {
    snprintf(buffer, sizeof(buffer), "Somente medicao");
  } else if (nome[0]) {  // Parado: diz qual foi o ultimo ensaio.
    snprintf(buffer, sizeof(buffer), "Ultima: %-12.12s", nome);
  } else {
    snprintf(buffer, sizeof(buffer), "Pronto para partida");
  }
  imprimirLinhaCompleta(0, buffer);

  if (pzemOk) snprintf(buffer, sizeof(buffer), "V:%5.1f I:%6.2fA", ultimaTensao, ultimaCorrente);
  else snprintf(buffer, sizeof(buffer), "PZEM sem leitura");
  imprimirLinhaCompleta(1, buffer);

  if (pzemOk) snprintf(buffer, sizeof(buffer), "P:%5.0fW FP:%4.2f", ultimaPotencia, ultimoFatorPotencia);
  else buffer[0] = '\0';
  imprimirLinhaCompleta(2, buffer);

  // Contatores ligados separados por hifen: "1-2" em vez de "12" colado.
  char contatores[2 * NUM_RELES] = "";
  uint8_t escritos = 0;
  for (uint8_t i = 0; i < NUM_RELES; ++i) {
    if (!estadoReles[i]) continue;
    if (escritos) contatores[escritos++] = '-';
    contatores[escritos++] = char('1' + i);
  }
  contatores[escritos] = '\0';
  if (!escritos) strcpy(contatores, "nenhum");
  // 4 + 7 + 1 + 6 + 2 = 20 colunas.
  if (pzemOk) snprintf(buffer, sizeof(buffer), "CNT %-7.7s %4.1fHz", contatores, ultimaFrequencia);
  else snprintf(buffer, sizeof(buffer), "CNT %-7.7s", contatores);
  imprimirLinhaCompleta(3, buffer);
  lcdPrecisaAtualizar = false;
}

// ---- Queda de rede ----
// Quanto tempo o ensaio continua depois que o Wi-Fi ou o MQTT cai. O padrao
// sao 15 s, que cobrem as quedas curtas do broker publico sem deixar a bancada
// ligada sozinha. Zero derruba na hora; SEM_LIMITE deixa seguir ate o fim do
// ensaio, que continua limitado por LIMITE_BANCADA_MS.
constexpr uint32_t SEM_LIMITE_SEM_LINK = 0xFFFFFFFFUL;
uint32_t toleranciaSemLinkMs = TOLERANCIA_SEM_LINK_MS;

void carregarLimiteDoEnsaio() {
  Preferences memoria;
  if (!memoria.begin("iot-comando", true)) return;
  limiteDoEnsaioMs = memoria.getUInt("ensaio", LIMITE_BANCADA_MS);
  memoria.end();
}

// segundos < 0 = sem limite de tempo; minimo de 10 s.
bool salvarLimiteDoEnsaio(long segundos) {
  if (segundos > MAX_ENSAIO_S || (segundos >= 0 && segundos < 10)) return false;
  const uint32_t valor = segundos < 0 ? SEM_LIMITE_ENSAIO : (uint32_t)segundos * 1000UL;
  Preferences memoria;
  if (!memoria.begin("iot-comando", false)) return false;
  memoria.putUInt("ensaio", valor);
  memoria.end();
  limiteDoEnsaioMs = valor;
  return true;
}

void carregarToleranciaSemLink() {
  Preferences memoria;
  if (!memoria.begin("iot-comando", true)) return;
  toleranciaSemLinkMs = memoria.getUInt("semlink", TOLERANCIA_SEM_LINK_MS);
  memoria.end();
}

// segundos < 0 = sem limite; 0 = derruba na hora.
bool salvarToleranciaSemLink(long segundos) {
  if (segundos > MAX_TOLERANCIA_S) return false;
  const uint32_t valor = segundos < 0 ? SEM_LIMITE_SEM_LINK
                                      : (uint32_t)segundos * 1000UL;
  Preferences memoria;
  if (!memoria.begin("iot-comando", false)) return false;
  memoria.putUInt("semlink", valor);
  memoria.end();
  toleranciaSemLinkMs = valor;
  return true;
}

// ---- Modo instrumentacao ----
// Com o acionamento desligado a placa nao fecha contator nenhum: so mede,
// publica e mostra no LCD. Serve para ensaiar a medicao com o motor ligado
// por um comando eletrico convencional, sem o ESP32 no meio.
bool acionamentoLigado = true;

void carregarAcionamento() {
  Preferences memoria;
  if (!memoria.begin("iot-comando", true)) return;
  acionamentoLigado = memoria.getBool("acionar", true);
  memoria.end();
  if (!acionamentoLigado) Serial.println("[MODO] instrumentacao: acionamento desligado");
}

bool salvarAcionamento(bool ligado) {
  Preferences memoria;
  if (!memoria.begin("iot-comando", false)) return false;
  memoria.putBool("acionar", ligado);
  memoria.end();
  acionamentoLigado = ligado;
  if (!ligado) pararBancada();  // Sai do modo com tudo aberto, nunca ligado.
  lcdPrecisaAtualizar = true;
  return true;
}

void manterWifi(unsigned long agora) {
  static bool estavaConectado = false;
  if (WiFi.status() == WL_CONNECTED) {
    relogio::manter(agora);  // Hora real para carimbar as medicoes.
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
  doc["firmware_version"] = "v11-wifi-list";
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
  doc["secure"] = comandoseguro::ligado;
  // false = modo instrumentacao: a placa nao aciona contator nenhum.
  doc["actuation"] = acionamentoLigado;
  // Segundos que o ensaio segue sem rede; -1 = sem limite.
  doc["link_grace_s"] = toleranciaSemLinkMs == SEM_LIMITE_SEM_LINK
                            ? -1
                            : (int)(toleranciaSemLinkMs / 1000UL);
  // Quanto tempo um ensaio pode durar; -1 = sem limite de tempo.
  doc["run_limit_s"] = limiteDoEnsaioMs == SEM_LIMITE_ENSAIO
                           ? -1
                           : (int)(limiteDoEnsaioMs / 1000UL);
  // Hora da medicao, em segundos UTC. Ausente enquanto o NTP nao responde.
  if (const uint32_t carimbo = relogio::agoraUtc()) doc["ts"] = carimbo;
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
  doc["mode"] = partidaAtiva ? "profile_bench" : "manual_relays";
  if (partidaAtiva) {  // Painel e app mostram o andamento da partida.
    doc["profile"] = perfilEmExecucao.id;
    doc["profile_ms"] = tempoDePartidaMs(millis());
  }
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
    publicarAuth();
    publicarRedes();
    publicarPerfis();
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
  carregarPerfis();
  wifistore::carregarRedePropria(PORTAL_NOME);
  Serial.printf("[WiFi] %u rede(s) na lista da placa\n", wifistore::total);
  ultimaTentativaWifi = millis();
  // Nenhuma rede da lista respondeu: so o portal permite cadastrar sem cabo.
  if (!wifistore::conectarEmOrdem(10000)) {
    imprimirLinhaCompleta(1, wifistore::apNome);  // Rede da placa aberta.
    abrirPortalDeRede(PORTAL_SEGUNDOS);
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
  snprintf(topicoPerfis, sizeof(topicoPerfis), "iotmotor/%s/profiles", DEVICE_ID);
  snprintf(topicoAuth, sizeof(topicoAuth), "iotmotor/%s/auth", DEVICE_ID);
  carregarAcionamento();
  carregarToleranciaSemLink();
  carregarLimiteDoEnsaio();
  comandoseguro::iniciar(DEVICE_ID);
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
  const bool saidasAtivas = partidaAtiva || estadoReles[0] || estadoReles[1] ||
                            estadoReles[2] || estadoReles[3];
  if (!comLink && saidasAtivas && toleranciaSemLinkMs != SEM_LIMITE_SEM_LINK &&
      decorrido(agora, inicioSemLink) > (int32_t)toleranciaSemLinkMs) {
    pararBancada();
    Serial.printf("[BANCADA] saidas desligadas: %lu s sem MQTT/Wi-Fi\n",
                  toleranciaSemLinkMs / 1000UL);
  }
  manterPartidaBancada(agora);
  // Reinicio pedido pelo painel: desiste se alguma saida ligou nesse meio tempo.
  if (reinicioPedidoEm && saidasAtivas) reinicioPedidoEm = 0;
  if (reinicioPedidoEm && agora - reinicioPedidoEm >= 300UL) {
    Serial.println("[QUADRO] reiniciando a pedido do painel");
    ESP.restart();
  }
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
