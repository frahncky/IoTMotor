/* ============================================================
 * PROJETO: Sistema de Comandos e Medicao de Maquinas Eletricas
 *          via Internet of Things (IoT)
 *
 * MODULO 1 - ESP32 DevKit V1  (device_id: esp32-01)
 * Papel: ACIONAMENTO do motor + MEDICAO ELETRICA
 *
 * Reune, num unico firmware:
 *   - Medicao real com PZEM-004T v3 (tensao, corrente, potencia,
 *     fator de potencia, frequencia e energia);
 *   - Acionamento por 4 reles com partida direta, partida
 *     estrela-triangulo (maquina de estados nao bloqueante) e parada;
 *   - LCD I2C 20x4 com cache de linhas (sem flicker);
 *   - Pagina web local (http://modulo1.local/) para operacao
 *     direta, sem broker;
 *   - Ponte MQTT no mesmo contrato do aplicativo Flutter IoTMotor,
 *     de modo que pagina web e aplicativo comandem o mesmo motor;
 *   - Protecao eletrica local (sub/sobretensao e sobrecorrente) e
 *     protecao cruzada: assina a telemetria do Modulo 2 (esp32-02)
 *     e desliga o motor em vibracao ou temperatura critica.
 *
 * Bibliotecas:
 *   - PubSubClient (Nick O'Leary)
 *   - ArduinoJson (Benoit Blanchon) 6.x
 *   - PZEM004Tv30 (Jakub Mandula) >= 1.1.2
 *   - LiquidCrystal I2C (Frank de Brabander)
 *   - WiFi / WebServer / ESPmDNS (core ESP32)
 *
 * Ligacoes:
 *   PZEM TX  -> GPIO16 (RX2)      LCD SDA -> GPIO21
 *   PZEM RX  -> GPIO17 (TX2)      LCD SCL -> GPIO22
 *   PZEM VCC -> 5V / VIN          PZEM GND -> GND
 *
 *   Rele 1 (K1 linha)      -> GPIO19
 *   Rele 2 (K2 estrela)    -> GPIO18
 *   Rele 3 (K3 triangulo)  -> GPIO23
 *   Rele 4 (K4 auxiliar)   -> GPIO27
 *
 * IFMA - Projeto PIBITI
 * Orientador: Prof. Almir Souza e Silva Neto
 * ============================================================ */

#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <PZEM004Tv30.h>
#include <math.h>

// -----------------------------------------------------------------------------
// Wi-Fi
// -----------------------------------------------------------------------------
static const char* WIFI_SSID     = "BotComp";
static const char* WIFI_PASSWORD = "linguagemC";
static const char* NOME_MDNS     = "modulo1";

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
static const char* DEVICE_ID    = "esp32-01";

// device_id do Modulo 2, cuja telemetria e usada na protecao cruzada.
static const char* DEVICE_ID_SENSORES = "esp32-02";

static const bool ACEITA_COMANDO_BROADCAST = true;  // topico <prefix>/request/command
static const bool ACEITA_COMANDO_DIRETO    = true;  // topico <prefix>/esp32-01/command

static const unsigned long INTERVALO_TELEMETRIA_MS = 1000UL;
static const unsigned long INTERVALO_RECONEXAO_MQTT_MS = 3000UL;

// -----------------------------------------------------------------------------
// Reles / acionamento
// -----------------------------------------------------------------------------
static const uint8_t NUM_RELES = 4;
static const uint8_t PINOS_RELES[NUM_RELES] = {19, 18, 23, 27};

// Indices logicos dos contatores.
static const uint8_t K_LINHA     = 0;  // contator de linha
static const uint8_t K_ESTRELA   = 1;  // contator de estrela
static const uint8_t K_TRIANGULO = 2;  // contator de triangulo
static const uint8_t K_AUXILIAR  = 3;  // sinalizacao / uso livre

// Ajuste conforme o modulo de rele:
//   false -> HIGH liga o rele
//   true  -> LOW liga o rele (comum em modulos com optoacoplador)
static const bool RELE_ATIVO_EM_NIVEL_BAIXO = false;

// Tempos da partida estrela-triangulo.
static const unsigned long TEMPO_ESTRELA_MS = 5000UL;  // permanencia em estrela
static const unsigned long TEMPO_MORTO_MS   = 250UL;   // intertravamento na comutacao

bool estadoReles[NUM_RELES] = {false, false, false, false};

enum EstadoAcionamento {
  ACIONAMENTO_PARADO,
  ACIONAMENTO_ESTRELA,
  ACIONAMENTO_TEMPO_MORTO,
  ACIONAMENTO_RODANDO
};

EstadoAcionamento estadoAcionamento = ACIONAMENTO_PARADO;
unsigned long marcoEstadoAcionamento = 0;
String modoAtual = "manual_stop";
String motivoUltimaParada = "";

// -----------------------------------------------------------------------------
// Protecoes
// -----------------------------------------------------------------------------
static const bool  PROTECAO_ELETRICA_HABILITADA = true;
static const float TENSAO_MINIMA_V     = 190.0f;
static const float TENSAO_MAXIMA_V     = 240.0f;
static const float CORRENTE_MAXIMA_A   = 10.0f;
// Ignora as protecoes de tensao/corrente logo apos a partida (inrush).
static const unsigned long JANELA_PARTIDA_MS = 4000UL;

static const bool  PROTECAO_CRUZADA_HABILITADA = true;
static const float VIBRACAO_MAXIMA_G     = 1.5f;
static const float TEMPERATURA_MAXIMA_C  = 70.0f;
// Se o Modulo 2 ficar mudo por mais que isso, a protecao cruzada e suspensa
// (nao derruba o motor apenas porque o outro modulo caiu).
static const unsigned long VALIDADE_TELEMETRIA_SENSORES_MS = 15000UL;

float ultimaVibracaoSensores = NAN;
float ultimaTemperaturaSensores = NAN;
unsigned long recebidoTelemetriaSensoresMs = 0;
bool travaProtecao = false;   // exige parada explicita antes de nova partida

// -----------------------------------------------------------------------------
// LCD I2C 20x4
// -----------------------------------------------------------------------------
static const uint8_t LCD_ENDERECO = 0x27;
static const uint8_t LCD_COLUNAS  = 20;
static const uint8_t LCD_LINHAS   = 4;
static const uint8_t LCD_SDA      = 21;
static const uint8_t LCD_SCL      = 22;
LiquidCrystal_I2C lcd(LCD_ENDERECO, LCD_COLUNAS, LCD_LINHAS);

char lcdCache[LCD_LINHAS][LCD_COLUNAS + 1];
volatile bool lcdPrecisaAtualizar = false;
unsigned long ultimaAtualizacaoLcd = 0;
static const unsigned long INTERVALO_LCD = 1000UL;

// -----------------------------------------------------------------------------
// PZEM-004T
// -----------------------------------------------------------------------------
static const uint8_t PZEM_RX_PIN = 16;  // RX do ESP32 -> TX do PZEM
static const uint8_t PZEM_TX_PIN = 17;  // TX do ESP32 -> RX do PZEM
static const bool PZEM_HABILITADO = true;

// Criado no setup(): construir globalmente faria a biblioteca chamar
// Serial2.begin() antes de o core do ESP32 estar pronto.
PZEM004Tv30* pzem = nullptr;

float ultimaTensao        = 0.0f;
float ultimaCorrente      = 0.0f;
float ultimaPotencia      = 0.0f;
float ultimaEnergia       = 0.0f;
float ultimaFrequencia    = 0.0f;
float ultimoFatorPotencia = 0.0f;
bool  pzemOk = false;

unsigned long ultimaLeituraPzem = 0;
static const unsigned long INTERVALO_LEITURA_PZEM = 3000UL;

// -----------------------------------------------------------------------------
// Objetos de rede
// -----------------------------------------------------------------------------
WebServer server(80);
WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

char topicTelemetria[96];
char topicStatus[96];
char topicComando[96];
char topicTelemetriaRequest[96];
char topicComandoRequest[96];
char topicCapabilities[96];
char topicTelemetriaSensores[96];

unsigned long ultimaTelemetriaMs   = 0;
unsigned long ultimaTentativaWifi  = 0;
unsigned long ultimaTentativaMqtt  = 0;
bool mdnsAtivo = false;

// -----------------------------------------------------------------------------
// Pagina web local
// -----------------------------------------------------------------------------
const char INDEX_HTML[] PROGMEM = R"====(
<!DOCTYPE html>
<html lang="pt-br">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Modulo 1 - Acionamento</title>
<style>
  body { font-family: Arial, Helvetica, sans-serif; background:#0f1720; color:#e6edf3; margin:0; padding:20px; }
  h1 { font-size:20px; margin:0 0 4px; }
  .sub { font-size:13px; color:#8b98a5; margin-bottom:18px; }
  .ok { color:#3fb950; }
  .alerta { color:#f59e0b; }
  .erro { color:#f85149; }
  .cartao { background:#161e27; border:1px solid #24303c; border-radius:10px; padding:16px; margin-bottom:16px; }
  .rotulo { font-size:11px; color:#8b98a5; text-transform:uppercase; letter-spacing:.05em; margin-bottom:10px; }
  .grade { display:grid; grid-template-columns:repeat(auto-fit,minmax(130px,1fr)); gap:10px; }
  .medida { background:#0d1117; border-radius:8px; padding:10px; text-align:center; }
  .medida .valor { font-size:20px; font-weight:700; }
  .medida .nome { font-size:12px; color:#8b98a5; margin-top:2px; }
  .estado { font-size:24px; font-weight:700; margin-bottom:4px; }
  .modo { font-size:13px; color:#8b98a5; }
  .botoes { display:flex; flex-wrap:wrap; gap:10px; margin-top:14px; }
  button { border:none; border-radius:6px; padding:12px 18px; font-size:14px; font-weight:700; cursor:pointer; color:#fff; }
  button:disabled { opacity:.5; cursor:wait; }
  .b-direta { background:#16a34a; }
  .b-estrela { background:#2563eb; }
  .b-parar { background:#dc2626; }
  .reles { display:flex; flex-wrap:wrap; gap:8px; margin-top:10px; }
  .rele { background:#0d1117; border:1px solid #24303c; border-radius:6px; padding:6px 10px; font-size:12px; }
  .rele.on { border-color:#3fb950; color:#3fb950; }
</style>
</head>
<body>
  <h1>Modulo 1 &mdash; Acionamento e Medicao</h1>
  <div class="sub" id="subtitulo">Carregando...</div>

  <div class="cartao">
    <div class="rotulo">Estado do motor</div>
    <div class="estado" id="estadoMotor">--</div>
    <div class="modo" id="modoMotor">--</div>
    <div class="botoes">
      <button class="b-direta" id="btDireta">Partida direta</button>
      <button class="b-estrela" id="btEstrela">Estrela-triangulo</button>
      <button class="b-parar" id="btParar">Parar</button>
    </div>
    <div class="reles" id="listaReles"></div>
  </div>

  <div class="cartao">
    <div class="rotulo">Medicao eletrica (PZEM-004T)</div>
    <div class="grade">
      <div class="medida"><div class="valor" id="vTensao">--</div><div class="nome">Tensao (V)</div></div>
      <div class="medida"><div class="valor" id="vCorrente">--</div><div class="nome">Corrente (A)</div></div>
      <div class="medida"><div class="valor" id="vPotencia">--</div><div class="nome">Potencia (W)</div></div>
      <div class="medida"><div class="valor" id="vEnergia">--</div><div class="nome">Energia (kWh)</div></div>
      <div class="medida"><div class="valor" id="vFrequencia">--</div><div class="nome">Frequencia (Hz)</div></div>
      <div class="medida"><div class="valor" id="vFP">--</div><div class="nome">Fator de potencia</div></div>
    </div>
  </div>

  <div class="cartao">
    <div class="rotulo">Modulo 2 (protecao cruzada)</div>
    <div class="grade">
      <div class="medida"><div class="valor" id="vVibracao">--</div><div class="nome">Vibracao (g)</div></div>
      <div class="medida"><div class="valor" id="vTemperatura">--</div><div class="nome">Temperatura (C)</div></div>
    </div>
    <div class="modo" id="avisoProtecao" style="margin-top:10px;"></div>
  </div>

<script>
var ocupado = false;

function texto(id, valor) { document.getElementById(id).textContent = valor; }

function rotuloEstado(estado) {
  if (estado === 'rodando') return 'RODANDO';
  if (estado === 'estrela') return 'PARTINDO (ESTRELA)';
  if (estado === 'tempo_morto') return 'COMUTANDO';
  return 'PARADO';
}

async function atualizar() {
  try {
    const resp = await fetch('/dados', { cache: 'no-store' });
    if (!resp.ok) throw new Error('HTTP ' + resp.status);
    const d = await resp.json();

    const sub = document.getElementById('subtitulo');
    const partes = [];
    partes.push(d.mqtt_ok ? 'MQTT conectado' : 'MQTT desconectado');
    partes.push(d.pzem_ok ? 'PZEM respondendo' : 'PZEM sem leitura');
    sub.textContent = partes.join(' | ') + ' | ' + d.device_id;
    sub.className = 'sub ' + ((d.mqtt_ok && d.pzem_ok) ? 'ok' : 'alerta');

    texto('estadoMotor', rotuloEstado(d.estado));
    document.getElementById('estadoMotor').className =
      'estado ' + (d.motor_on ? 'ok' : (d.trava_protecao ? 'erro' : ''));
    texto('modoMotor', 'Modo: ' + d.mode + (d.motivo_parada ? ' | ' + d.motivo_parada : ''));

    texto('vTensao',     d.pzem_ok ? d.voltage.toFixed(1) : '--');
    texto('vCorrente',   d.pzem_ok ? d.current.toFixed(2) : '--');
    texto('vPotencia',   d.pzem_ok ? d.power.toFixed(0) : '--');
    texto('vEnergia',    d.pzem_ok ? d.energy.toFixed(3) : '--');
    texto('vFrequencia', d.pzem_ok ? d.frequency.toFixed(1) : '--');
    texto('vFP',         d.pzem_ok ? d.pf.toFixed(2) : '--');

    texto('vVibracao',    d.sensores_ok ? d.vibration.toFixed(3) : '--');
    texto('vTemperatura', d.sensores_ok ? d.temperature.toFixed(1) : '--');
    document.getElementById('avisoProtecao').textContent = d.sensores_ok
      ? 'Telemetria do Modulo 2 valida.'
      : 'Sem telemetria recente do Modulo 2 - protecao cruzada suspensa.';

    const lista = document.getElementById('listaReles');
    lista.innerHTML = '';
    const nomes = ['K1 linha', 'K2 estrela', 'K3 triangulo', 'K4 auxiliar'];
    d.reles.forEach(function (ligado, i) {
      const el = document.createElement('div');
      el.className = 'rele' + (ligado ? ' on' : '');
      el.textContent = nomes[i] + ': ' + (ligado ? 'ON' : 'OFF');
      lista.appendChild(el);
    });
  } catch (e) {
    const sub = document.getElementById('subtitulo');
    sub.textContent = 'Erro de comunicacao com o ESP32';
    sub.className = 'sub erro';
  }
}

async function comandar(tipo) {
  if (ocupado) return;
  ocupado = true;
  const botoes = document.querySelectorAll('button');
  botoes.forEach(function (b) { b.disabled = true; });
  try {
    const resp = await fetch('/comando?tipo=' + tipo, { cache: 'no-store' });
    const corpo = await resp.text();
    if (!resp.ok) throw new Error(corpo);
  } catch (e) {
    alert('Falha ao comandar: ' + e.message);
  } finally {
    ocupado = false;
    botoes.forEach(function (b) { b.disabled = false; });
    atualizar();
  }
}

document.getElementById('btDireta').addEventListener('click', function () { comandar('direct'); });
document.getElementById('btEstrela').addEventListener('click', function () { comandar('star_delta'); });
document.getElementById('btParar').addEventListener('click', function () { comandar('stop'); });

atualizar();
setInterval(atualizar, 1500);
</script>
</body>
</html>
)====";

// -----------------------------------------------------------------------------
// Reles
// -----------------------------------------------------------------------------
static inline uint8_t nivelLigado()    { return RELE_ATIVO_EM_NIVEL_BAIXO ? LOW : HIGH; }
static inline uint8_t nivelDesligado() { return RELE_ATIVO_EM_NIVEL_BAIXO ? HIGH : LOW; }

void escreverRele(uint8_t indice, bool ligado) {
  if (indice >= NUM_RELES) return;
  estadoReles[indice] = ligado;
  digitalWrite(PINOS_RELES[indice], ligado ? nivelLigado() : nivelDesligado());
}

// Intertravamento fisico: estrela e triangulo nunca podem fechar juntos.
void aplicarContatores(bool linha, bool estrela, bool triangulo) {
  if (estrela && triangulo) {
    estrela = false;
    triangulo = false;
  }

  // Abre antes de fechar, para nao haver instante com os dois contatores ativos.
  if (!estrela)   escreverRele(K_ESTRELA, false);
  if (!triangulo) escreverRele(K_TRIANGULO, false);

  escreverRele(K_LINHA, linha);
  if (estrela)   escreverRele(K_ESTRELA, true);
  if (triangulo) escreverRele(K_TRIANGULO, true);

  escreverRele(K_AUXILIAR, linha);
  lcdPrecisaAtualizar = true;
}

bool motorLigado() {
  return estadoAcionamento != ACIONAMENTO_PARADO;
}

const char* nomeEstadoAcionamento() {
  switch (estadoAcionamento) {
    case ACIONAMENTO_ESTRELA:     return "estrela";
    case ACIONAMENTO_TEMPO_MORTO: return "tempo_morto";
    case ACIONAMENTO_RODANDO:     return "rodando";
    default:                      return "parado";
  }
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
  snprintf(topicTelemetriaSensores, sizeof(topicTelemetriaSensores), "%s/%s/telemetry",
           TOPIC_PREFIX, DEVICE_ID_SENSORES);
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
  doc["role"] = "actuator";
  JsonArray campos = doc.createNestedArray("fields");
  campos.add("voltage");
  campos.add("current");
  campos.add("power");
  campos.add("pf");
  campos.add("frequency");
  campos.add("energy");
  JsonArray modos = doc.createNestedArray("start_modes");
  modos.add("direct");
  modos.add("star_delta");
  doc["accepts_command_request"] = ACEITA_COMANDO_BROADCAST;
  doc["accepts_direct_command"]  = ACEITA_COMANDO_DIRETO;
  doc["request_telemetry_topic"] = topicTelemetriaRequest;
  doc["request_command_topic"]   = topicComandoRequest;
  doc["command_topic"]           = topicComando;
  doc["telemetry_topic"]         = topicTelemetria;
  doc["local_page"]              = WiFi.localIP().toString();
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

  const bool wantV  = campoPedido(campos, "voltage");
  const bool wantI  = campoPedido(campos, "current");
  const bool wantP  = campoPedido(campos, "power");
  const bool wantPf = campoPedido(campos, "pf");
  const bool wantF  = campoPedido(campos, "frequency");
  const bool wantE  = campoPedido(campos, "energy");

  StaticJsonDocument<384> doc;
  doc["device_id"] = DEVICE_ID;

  if (pzemOk) {
    if (wantV)  doc["voltage"]   = ultimaTensao;
    if (wantI)  doc["current"]   = ultimaCorrente;
    if (wantP)  doc["power"]     = ultimaPotencia;
    if (wantPf) doc["pf"]        = ultimoFatorPotencia;
    if (wantF)  doc["frequency"] = ultimaFrequencia;
    if (wantE)  doc["energy"]    = ultimaEnergia;
  }

  doc["motor_on"] = motorLigado();
  doc["mode"]     = modoAtual;
  doc["state"]    = nomeEstadoAcionamento();
  doc["pzem_ok"]  = pzemOk;
  if (requestId != nullptr && strlen(requestId) > 0) {
    doc["request_id"] = requestId;
  }

  char payload[384];
  size_t n = serializeJson(doc, payload, sizeof(payload));
  mqttClient.publish(topicTelemetria, (const uint8_t*)payload, n, false);
}

// -----------------------------------------------------------------------------
// Acionamento
// -----------------------------------------------------------------------------
void pararMotor(const char* motivo) {
  aplicarContatores(false, false, false);
  estadoAcionamento = ACIONAMENTO_PARADO;
  marcoEstadoAcionamento = millis();
  modoAtual = "manual_stop";
  motivoUltimaParada = (motivo != nullptr) ? String(motivo) : String("");
  publicarStatus("motor_stopped");
}

bool iniciarMotor(const String& modo) {
  if (travaProtecao) {
    publicarStatus("blocked_by_protection");
    return false;
  }

  if (modo == "star_delta") {
    // Fecha estrela primeiro e so entao a linha, como no comando real.
    aplicarContatores(false, true, false);
    aplicarContatores(true, true, false);
    estadoAcionamento = ACIONAMENTO_ESTRELA;
  } else {
    // Partida direta: motor ligado em triangulo, tensao plena.
    aplicarContatores(true, false, true);
    estadoAcionamento = ACIONAMENTO_RODANDO;
  }

  marcoEstadoAcionamento = millis();
  modoAtual = modo;
  motivoUltimaParada = "";
  publicarStatus("motor_started");
  return true;
}

// Avanca a maquina de estados da partida estrela-triangulo sem bloquear o loop.
void atualizarAcionamento(unsigned long agora) {
  switch (estadoAcionamento) {
    case ACIONAMENTO_ESTRELA:
      if (agora - marcoEstadoAcionamento >= TEMPO_ESTRELA_MS) {
        aplicarContatores(true, false, false);  // abre a estrela
        estadoAcionamento = ACIONAMENTO_TEMPO_MORTO;
        marcoEstadoAcionamento = agora;
      }
      break;

    case ACIONAMENTO_TEMPO_MORTO:
      if (agora - marcoEstadoAcionamento >= TEMPO_MORTO_MS) {
        aplicarContatores(true, false, true);   // fecha o triangulo
        estadoAcionamento = ACIONAMENTO_RODANDO;
        marcoEstadoAcionamento = agora;
        publicarStatus("motor_running");
      }
      break;

    default:
      break;
  }
}

void aplicarComando(const char* comando, const char* modo) {
  if (comando == nullptr) return;

  if (strcmp(comando, "stop") == 0) {
    travaProtecao = false;  // parada explicita rearma a protecao
    pararMotor("parada solicitada");
    return;
  }

  if (strcmp(comando, "start") == 0) {
    const String modoPedido = (modo != nullptr && strlen(modo) > 0) ? String(modo) : String("direct");
    if (motorLigado()) {
      // Ja em movimento: nao reinicia a partida, apenas confirma.
      publicarStatus("motor_started");
      return;
    }
    iniciarMotor(modoPedido);
    return;
  }

  publicarStatus("unknown_command");
}

// -----------------------------------------------------------------------------
// Protecoes
// -----------------------------------------------------------------------------
void dispararProtecao(const char* motivo, const char* status) {
  travaProtecao = true;
  pararMotor(motivo);
  publicarStatus(status);
  Serial.print("[protecao] ");
  Serial.println(motivo);
}

bool telemetriaSensoresValida() {
  if (recebidoTelemetriaSensoresMs == 0) return false;
  return (millis() - recebidoTelemetriaSensoresMs) <= VALIDADE_TELEMETRIA_SENSORES_MS;
}

void avaliarProtecoes(unsigned long agora) {
  if (!motorLigado()) return;

  // Durante o inrush da partida, corrente e tensao saem da faixa normalmente.
  const bool dentroDaJanelaDePartida =
      (agora - marcoEstadoAcionamento) < JANELA_PARTIDA_MS ||
      estadoAcionamento == ACIONAMENTO_ESTRELA ||
      estadoAcionamento == ACIONAMENTO_TEMPO_MORTO;

  if (PROTECAO_ELETRICA_HABILITADA && pzemOk && !dentroDaJanelaDePartida) {
    if (ultimaCorrente > CORRENTE_MAXIMA_A) {
      dispararProtecao("sobrecorrente", "protection_overcurrent");
      return;
    }
    if (ultimaTensao > TENSAO_MAXIMA_V) {
      dispararProtecao("sobretensao", "protection_overvoltage");
      return;
    }
    if (ultimaTensao < TENSAO_MINIMA_V) {
      dispararProtecao("subtensao", "protection_undervoltage");
      return;
    }
  }

  if (PROTECAO_CRUZADA_HABILITADA && telemetriaSensoresValida()) {
    if (!isnan(ultimaVibracaoSensores) && ultimaVibracaoSensores > VIBRACAO_MAXIMA_G) {
      dispararProtecao("vibracao critica no Modulo 2", "protection_vibration");
      return;
    }
    if (!isnan(ultimaTemperaturaSensores) && ultimaTemperaturaSensores > TEMPERATURA_MAXIMA_C) {
      dispararProtecao("temperatura critica no Modulo 2", "protection_temperature");
      return;
    }
  }
}

// -----------------------------------------------------------------------------
// PZEM
// -----------------------------------------------------------------------------
void marcarPzemIndisponivel() {
  if (pzemOk) Serial.println("PZEM perdeu comunicacao.");
  pzemOk = false;
  lcdPrecisaAtualizar = true;
}

void lerPzem() {
  if (!PZEM_HABILITADO || pzem == nullptr) {
    pzemOk = false;
    return;
  }

  // A primeira chamada dispara a leitura Modbus. Se falhar, sai imediatamente
  // em vez de encadear mais cinco timeouts seriais dentro do loop.
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
void imprimirLinhaCompleta(uint8_t linha, const char* texto) {
  if (linha >= LCD_LINHAS) return;

  char buffer[LCD_COLUNAS + 1];
  snprintf(buffer, sizeof(buffer), "%-*.*s", LCD_COLUNAS, LCD_COLUNAS, texto);

  // Evita reescrever (e piscar) uma linha que nao mudou.
  if (strcmp(buffer, lcdCache[linha]) == 0) return;
  strcpy(lcdCache[linha], buffer);

  lcd.setCursor(0, linha);
  lcd.print(buffer);
}

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
    snprintf(buffer, sizeof(buffer), "P:%4.0fW E:%8.2fkWh", ultimaPotencia, ultimaEnergia);
  } else {
    buffer[0] = '\0';
  }
  imprimirLinhaCompleta(2, buffer);

  const char* rotuloEstado;
  switch (estadoAcionamento) {
    case ACIONAMENTO_ESTRELA:     rotuloEstado = "ESTRELA"; break;
    case ACIONAMENTO_TEMPO_MORTO: rotuloEstado = "COMUTA "; break;
    case ACIONAMENTO_RODANDO:     rotuloEstado = "RODANDO"; break;
    default:                      rotuloEstado = travaProtecao ? "TRAVADO" : "PARADO "; break;
  }
  snprintf(buffer, sizeof(buffer), "%s %c%c%c%c %s",
           rotuloEstado,
           estadoReles[0] ? '1' : '-',
           estadoReles[1] ? '2' : '-',
           estadoReles[2] ? '3' : '-',
           estadoReles[3] ? '4' : '-',
           mqttClient.connected() ? "MQ" : "--");
  imprimirLinhaCompleta(3, buffer);

  lcdPrecisaAtualizar = false;
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

void tratarComandoMqtt(const JsonDocument& doc, bool viaBroadcast) {
  if (viaBroadcast && !ACEITA_COMANDO_BROADCAST) return;
  if (!viaBroadcast && !ACEITA_COMANDO_DIRETO) return;
  if (viaBroadcast && !destinadoAEsteModulo(doc)) return;

  // O topico de broadcast tambem carrega configuracoes que nao sao do Modulo 1
  // (por exemplo storage_config, tratada pelo Modulo 2).
  const char* tipo = doc["type"] | "";
  if (strlen(tipo) > 0 && strcmp(tipo, "command_request") != 0) return;

  const char* comando = doc["command"] | "";
  const char* modo    = doc["mode"] | "direct";
  aplicarComando(comando, modo);
}

void tratarTelemetriaDosSensores(const JsonDocument& doc) {
  bool recebeuAlgo = false;

  if (doc.containsKey("vibration")) {
    ultimaVibracaoSensores = doc["vibration"].as<float>();
    recebeuAlgo = true;
  }
  if (doc.containsKey("temperature")) {
    ultimaTemperaturaSensores = doc["temperature"].as<float>();
    recebeuAlgo = true;
  }

  if (recebeuAlgo) {
    recebidoTelemetriaSensoresMs = millis();
  }
}

void aoReceberMqtt(char* topico, byte* payload, unsigned int tamanho) {
  StaticJsonDocument<512> doc;
  DeserializationError erro = deserializeJson(doc, payload, tamanho);
  if (erro) {
    if (strcmp(topico, topicComando) == 0 || strcmp(topico, topicComandoRequest) == 0) {
      publicarStatus("invalid_command_json");
    }
    return;
  }

  if (strcmp(topico, topicComando) == 0) {
    tratarComandoMqtt(doc, false);
    return;
  }

  if (strcmp(topico, topicComandoRequest) == 0) {
    tratarComandoMqtt(doc, true);
    return;
  }

  if (strcmp(topico, topicTelemetriaRequest) == 0) {
    if (!destinadoAEsteModulo(doc)) return;
    publicarTelemetria(doc["fields"], doc["request_id"] | "");
    return;
  }

  if (strcmp(topico, topicTelemetriaSensores) == 0) {
    tratarTelemetriaDosSensores(doc);
  }
}

// Nao bloqueia: tenta uma conexao por chamada e devolve o controle ao loop.
void manterMqtt(unsigned long agora) {
  if (WiFi.status() != WL_CONNECTED) return;
  if (mqttClient.connected()) return;
  if (agora - ultimaTentativaMqtt < INTERVALO_RECONEXAO_MQTT_MS) return;

  ultimaTentativaMqtt = agora;

  const String clientId = String("esp32_mod1_") + String(DEVICE_ID);
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

  mqttClient.subscribe(topicComando);
  mqttClient.subscribe(topicComandoRequest);
  mqttClient.subscribe(topicTelemetriaRequest);
  mqttClient.subscribe(topicTelemetriaSensores);

  publicarStatus("online");
  publicarCapabilities();
  lcdPrecisaAtualizar = true;
  Serial.println("MQTT conectado.");
}

// -----------------------------------------------------------------------------
// Wi-Fi / mDNS
// -----------------------------------------------------------------------------
void iniciarMdns() {
  if (WiFi.status() != WL_CONNECTED || mdnsAtivo) return;

  if (MDNS.begin(NOME_MDNS)) {
    mdnsAtivo = true;
    MDNS.addService("http", "tcp", 80);
    Serial.print("mDNS ativo: http://");
    Serial.print(NOME_MDNS);
    Serial.println(".local/");
  } else {
    Serial.println("Falha ao iniciar mDNS. Use o endereco IP.");
  }
}

void manterWifi(unsigned long agora) {
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

  if (agora - ultimaTentativaWifi >= INTERVALO_RECONEXAO_WIFI) {
    ultimaTentativaWifi = agora;
    Serial.println("Tentando reconectar ao Wi-Fi...");
    WiFi.disconnect(false, false);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  }
}

// -----------------------------------------------------------------------------
// Rotas HTTP
// -----------------------------------------------------------------------------
void cabecalhosComuns() {
  server.sendHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
  server.sendHeader("Pragma", "no-cache");
  server.sendHeader("Access-Control-Allow-Origin", "*");
}

void tratarIndex() {
  cabecalhosComuns();
  server.send_P(200, "text/html; charset=utf-8", INDEX_HTML);
}

void tratarDados() {
  StaticJsonDocument<768> doc;
  doc["device_id"]   = DEVICE_ID;
  doc["wifi_ok"]     = (WiFi.status() == WL_CONNECTED);
  doc["mqtt_ok"]     = mqttClient.connected();
  doc["pzem_ok"]     = pzemOk;
  doc["voltage"]     = ultimaTensao;
  doc["current"]     = ultimaCorrente;
  doc["power"]       = ultimaPotencia;
  doc["energy"]      = ultimaEnergia;
  doc["frequency"]   = ultimaFrequencia;
  doc["pf"]          = ultimoFatorPotencia;
  doc["motor_on"]    = motorLigado();
  doc["mode"]        = modoAtual;
  doc["estado"]      = nomeEstadoAcionamento();
  doc["trava_protecao"]  = travaProtecao;
  doc["motivo_parada"]   = motivoUltimaParada;
  doc["sensores_ok"]     = telemetriaSensoresValida();
  doc["vibration"]       = isnan(ultimaVibracaoSensores) ? 0.0f : ultimaVibracaoSensores;
  doc["temperature"]     = isnan(ultimaTemperaturaSensores) ? 0.0f : ultimaTemperaturaSensores;

  JsonArray reles = doc.createNestedArray("reles");
  for (uint8_t i = 0; i < NUM_RELES; i++) {
    reles.add(estadoReles[i]);
  }

  String corpo;
  serializeJson(doc, corpo);
  cabecalhosComuns();
  server.send(200, "application/json; charset=utf-8", corpo);
}

void tratarComandoWeb() {
  cabecalhosComuns();

  if (!server.hasArg("tipo")) {
    server.send(400, "text/plain; charset=utf-8", "Parametro 'tipo' e obrigatorio.");
    return;
  }

  const String tipo = server.arg("tipo");

  if (tipo == "stop") {
    aplicarComando("stop", "manual_stop");
    server.send(200, "text/plain; charset=utf-8", "OK");
    return;
  }

  if (tipo == "direct" || tipo == "star_delta") {
    if (travaProtecao) {
      server.send(409, "text/plain; charset=utf-8",
                  "Protecao atuada. Envie 'Parar' para rearmar antes de nova partida.");
      return;
    }
    aplicarComando("start", tipo.c_str());
    server.send(200, "text/plain; charset=utf-8", "OK");
    return;
  }

  server.send(400, "text/plain; charset=utf-8",
              "Tipo invalido. Use direct, star_delta ou stop.");
}

// Mantido por compatibilidade com a versao v6: aciona um rele avulso.
// So funciona com o motor parado, para nao furar o intertravamento.
void tratarReleWeb() {
  cabecalhosComuns();

  if (!server.hasArg("canal") || !server.hasArg("estado")) {
    server.send(400, "text/plain; charset=utf-8",
                "Parametros 'canal' e 'estado' sao obrigatorios.");
    return;
  }

  if (motorLigado()) {
    server.send(409, "text/plain; charset=utf-8",
                "Comando de rele avulso bloqueado com o motor acionado.");
    return;
  }

  const String canalTexto  = server.arg("canal");
  const String estadoTexto = server.arg("estado");

  if (estadoTexto != "0" && estadoTexto != "1") {
    server.send(400, "text/plain; charset=utf-8", "Estado invalido. Use 0 ou 1.");
    return;
  }

  const long canal = canalTexto.toInt();
  if (canal < 1 || canal > (long)NUM_RELES || canalTexto != String(canal)) {
    server.send(400, "text/plain; charset=utf-8", "Canal invalido. Use 1, 2, 3 ou 4.");
    return;
  }

  const uint8_t indice = (uint8_t)(canal - 1);
  const bool ligar = (estadoTexto == "1");

  // Nunca deixa estrela e triangulo fechados ao mesmo tempo.
  if (ligar && indice == K_ESTRELA && estadoReles[K_TRIANGULO]) {
    server.send(409, "text/plain; charset=utf-8", "Intertravamento: triangulo esta fechado.");
    return;
  }
  if (ligar && indice == K_TRIANGULO && estadoReles[K_ESTRELA]) {
    server.send(409, "text/plain; charset=utf-8", "Intertravamento: estrela esta fechada.");
    return;
  }

  escreverRele(indice, ligar);
  lcdPrecisaAtualizar = true;
  server.send(200, "text/plain; charset=utf-8", "OK");
}

void tratarNaoEncontrado() {
  cabecalhosComuns();
  server.send(404, "text/plain; charset=utf-8", "Rota nao encontrada.");
}

// -----------------------------------------------------------------------------
// Setup
// -----------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println();
  Serial.println("=== IoTMotor | Modulo 1 (acionamento) ===");

  // Reles: escreve o nivel de repouso ANTES de configurar como saida, para nao
  // dar pulso durante o boot (critico em modulos ativos em nivel baixo).
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
  imprimirLinhaCompleta(0, "IoTMotor Modulo 1");
  imprimirLinhaCompleta(1, "Conectando WiFi...");

  // PZEM - criado aqui, com o core ja inicializado.
  if (PZEM_HABILITADO) {
    pzem = new PZEM004Tv30(Serial2, PZEM_RX_PIN, PZEM_TX_PIN);
  }

  montarTopicos();

  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);
  WiFi.setSleep(false);  // evita latencia alta no servidor web
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
    iniciarMdns();
  } else {
    Serial.println("Wi-Fi nao conectado. O modulo segue operando e tentara reconectar.");
  }

  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(aoReceberMqtt);
  mqttClient.setBufferSize(768);

  server.on("/", HTTP_GET, tratarIndex);
  server.on("/dados", HTTP_GET, tratarDados);
  server.on("/comando", HTTP_GET, tratarComandoWeb);
  server.on("/rele", HTTP_GET, tratarReleWeb);
  server.onNotFound(tratarNaoEncontrado);
  server.begin();
  Serial.println("Servidor HTTP iniciado na porta 80.");

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
  const unsigned long agora = millis();

  server.handleClient();
  manterWifi(agora);
  manterMqtt(agora);
  mqttClient.loop();

  atualizarAcionamento(agora);

  if (agora - ultimaLeituraPzem >= INTERVALO_LEITURA_PZEM) {
    ultimaLeituraPzem = agora;
    lerPzem();
  }

  avaliarProtecoes(agora);

  if (agora - ultimaTelemetriaMs >= INTERVALO_TELEMETRIA_MS) {
    ultimaTelemetriaMs = agora;
    publicarTelemetria(JsonVariantConst(), "");
  }

  if (lcdPrecisaAtualizar || (agora - ultimaAtualizacaoLcd >= INTERVALO_LCD)) {
    ultimaAtualizacaoLcd = agora;
    atualizarLcd();
  }

  delay(2);
}
