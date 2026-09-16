/* ============================================================
 * IoTMotorNet — acesso local e atualizacao de firmware
 *
 * Compartilhado pelos dois modulos do IoTMotor. Reune:
 *
 *   - servidor HTTP local (diagnostico e upload de firmware), no mesmo
 *     desenho do firmware do E-Metrics IoT: rotas JSON protegidas por uma
 *     chave enviada em cabecalho, comparada em tempo constante;
 *   - ArduinoOTA, para push direto da IDE pela rede local;
 *   - ponto de acesso de emergencia quando o Wi-Fi da planta nao volta;
 *   - atualizacao remota puxada por HTTPS de uma URL cujo prefixo e fixado
 *     em tempo de compilacao.
 *
 * O prefixo fixado e a defesa central: mesmo que alguem consiga disparar uma
 * atualizacao (por exemplo publicando num broker sem autenticacao), so
 * consegue apontar para o seu proprio endereco de releases. Nao vira execucao
 * de codigo arbitrario, no maximo uma reinstalacao — e o bloqueio de versao
 * anterior fecha o caminho do downgrade.
 *
 * IFMA - Projeto PIBITI
 * ============================================================ */

#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFiClientSecure.h>

namespace iotmotor {

/// Preenche o objeto JSON de /health com o estado especifico do modulo.
typedef void (*ProvedorDeEstado)(JsonObject);

/// Veta uma atualizacao. Devolve false e preenche o motivo para recusar.
/// O Modulo 1 usa isto para nao atualizar com o motor acionado.
typedef bool (*VetoDeAtualizacao)(String &motivo);

/// Reporta o andamento para fora (tipicamente publicando em MQTT).
typedef void (*RelatorDeStatus)(const char *status);

/// Credenciais de rede e broker, guardadas em NVS.
///
/// Os valores compilados no sketch sao apenas o padrao de fabrica: se houver
/// provisionamento gravado, ele vence. Isso permite levar a placa para outra
/// planta sem recompilar.
struct Credenciais {
  String wifiSsid;
  String wifiSenha;
  String mqttHost;
  uint16_t mqttPorta = 1883;
  String mqttUsuario;
  String mqttSenha;
  String prefixoTopicos;
  bool mqttTls = false;

  /// true quando os valores vieram da NVS, nao dos padroes de compilacao.
  bool provisionado = false;
};

struct Config {
  /// device_id do modulo (esp32-01, esp32-02). Tambem vira hostname do mDNS.
  const char *deviceId = "esp32";

  /// Versao deste firmware, em x.y.z. Usada para recusar versao anterior.
  const char *versaoFirmware = "0.0.0";

  /// Prefixo obrigatorio das URLs de atualizacao remota. Uma URL que nao
  /// comece exatamente com isto e recusada antes de qualquer download.
  const char *prefixoUrlOta = "";

  /// Chave exigida no cabecalho X-IoTMotor-OTA-Key para o upload local e
  /// usada tambem como senha do ArduinoOTA. Minimo de 8 caracteres; com
  /// menos que isso o upload local e o ArduinoOTA ficam desligados.
  const char *chaveOta = "";

  /// Ponto de acesso de emergencia, levantado quando o Wi-Fi nao volta.
  const char *apSsid = "IoTMotor-Setup";
  const char *apSenha = "12345678";

  /// Tempo sem Wi-Fi antes de levantar o ponto de acesso. Zero desliga.
  unsigned long atrasoApFallbackMs = 90000UL;

  /// Porta do servidor HTTP local.
  uint16_t portaHttp = 80;
};

/// Instala o pacote de certificados raiz do core neste cliente TLS.
/// Use para o broker MQTT quando o provisionamento pedir TLS — o pacote ja
/// esta embutido por causa da atualizacao remota, entao nao custa flash extra.
void aplicarRaizesTls(WiFiClientSecure &cliente);

class Rede {
 public:
  void begin(const Config &config);

  /// Chame a cada iteracao do loop(). `wifiConectado` evita que a biblioteca
  /// consulte o estado do radio por conta propria.
  void loop(bool wifiConectado);

  void aoConsultarEstado(ProvedorDeEstado f) { estado_ = f; }
  void aoVetarAtualizacao(VetoDeAtualizacao f) { veto_ = f; }
  void aoRelatarStatus(RelatorDeStatus f) { relator_ = f; }

  /// Baixa e aplica um firmware. Devolve false e preenche `erro` quando
  /// recusa ou falha; em caso de sucesso reinicia e nao retorna.
  bool atualizarDeUrl(const String &url, const String &versao, String &erro);

  /// true enquanto uma atualizacao esta em andamento (local ou remota).
  bool atualizando() const { return atualizando_; }

  /// true quando o ponto de acesso de emergencia esta no ar.
  bool apDeFallbackAtivo() const { return apAtivo_; }

  const Config &config() const { return cfg_; }

  /// Le as credenciais gravadas, caindo nos padroes quando nao ha nada.
  /// Chame ANTES de begin(): o resultado precisa viver enquanto o programa
  /// rodar, porque o PubSubClient guarda o ponteiro do host.
  Credenciais carregarCredenciais(const Credenciais &padroes);

  /// Credenciais em uso, para o modulo consultar depois de carregar.
  const Credenciais &credenciais() const { return creds_; }

  /// Compara versoes x.y.z. <0, 0 ou >0, como strcmp.
  static int compararVersoes(const String &a, const String &b);

 private:
  void registrarRotas();
  void iniciarArduinoOta();
  void manterApDeFallback(bool wifiConectado, unsigned long agora);
  bool chaveConfere() const;
  void relatar(const char *status);

  void trataHealth();
  void trataRedesWifi();
  void trataProvisionamentoLer();
  void trataProvisionamentoGravar();
  void trataProvisionamentoLimpar();
  void trataUploadFinal();
  void trataUploadBloco();
  void trataNaoEncontrado();

  Config cfg_;
  ProvedorDeEstado estado_ = nullptr;
  VetoDeAtualizacao veto_ = nullptr;
  RelatorDeStatus relator_ = nullptr;

  bool iniciado_ = false;
  bool atualizando_ = false;
  bool apAtivo_ = false;
  bool arduinoOtaAtivo_ = false;
  unsigned long semWifiDesde_ = 0;
  String erroUpload_;
  Credenciais creds_;
  String chaveGravada_;
};

/// Instancia unica: o WebServer e o ArduinoOTA ja sao recursos unicos do chip.
extern Rede rede;

}  // namespace iotmotor
