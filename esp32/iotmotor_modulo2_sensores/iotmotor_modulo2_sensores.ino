/* ============================================================
 * PROJETO: Sistema de Comandos e Medicao de Maquinas Eletricas
 *          via Internet of Things (IoT)
 *
 * MODULO 2 - ESP32-S3 DevKitC N8R2  (device_id: esp32-02)
 * Papel: AQUISICAO dos dados do motor usados no controle
 *
 * O modulo nao serve pagina web. Toda a interface - pagina web e
 * aplicativo - e o proprio cliente Flutter falando com o broker MQTT.
 *
 * Conteudo:
 *   - Vibracao via MPU6050 lido diretamente nos registradores, com
 *     reset de software e reconfiguracao automatica se o sensor travar;
 *   - Amostragem rapida (50 Hz) com RMS e pico por janela, em vez de
 *     uma unica amostra instantanea por publicacao;
 *   - Temperatura via DS18B20 (OneWire);
 *   - Registro local em cartao SD com arquivos diarios e expurgo por
 *     retencao, configuravel pelo aplicativo (payload storage_config).
 *     O SD e a garantia de que nada se perde enquanto a rede estiver
 *     fora, ja que nao ha mais interface local para consulta;
 *   - Sinalizacao local por LED RGB e buzzer em estado critico - a
 *     unica indicacao para quem esta junto da bancada;
 *   - Publicacao MQTT no mesmo contrato do aplicativo Flutter. O
 *     Modulo 1 (esp32-01) assina esta telemetria e usa vibracao e
 *     temperatura como protecao cruzada do acionamento.
 *
 * Bibliotecas:
 *   - PubSubClient (Nick O'Leary)
 *   - ArduinoJson (Benoit Blanchon) 6.x
 *   - OneWire + DallasTemperature
 *   - WiFi / Wire / SPI / SD / Preferences (core ESP32)
 *
 * Ligacoes:
 *   MPU6050 SDA -> GPIO5      DS18B20 DQ -> GPIO4 (pull-up 4k7 ao 3V3)
 *   MPU6050 SCL -> GPIO9      Buzzer     -> GPIO42
 *   SD CS       -> GPIO10     LED azul   -> GPIO16
 *                             LED verde  -> GPIO17
 *                             LED verm.  -> GPIO18
 *
 * IFMA - Projeto PIBITI
 * Orientador: Prof. Almir Souza e Silva Neto
 * ============================================================ */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <SPI.h>
#include <SD.h>
#include <Preferences.h>
#include <time.h>
#include <math.h>

// -----------------------------------------------------------------------------
// Wi-Fi
// -----------------------------------------------------------------------------
static const char* WIFI_SSID     = "BotComp";
static const char* WIFI_PASSWORD = "linguagemC";

static const unsigned long TEMPO_MAX_CONEXAO_WIFI   = 15000UL;
static const unsigned long INTERVALO_RECONEXAO_WIFI = 10000UL;

// -----------------------------------------------------------------------------
// MQTT - mesmo contrato usado pelo aplicativo Flutter
// -----------------------------------------------------------------------------
static const char*    MQTT_HOST = "broker.hivemq.com";
static const uint16_t MQTT_PORT = 1883;
static const char*    MQTT_USER = "";
static const char*    MQTT_PASS = "";

static const char* TOPIC_PREFIX = "iotmotor";
static const char* DEVICE_ID    = "esp32-02";

// device_id do Modulo 1, cuja telemetria informa se o motor esta acionado.
static const char* DEVICE_ID_ACIONAMENTO = "esp32-01";

static const unsigned long INTERVALO_TELEMETRIA_MS      = 1000UL;
static const unsigned long INTERVALO_RECONEXAO_MQTT_MS  = 3000UL;

// -----------------------------------------------------------------------------
// Pinagem
// -----------------------------------------------------------------------------
static const uint8_t SDA_PIN       = 5;
static const uint8_t SCL_PIN       = 9;
static const uint8_t DS18B20_PIN   = 4;
static const uint8_t BUZZER_PIN    = 42;
static const uint8_t LED_BLUE_PIN  = 16;
static const uint8_t LED_GREEN_PIN = 17;
static const uint8_t LED_RED_PIN   = 18;
static const uint8_t SD_CS_PIN     = 10;

static const bool RGB_ANODO_COMUM = false;

// Registradores do MPU6050
static const uint8_t MPU_ADDR        = 0x68;
static const uint8_t MPU_PWR_MGMT_1  = 0x6B;
static const uint8_t MPU_ACCEL_CONF  = 0x1C;
static const uint8_t MPU_ACCEL_XOUT  = 0x3B;
// Escala +/- 4 g -> 8192 LSB/g
static const float   MPU_LSB_POR_G   = 8192.0f;

// -----------------------------------------------------------------------------
// Parametros de operacao
// -----------------------------------------------------------------------------
static const unsigned long INTERVALO_AMOSTRA_MS     = 20UL;    // 50 Hz no MPU6050
static const unsigned long INTERVALO_TEMPERATURA_MS = 2000UL;  // DS18B20 e lento
static const unsigned long INTERVALO_BEEP_MS        = 400UL;
// A gravacao no SD e mais lenta que a telemetria: abrir e fechar o arquivo a
// cada segundo desgasta o cartao e atrasa o laco. Publica a 1 Hz, grava a 1/5 Hz.
static const unsigned long INTERVALO_REGISTRO_SD_MS = 5000UL;

static const float VIBRACAO_LIMIAR_G     = 0.50f;
static const float TEMPERATURA_LIMIAR_C  = 60.0f;

// -----------------------------------------------------------------------------
// Hora via NTP
// -----------------------------------------------------------------------------
static const char* NTP_SERVER          = "pool.ntp.org";
static const long  GMT_OFFSET_SEC      = -3 * 3600;
static const int   DAYLIGHT_OFFSET_SEC = 0;

// -----------------------------------------------------------------------------
// Cartao SD
// -----------------------------------------------------------------------------
// Um arquivo por dia (/logs/AAAAMMDD.csv) permite expurgar por retencao
// simplesmente apagando arquivos inteiros.
static const char* LOG_DIR = "/logs";
static const int   RETENCAO_PADRAO_DIAS = 30;
static const int   RETENCAO_MINIMA_DIAS = 1;
static const int   RETENCAO_MAXIMA_DIAS = 3650;

bool sdDisponivel = false;
unsigned long totalAmostrasGravadas = 0;
int retencaoDias = RETENCAO_PADRAO_DIAS;
unsigned long ultimoExpurgoMs = 0;
static const unsigned long INTERVALO_EXPURGO_MS = 6UL * 60UL * 60UL * 1000UL;  // 6 h

Preferences preferencias;

// -----------------------------------------------------------------------------
// Objetos globais
// -----------------------------------------------------------------------------
WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

OneWire oneWire(DS18B20_PIN);
DallasTemperature ds18b20(&oneWire);

char topicTelemetria[96];
char topicStatus[96];
char topicComando[96];
char topicTelemetriaRequest[96];
char topicComandoRequest[96];
char topicCapabilities[96];
char topicTelemetriaAcionamento[96];

bool mpuDisponivel = false;

unsigned long ultimaAmostraMs      = 0;
unsigned long ultimaTemperaturaMs  = 0;
unsigned long ultimaTelemetriaMs   = 0;
unsigned long ultimoRegistroSdMs   = 0;
unsigned long ultimaTentativaWifi  = 0;
unsigned long ultimaTentativaMqtt  = 0;
unsigned long ultimoBeepMs         = 0;

bool estadoCritico = false;
bool buzzerLigado  = false;

// Janela de agregacao da vibracao.
double somaQuadradosDesvio = 0.0;
uint32_t amostrasNaJanela  = 0;
float picoDesvioJanela     = 0.0f;

// Ultimos valores publicados.
float g_ax = 0, g_ay = 0, g_az = 0;
float g_magnitude = 0;
float g_vibracaoRms = 0, g_vibracaoPico = 0;
float g_temperatura = NAN;
bool  g_tempValida = false;
uint32_t g_contadorLeituras = 0;
String g_timestamp = "--";

// Estado do motor, vindo do Modulo 1: registrado no SD junto de cada amostra,
// para que a analise posterior saiba se o motor estava acionado.
bool motorLigado = false;
bool motorConhecido = false;

// -----------------------------------------------------------------------------
// MPU6050 - reset de software e leitura direta dos registradores
// -----------------------------------------------------------------------------
bool inicializarEForcarMPU() {
  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(100000);

  // 1. Reset geral (bit 7 de PWR_MGMT_1).
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(MPU_PWR_MGMT_1);
  Wire.write(0x80);
  if (Wire.endTransmission() != 0) return false;

  delay(100);  // aguarda o reset interno concluir

  // 2. Desperta o sensor e seleciona o clock do giroscopio do eixo X
  //    (0x01 e mais estavel que o oscilador interno 0x00).
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(MPU_PWR_MGMT_1);
  Wire.write(0x01);
  if (Wire.endTransmission() != 0) return false;

  // 3. Acelerometro em +/- 4 g.
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(MPU_ACCEL_CONF);
  Wire.write(0x08);
  if (Wire.endTransmission() != 0) return false;

  delay(50);
  return true;
}

bool lerAcelerometroBruto(float &ax, float &ay, float &az) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(MPU_ACCEL_XOUT);
  if (Wire.endTransmission(false) != 0) return false;

  if (Wire.requestFrom((uint8_t)MPU_ADDR, (size_t)6) != 6) return false;

  int16_t rawX = (Wire.read() << 8) | Wire.read();
  int16_t rawY = (Wire.read() << 8) | Wire.read();
  int16_t rawZ = (Wire.read() << 8) | Wire.read();

  // Os tres eixos exatamente em zero indicam sensor travado, nao repouso.
  if (rawX == 0 && rawY == 0 && rawZ == 0) return false;

  ax = (float)rawX / MPU_LSB_POR_G;
  ay = (float)rawY / MPU_LSB_POR_G;
  az = (float)rawZ / MPU_LSB_POR_G;
  return true;
}

// -----------------------------------------------------------------------------
// LED RGB e buzzer - unica sinalizacao local
// -----------------------------------------------------------------------------
void setLED(bool azul, bool verde, bool vermelho) {
  if (RGB_ANODO_COMUM) {
    digitalWrite(LED_BLUE_PIN,  azul     ? LOW : HIGH);
    digitalWrite(LED_GREEN_PIN, verde    ? LOW : HIGH);
    digitalWrite(LED_RED_PIN,   vermelho ? LOW : HIGH);
  } else {
    digitalWrite(LED_BLUE_PIN,  azul     ? HIGH : LOW);
    digitalWrite(LED_GREEN_PIN, verde    ? HIGH : LOW);
    digitalWrite(LED_RED_PIN,   vermelho ? HIGH : LOW);
  }
}

void atualizarAlarmeSonoro(unsigned long agora) {
  if (!estadoCritico) {
    if (buzzerLigado) {
      noTone(BUZZER_PIN);
      buzzerLigado = false;
    }
    return;
  }

  if (agora - ultimoBeepMs >= INTERVALO_BEEP_MS) {
    ultimoBeepMs = agora;
    buzzerLigado = !buzzerLigado;
    if (buzzerLigado) {
      tone(BUZZER_PIN, 2000);
    } else {
      noTone(BUZZER_PIN);
    }
  }
}

// -----------------------------------------------------------------------------
// Hora
// -----------------------------------------------------------------------------
bool horaSincronizada(struct tm &saida) {
  // Espera zero: apenas consulta o relogio interno, sem travar o loop
  // enquanto o NTP nao sincroniza.
  if (!getLocalTime(&saida, 0)) return false;
  // Antes da sincronizacao o ESP32 reporta 1970.
  return (saida.tm_year + 1900) >= 2023;
}

String obterTimestamp() {
  struct tm horario;
  if (!horaSincronizada(horario)) {
    return "millis_" + String(millis());
  }
  char buffer[32];
  strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%S", &horario);
  return String(buffer);
}

// -----------------------------------------------------------------------------
// Cartao SD: arquivos diarios e expurgo por retencao
// -----------------------------------------------------------------------------
void carregarRetencaoPersistida() {
  preferencias.begin("iotmotor", false);
  retencaoDias = preferencias.getInt("retencao", RETENCAO_PADRAO_DIAS);
  if (retencaoDias < RETENCAO_MINIMA_DIAS || retencaoDias > RETENCAO_MAXIMA_DIAS) {
    retencaoDias = RETENCAO_PADRAO_DIAS;
  }
}

void salvarRetencaoPersistida(int dias) {
  preferencias.putInt("retencao", dias);
}

// Nome do arquivo do dia: /logs/AAAAMMDD.csv (compativel com 8.3).
bool montarNomeArquivoDoDia(char* destino, size_t tamanho) {
  struct tm horario;
  if (!horaSincronizada(horario)) return false;
  snprintf(destino, tamanho, "%s/%04d%02d%02d.csv",
           LOG_DIR, horario.tm_year + 1900, horario.tm_mon + 1, horario.tm_mday);
  return true;
}

void inicializarSD() {
  if (!SD.begin(SD_CS_PIN)) {
    sdDisponivel = false;
    Serial.println("Cartao SD nao encontrado. O registro local fica desativado.");
    return;
  }

  if (!SD.exists(LOG_DIR) && !SD.mkdir(LOG_DIR)) {
    sdDisponivel = false;
    Serial.println("Nao foi possivel criar o diretorio de logs no SD.");
    return;
  }

  sdDisponivel = true;
  Serial.println("Cartao SD pronto.");
}

// Converte "AAAAMMDD" no epoch local daquele dia.
// Devolve 0 quando o nome nao segue o padrao.
time_t epochDoNomeDeArquivo(const char* nome) {
  size_t n = strlen(nome);
  if (n < 12) return 0;                       // AAAAMMDD.csv
  if (strcmp(nome + n - 4, ".csv") != 0) return 0;

  char digitos[9];
  memcpy(digitos, nome + (n - 12), 8);
  digitos[8] = '\0';
  for (int i = 0; i < 8; i++) {
    if (digitos[i] < '0' || digitos[i] > '9') return 0;
  }

  const int ano = (digitos[0] - '0') * 1000 + (digitos[1] - '0') * 100 +
                  (digitos[2] - '0') * 10 + (digitos[3] - '0');
  const int mes = (digitos[4] - '0') * 10 + (digitos[5] - '0');
  const int dia = (digitos[6] - '0') * 10 + (digitos[7] - '0');
  if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return 0;

  struct tm t;
  memset(&t, 0, sizeof(t));
  t.tm_year  = ano - 1900;
  t.tm_mon   = mes - 1;
  t.tm_mday  = dia;
  t.tm_hour  = 12;   // meio-dia evita problemas de fuso na conversao
  t.tm_isdst = -1;
  return mktime(&t);
}

// Remove os arquivos diarios mais antigos que a retencao configurada.
// Devolve a quantidade removida, ou -1 se nao foi possivel avaliar.
int expurgarLogsAntigos() {
  // Marca a tentativa antes de qualquer retorno antecipado, para que uma
  // falha nao faca o loop rechamar o expurgo a cada iteracao.
  ultimoExpurgoMs = millis();

  if (!sdDisponivel) return -1;

  struct tm agoraTm;
  if (!horaSincronizada(agoraTm)) return -1;  // sem data confiavel, nao apaga nada

  const time_t agora = mktime(&agoraTm);
  const time_t limite = agora - (time_t)retencaoDias * 86400L;

  File dir = SD.open(LOG_DIR);
  if (!dir || !dir.isDirectory()) {
    if (dir) dir.close();
    return -1;
  }

  // Coleta primeiro e apaga depois: remover durante a varredura invalida
  // o iterador do diretorio.
  static const int MAX_REMOCOES = 16;
  char paraRemover[MAX_REMOCOES][32];
  int total = 0;

  File entrada = dir.openNextFile();
  while (entrada && total < MAX_REMOCOES) {
    if (!entrada.isDirectory()) {
      const char* caminho = entrada.name();
      const char* barra = strrchr(caminho, '/');
      const char* base = (barra != nullptr) ? barra + 1 : caminho;

      const time_t doArquivo = epochDoNomeDeArquivo(base);
      if (doArquivo != 0 && doArquivo < limite) {
        snprintf(paraRemover[total], sizeof(paraRemover[total]), "%s/%s", LOG_DIR, base);
        total++;
      }
    }
    entrada.close();
    entrada = dir.openNextFile();
  }
  if (entrada) entrada.close();
  dir.close();

  int removidos = 0;
  for (int i = 0; i < total; i++) {
    if (SD.remove(paraRemover[i])) {
      removidos++;
      Serial.print("Log expurgado: ");
      Serial.println(paraRemover[i]);
    }
  }

  return removidos;
}

void registrarNoSD() {
  if (!sdDisponivel) return;

  char nome[32];
  if (!montarNomeArquivoDoDia(nome, sizeof(nome))) {
    return;  // sem hora valida nao ha como nomear o arquivo do dia
  }

  const bool arquivoNovo = !SD.exists(nome);
  File arquivo = SD.open(nome, FILE_APPEND);
  if (!arquivo) return;

  if (arquivoNovo) {
    arquivo.println("timestamp,ax_g,ay_g,az_g,magnitude_g,vibracao_rms_g,"
                    "vibracao_pico_g,temperatura_c,motor_on,estado_critico");
  }

  arquivo.print(g_timestamp);        arquivo.print(',');
  arquivo.print(g_ax, 3);            arquivo.print(',');
  arquivo.print(g_ay, 3);            arquivo.print(',');
  arquivo.print(g_az, 3);            arquivo.print(',');
  arquivo.print(g_magnitude, 3);     arquivo.print(',');
  arquivo.print(g_vibracaoRms, 4);   arquivo.print(',');
  arquivo.print(g_vibracaoPico, 4);  arquivo.print(',');
  if (g_tempValida) arquivo.print(g_temperatura, 1);
  arquivo.print(',');
  if (motorConhecido) arquivo.print(motorLigado ? 1 : 0);
  arquivo.print(',');
  arquivo.println(estadoCritico ? 1 : 0);
  arquivo.close();

  totalAmostrasGravadas++;
}

// -----------------------------------------------------------------------------
// MQTT - publicacoes
// -----------------------------------------------------------------------------
void montarTopicos() {
  snprintf(topicTelemetria, sizeof(topicTelemetria), "%s/%s/telemetry", TOPIC_PREFIX, DEVICE_ID);
  snprintf(topicStatus, sizeof(topicStatus), "%s/%s/status", TOPIC_PREFIX, DEVICE_ID);
  snprintf(topicComando, sizeof(topicComando), "%s/%s/command", TOPIC_PREFIX, DEVICE_ID);
  snprintf(topicTelemetriaRequest, sizeof(topicTelemetriaRequest), "%s/request/telemetry", TOPIC_PREFIX);
  snprintf(topicComandoRequest, sizeof(topicComandoRequest), "%s/request/command", TOPIC_PREFIX);
  snprintf(topicCapabilities, sizeof(topicCapabilities), "%s/%s/capabilities", TOPIC_PREFIX, DEVICE_ID);
  snprintf(topicTelemetriaAcionamento, sizeof(topicTelemetriaAcionamento), "%s/%s/telemetry",
           TOPIC_PREFIX, DEVICE_ID_ACIONAMENTO);
}

void publicarStatus(const char* valor) {
  if (mqttClient.connected()) {
    mqttClient.publish(topicStatus, valor, true);
  }
  Serial.print("[status] ");
  Serial.println(valor);
}

void publicarCapabilities() {
  StaticJsonDocument<512> doc;
  doc["device_id"] = DEVICE_ID;
  doc["role"] = "sensor";
  JsonArray campos = doc.createNestedArray("fields");
  campos.add("vibration");
  campos.add("temperature");
  doc["accepts_command_request"] = false;   // nao aciona o motor
  doc["accepts_direct_command"]  = false;
  doc["accepts_storage_config"]  = true;
  doc["storage_medium"]          = "sdcard";
  doc["retention_days"]          = retencaoDias;
  doc["request_telemetry_topic"] = topicTelemetriaRequest;
  doc["request_command_topic"]   = topicComandoRequest;
  doc["telemetry_topic"]         = topicTelemetria;
  doc["timestamp"]               = millis();

  char payload[512];
  size_t n = serializeJson(doc, payload, sizeof(payload));
  mqttClient.publish(topicCapabilities, (const uint8_t*)payload, n, true);
}

// Um pedido sem lista de campos (ou com lista vazia) significa "todos".
bool campoPedido(JsonVariantConst campos, const char* nome) {
  if (campos.isNull()) return true;
  JsonArrayConst lista = campos.as<JsonArrayConst>();
  if (lista.isNull() || lista.size() == 0) return true;
  for (JsonVariantConst item : lista) {
    const char* texto = item.as<const char*>();
    if (texto != nullptr && strcmp(texto, nome) == 0) return true;
  }
  return false;
}

void publicarTelemetria(JsonVariantConst campos, const char* requestId) {
  if (!mqttClient.connected()) return;

  const bool wantVib  = campoPedido(campos, "vibration");
  const bool wantTemp = campoPedido(campos, "temperature");

  StaticJsonDocument<448> doc;
  doc["device_id"] = DEVICE_ID;

  if (wantVib && mpuDisponivel) {
    doc["vibration"]      = g_vibracaoRms;
    doc["vibration_peak"] = g_vibracaoPico;
    doc["magnitude"]      = g_magnitude;
  }
  if (wantTemp && g_tempValida) {
    doc["temperature"] = g_temperatura;
  }

  doc["critical"]       = estadoCritico;
  doc["mpu_ok"]         = mpuDisponivel;
  doc["sd_ok"]          = sdDisponivel;
  // Sem interface local, o estado do registro so e visivel por aqui.
  doc["sd_samples"]     = totalAmostrasGravadas;
  doc["retention_days"] = retencaoDias;
  doc["seq"]            = g_contadorLeituras;
  if (requestId != nullptr && strlen(requestId) > 0) {
    doc["request_id"] = requestId;
  }

  char payload[448];
  size_t n = serializeJson(doc, payload, sizeof(payload));
  mqttClient.publish(topicTelemetria, (const uint8_t*)payload, n, false);
}

// -----------------------------------------------------------------------------
// MQTT - recepcao
// -----------------------------------------------------------------------------
// Uma mensagem de broadcast so vale para este modulo se nao trouxer device_id
// ou se o device_id apontar para ele.
bool destinadoAEsteModulo(const JsonDocument& doc) {
  const char* alvo = doc["device_id"] | "";
  if (strlen(alvo) == 0) return true;
  return strcmp(alvo, DEVICE_ID) == 0;
}

// Payload storage_config enviado pela aba Configuracoes > Armazenamento do app.
void tratarConfiguracaoDeArmazenamento(const JsonDocument& doc) {
  if (!destinadoAEsteModulo(doc)) return;

  int dias = 0;
  JsonVariantConst storage = doc["storage"];
  if (!storage.isNull()) {
    dias = storage["retention_days"] | 0;
  }
  if (dias <= 0) dias = doc["retention_days"] | 0;
  if (dias <= 0) dias = doc["remote_retention_days"] | 0;
  if (dias <= 0) {
    publicarStatus("storage_config_invalid");
    return;
  }

  if (dias < RETENCAO_MINIMA_DIAS) dias = RETENCAO_MINIMA_DIAS;
  if (dias > RETENCAO_MAXIMA_DIAS) dias = RETENCAO_MAXIMA_DIAS;

  retencaoDias = dias;
  salvarRetencaoPersistida(dias);

  Serial.print("Retencao remota ajustada para ");
  Serial.print(retencaoDias);
  Serial.println(" dias.");

  expurgarLogsAntigos();
  publicarStatus("storage_config_applied");
  publicarCapabilities();
}

void tratarTelemetriaDoAcionamento(const JsonDocument& doc) {
  if (doc.containsKey("motor_on")) {
    motorLigado = doc["motor_on"].as<bool>();
    motorConhecido = true;
  }
}

void aoReceberMqtt(char* topico, byte* payload, unsigned int tamanho) {
  StaticJsonDocument<512> doc;
  if (deserializeJson(doc, payload, tamanho)) {
    return;
  }

  if (strcmp(topico, topicTelemetriaRequest) == 0) {
    if (!destinadoAEsteModulo(doc)) return;
    publicarTelemetria(doc["fields"], doc["request_id"] | "");
    return;
  }

  if (strcmp(topico, topicComandoRequest) == 0 || strcmp(topico, topicComando) == 0) {
    const char* tipo = doc["type"] | "";
    if (strcmp(tipo, "storage_config") == 0) {
      tratarConfiguracaoDeArmazenamento(doc);
    }
    // Comandos de partida/parada nao pertencem a este modulo: sao do Modulo 1.
    return;
  }

  if (strcmp(topico, topicTelemetriaAcionamento) == 0) {
    tratarTelemetriaDoAcionamento(doc);
  }
}

// Nao bloqueia: tenta uma conexao por chamada e devolve o controle ao loop,
// para que a aquisicao e o registro no SD sigam rodando sem broker.
void manterMqtt(unsigned long agora) {
  if (WiFi.status() != WL_CONNECTED) return;
  if (mqttClient.connected()) return;
  if (agora - ultimaTentativaMqtt < INTERVALO_RECONEXAO_MQTT_MS) return;

  ultimaTentativaMqtt = agora;

  const String clientId = String("esp32_mod2_") + String(DEVICE_ID);
  bool ok;
  if (strlen(MQTT_USER) > 0) {
    ok = mqttClient.connect(clientId.c_str(), MQTT_USER, MQTT_PASS, topicStatus, 0, true, "offline");
  } else {
    ok = mqttClient.connect(clientId.c_str(), topicStatus, 0, true, "offline");
  }

  if (!ok) {
    Serial.print("Falha MQTT, rc=");
    Serial.println(mqttClient.state());
    return;
  }

  mqttClient.subscribe(topicTelemetriaRequest);
  mqttClient.subscribe(topicComandoRequest);
  mqttClient.subscribe(topicComando);
  mqttClient.subscribe(topicTelemetriaAcionamento);

  publicarStatus("online");
  publicarCapabilities();
  Serial.println("MQTT conectado.");
}

// -----------------------------------------------------------------------------
// Wi-Fi
// -----------------------------------------------------------------------------
void manterWifi(unsigned long agora) {
  static bool estavaConectado = false;
  const bool conectado = (WiFi.status() == WL_CONNECTED);

  if (conectado) {
    if (!estavaConectado) {
      estavaConectado = true;
      Serial.print("Wi-Fi conectado. IP: ");
      Serial.println(WiFi.localIP());
    }
    return;
  }

  if (estavaConectado) {
    estavaConectado = false;
    Serial.println("Wi-Fi desconectado.");
  }

  if (agora - ultimaTentativaWifi >= INTERVALO_RECONEXAO_WIFI) {
    ultimaTentativaWifi = agora;
    Serial.println("Tentando reconectar ao Wi-Fi...");
    WiFi.disconnect(false, false);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  }
}

// -----------------------------------------------------------------------------
// Aquisicao
// -----------------------------------------------------------------------------
// Amostra rapida: acumula o desvio em relacao a 1 g (gravidade) para compor
// RMS e pico da janela, em vez de publicar uma amostra instantanea isolada.
void amostrarVibracao() {
  float ax, ay, az;
  if (!lerAcelerometroBruto(ax, ay, az)) {
    mpuDisponivel = inicializarEForcarMPU();
    return;
  }

  mpuDisponivel = true;
  g_ax = ax;
  g_ay = ay;
  g_az = az;
  g_magnitude = sqrtf(ax * ax + ay * ay + az * az);

  const float desvio = fabsf(g_magnitude - 1.0f);
  somaQuadradosDesvio += (double)desvio * (double)desvio;
  amostrasNaJanela++;
  if (desvio > picoDesvioJanela) {
    picoDesvioJanela = desvio;
  }
}

void fecharJanelaDeVibracao() {
  if (amostrasNaJanela > 0) {
    g_vibracaoRms  = sqrtf((float)(somaQuadradosDesvio / (double)amostrasNaJanela));
    g_vibracaoPico = picoDesvioJanela;
  } else {
    g_vibracaoRms  = 0.0f;
    g_vibracaoPico = 0.0f;
  }
  somaQuadradosDesvio = 0.0;
  amostrasNaJanela = 0;
  picoDesvioJanela = 0.0f;
}

// O DS18B20 leva ate 750 ms por conversao: pede agora e le no ciclo seguinte.
void amostrarTemperatura() {
  const float lida = ds18b20.getTempCByIndex(0);
  g_tempValida = (lida != DEVICE_DISCONNECTED_C) && (lida > -55.0f) && (lida < 125.0f);
  if (g_tempValida) {
    g_temperatura = lida;
  }
  ds18b20.requestTemperatures();
}

void avaliarEstadoCritico() {
  const bool vibracaoCritica = mpuDisponivel && (g_vibracaoPico > VIBRACAO_LIMIAR_G);
  const bool temperaturaCritica = g_tempValida && (g_temperatura > TEMPERATURA_LIMIAR_C);
  estadoCritico = vibracaoCritica || temperaturaCritica;

  if (!mpuDisponivel && !g_tempValida) {
    setLED(true, false, false);   // azul: sem sensores validos
  } else {
    setLED(false, !estadoCritico, estadoCritico);
  }
}

// -----------------------------------------------------------------------------
// Setup
// -----------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println();
  Serial.println("=== IoTMotor | Modulo 2 (aquisicao) ===");

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(LED_BLUE_PIN, OUTPUT);
  pinMode(LED_GREEN_PIN, OUTPUT);
  pinMode(LED_RED_PIN, OUTPUT);
  noTone(BUZZER_PIN);
  setLED(true, false, false);

  carregarRetencaoPersistida();
  Serial.print("Retencao local no SD: ");
  Serial.print(retencaoDias);
  Serial.println(" dias.");

  mpuDisponivel = inicializarEForcarMPU();
  Serial.println(mpuDisponivel ? "MPU6050 inicializado." : "MPU6050 nao respondeu no boot.");

  ds18b20.begin();
  ds18b20.setWaitForConversion(false);
  ds18b20.requestTemperatures();

  montarTopicos();

  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);
  WiFi.setSleep(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  ultimaTentativaWifi = millis();

  Serial.print("Conectando ao Wi-Fi");
  const unsigned long inicio = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - inicio) < TEMPO_MAX_CONEXAO_WIFI) {
    delay(250);
    Serial.print('.');
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("Wi-Fi conectado. IP: ");
    Serial.println(WiFi.localIP());
    configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, NTP_SERVER);
  } else {
    Serial.println("Wi-Fi nao conectado. O modulo segue medindo e tentara reconectar.");
  }

  inicializarSD();
  expurgarLogsAntigos();

  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(aoReceberMqtt);
  mqttClient.setBufferSize(768);

  setLED(false, true, false);
}

// -----------------------------------------------------------------------------
// Loop
// -----------------------------------------------------------------------------
void loop() {
  const unsigned long agora = millis();

  manterWifi(agora);
  manterMqtt(agora);
  mqttClient.loop();

  if (agora - ultimaAmostraMs >= INTERVALO_AMOSTRA_MS) {
    ultimaAmostraMs = agora;
    amostrarVibracao();
  }

  if (agora - ultimaTemperaturaMs >= INTERVALO_TEMPERATURA_MS) {
    ultimaTemperaturaMs = agora;
    amostrarTemperatura();
  }

  if (agora - ultimaTelemetriaMs >= INTERVALO_TELEMETRIA_MS) {
    ultimaTelemetriaMs = agora;

    fecharJanelaDeVibracao();
    avaliarEstadoCritico();
    g_timestamp = obterTimestamp();
    g_contadorLeituras++;

    publicarTelemetria(JsonVariantConst(), "");

    // Um estado critico e sempre registrado, mesmo fora da cadencia normal.
    if (estadoCritico || (agora - ultimoRegistroSdMs >= INTERVALO_REGISTRO_SD_MS)) {
      ultimoRegistroSdMs = agora;
      registrarNoSD();
    }
  }

  if (agora - ultimoExpurgoMs >= INTERVALO_EXPURGO_MS) {
    expurgarLogsAntigos();
  }

  atualizarAlarmeSonoro(agora);

  delay(1);
}
