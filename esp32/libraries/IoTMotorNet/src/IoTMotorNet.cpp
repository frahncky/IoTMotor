#include "IoTMotorNet.h"

#include <ArduinoOTA.h>
#include <ESPmDNS.h>
#include <HTTPClient.h>
#include <Update.h>
#include <WebServer.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <mbedtls/md.h>

namespace iotmotor {

Rede rede;

namespace {

WebServer servidor(80);

const char *CABECALHO_CHAVE = "X-IoTMotor-OTA-Key";
const char *CABECALHOS_COLETADOS[] = {CABECALHO_CHAVE};

// Pacote de certificados raiz embutido pelo core do ESP32. Cobre os emissores
// publicos, entao a URL de atualizacao pode migrar de host sem recompilar.
extern "C" const uint8_t rootca_crt_bundle_start[] asm("_binary_x509_crt_bundle_start");

String jsonDeErro(const String &mensagem) {
  StaticJsonDocument<256> doc;
  doc["ok"] = false;
  doc["message"] = mensagem;
  String corpo;
  serializeJson(doc, corpo);
  return corpo;
}

void cabecalhosComuns() {
  servidor.sendHeader("Cache-Control", "no-store");
  servidor.sendHeader("Access-Control-Allow-Origin", "*");
}

}  // namespace

// -----------------------------------------------------------------------------
// Versoes
// -----------------------------------------------------------------------------
int Rede::compararVersoes(const String &a, const String &b) {
  int ia = 0, ib = 0;
  while (ia < (int)a.length() || ib < (int)b.length()) {
    long va = 0, vb = 0;
    while (ia < (int)a.length() && a[ia] >= '0' && a[ia] <= '9') {
      va = va * 10 + (a[ia++] - '0');
    }
    while (ib < (int)b.length() && b[ib] >= '0' && b[ib] <= '9') {
      vb = vb * 10 + (b[ib++] - '0');
    }
    if (va != vb) return va < vb ? -1 : 1;
    // Pula o separador de cada lado (ponto, hifen, o que vier).
    if (ia < (int)a.length()) ia++;
    if (ib < (int)b.length()) ib++;
  }
  return 0;
}

// -----------------------------------------------------------------------------
// Autenticacao do upload local
// -----------------------------------------------------------------------------
// Comparacao em tempo constante: um `==` comum vaza o tamanho do prefixo
// correto pelo tempo de resposta.
bool Rede::chaveConfere() const {
  const size_t esperado = strlen(cfg_.chaveOta);
  if (esperado < 8) return false;

  const String recebida = servidor.header(CABECALHO_CHAVE);
  if (recebida.length() != esperado) return false;

  uint8_t diferencas = 0;
  for (size_t i = 0; i < esperado; i++) {
    diferencas |= (uint8_t)(recebida[i] ^ cfg_.chaveOta[i]);
  }
  return diferencas == 0;
}

void Rede::relatar(const char *status) {
  if (relator_) relator_(status);
  Serial.print("[ota] ");
  Serial.println(status);
}

// -----------------------------------------------------------------------------
// Rotas HTTP
// -----------------------------------------------------------------------------
void Rede::trataHealth() {
  StaticJsonDocument<768> doc;
  doc["ok"] = true;
  doc["device_id"] = cfg_.deviceId;
  doc["firmware_version"] = cfg_.versaoFirmware;
  doc["uptime_s"] = millis() / 1000;
  doc["free_heap"] = ESP.getFreeHeap();
  doc["sketch_size"] = ESP.getSketchSize();
  doc["free_sketch_space"] = ESP.getFreeSketchSpace();
  doc["wifi_connected"] = WiFi.status() == WL_CONNECTED;
  doc["rssi"] = WiFi.RSSI();
  doc["ip"] = WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString()
                                            : WiFi.softAPIP().toString();
  doc["fallback_ap"] = apAtivo_;
  doc["updating"] = atualizando_;
  doc["ota_local_enabled"] = strlen(cfg_.chaveOta) >= 8;
  doc["ota_url_prefix"] = cfg_.prefixoUrlOta;

  if (estado_) {
    JsonObject modulo = doc.createNestedObject("module");
    estado_(modulo);
  }

  String corpo;
  serializeJson(doc, corpo);
  cabecalhosComuns();
  servidor.send(200, "application/json", corpo);
}

void Rede::trataRedesWifi() {
  // Varredura sincrona: bloqueia por alguns segundos, mas so acontece quando
  // alguem pede pela rede local, nunca no caminho normal do loop.
  const int achadas = WiFi.scanNetworks();

  StaticJsonDocument<2048> doc;
  doc["ok"] = true;
  JsonArray redes = doc.createNestedArray("networks");
  for (int i = 0; i < achadas && i < 20; i++) {
    JsonObject r = redes.createNestedObject();
    r["ssid"] = WiFi.SSID(i);
    r["rssi"] = WiFi.RSSI(i);
    r["secure"] = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
  }
  WiFi.scanDelete();

  String corpo;
  serializeJson(doc, corpo);
  cabecalhosComuns();
  servidor.send(200, "application/json", corpo);
}

// Resposta do upload: roda depois que todos os blocos chegaram.
void Rede::trataUploadFinal() {
  cabecalhosComuns();

  if (erroUpload_.length() > 0) {
    atualizando_ = false;
    servidor.send(500, "application/json", jsonDeErro(erroUpload_));
    relatar("ota_local_failed");
    return;
  }

  servidor.send(200, "application/json",
                "{\"ok\":true,\"message\":\"Firmware gravado. Reiniciando.\"}");
  relatar("ota_local_applied");
  delay(400);
  ESP.restart();
}

// Recebe o firmware em blocos, direto para a particao ociosa.
void Rede::trataUploadBloco() {
  HTTPUpload &upload = servidor.upload();

  if (upload.status == UPLOAD_FILE_START) {
    erroUpload_ = "";

    if (!chaveConfere()) {
      erroUpload_ = "Chave de atualizacao invalida.";
      return;
    }

    String motivo;
    if (veto_ && !veto_(motivo)) {
      erroUpload_ = motivo.length() ? motivo : "Atualizacao recusada pelo modulo.";
      return;
    }

    atualizando_ = true;
    relatar("ota_local_started");

    if (!Update.begin(UPDATE_SIZE_UNKNOWN, U_FLASH)) {
      erroUpload_ = String("Update.begin: ") + Update.errorString();
      atualizando_ = false;
    }
    return;
  }

  // Um erro num bloco anterior aborta o restante sem tentar gravar.
  if (erroUpload_.length() > 0) return;

  if (upload.status == UPLOAD_FILE_WRITE) {
    if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
      erroUpload_ = String("Update.write: ") + Update.errorString();
      Update.abort();
      atualizando_ = false;
    }
    return;
  }

  if (upload.status == UPLOAD_FILE_END) {
    if (!Update.end(true)) {
      erroUpload_ = String("Update.end: ") + Update.errorString();
      atualizando_ = false;
    }
    return;
  }

  if (upload.status == UPLOAD_FILE_ABORTED) {
    if (Update.isRunning()) Update.abort();
    erroUpload_ = "Upload interrompido.";
    atualizando_ = false;
  }
}

void Rede::trataNaoEncontrado() {
  cabecalhosComuns();
  servidor.send(404, "application/json", jsonDeErro("Rota nao encontrada."));
}

void Rede::registrarRotas() {
  servidor.collectHeaders(CABECALHOS_COLETADOS, 1);
  servidor.on("/health", HTTP_GET, []() { rede.trataHealth(); });
  servidor.on("/wifi-networks", HTTP_GET, []() { rede.trataRedesWifi(); });
  servidor.on("/firmware/update", HTTP_POST,
              []() { rede.trataUploadFinal(); },
              []() { rede.trataUploadBloco(); });
  servidor.onNotFound([]() { rede.trataNaoEncontrado(); });
  servidor.begin();
}

// -----------------------------------------------------------------------------
// ArduinoOTA (push pela IDE)
// -----------------------------------------------------------------------------
void Rede::iniciarArduinoOta() {
  if (strlen(cfg_.chaveOta) < 8) {
    Serial.println("[ota] ArduinoOTA desligado: defina uma chave de 8+ caracteres.");
    return;
  }

  ArduinoOTA.setHostname(cfg_.deviceId);
  ArduinoOTA.setPassword(cfg_.chaveOta);

  ArduinoOTA.onStart([]() {
    String motivo;
    // O veto nao consegue cancelar o ArduinoOTA depois que ele comeca; o que
    // da para fazer e registrar, para o motivo aparecer no log da bancada.
    if (rede.veto_ && !rede.veto_(motivo)) {
      Serial.print("[ota] ATENCAO: modulo pediu para recusar (");
      Serial.print(motivo);
      Serial.println("), mas o ArduinoOTA ja iniciou.");
    }
    rede.atualizando_ = true;
    rede.relatar("ota_push_started");
  });
  ArduinoOTA.onEnd([]() { rede.relatar("ota_push_applied"); });
  ArduinoOTA.onError([](ota_error_t) {
    rede.atualizando_ = false;
    rede.relatar("ota_push_failed");
  });

  ArduinoOTA.begin();
  arduinoOtaAtivo_ = true;
}

// -----------------------------------------------------------------------------
// Ponto de acesso de emergencia
// -----------------------------------------------------------------------------
void Rede::manterApDeFallback(bool wifiConectado, unsigned long agora) {
  if (cfg_.atrasoApFallbackMs == 0) return;

  if (wifiConectado) {
    semWifiDesde_ = 0;
    if (apAtivo_) {
      WiFi.softAPdisconnect(true);
      WiFi.mode(WIFI_STA);
      apAtivo_ = false;
      Serial.println("[rede] Wi-Fi voltou. Ponto de acesso de emergencia desligado.");
    }
    return;
  }

  if (semWifiDesde_ == 0) {
    semWifiDesde_ = agora;
    return;
  }

  if (!apAtivo_ && (agora - semWifiDesde_) >= cfg_.atrasoApFallbackMs) {
    // WIFI_AP_STA mantem a estacao tentando reconectar enquanto o AP esta no ar.
    WiFi.mode(WIFI_AP_STA);
    if (WiFi.softAP(cfg_.apSsid, cfg_.apSenha)) {
      apAtivo_ = true;
      Serial.print("[rede] Ponto de acesso de emergencia no ar: ");
      Serial.print(cfg_.apSsid);
      Serial.print(" — http://");
      Serial.println(WiFi.softAPIP());
    }
  }
}

// -----------------------------------------------------------------------------
// Atualizacao remota
// -----------------------------------------------------------------------------
bool Rede::atualizarDeUrl(const String &url, const String &versao, String &erro) {
  if (atualizando_) {
    erro = "Ja existe uma atualizacao em andamento.";
    return false;
  }

  // 1. O modulo pode vetar (motor acionado, por exemplo).
  String motivo;
  if (veto_ && !veto_(motivo)) {
    erro = motivo.length() ? motivo : "Atualizacao recusada pelo modulo.";
    relatar("ota_refused");
    return false;
  }

  // 2. Prefixo fixado em tempo de compilacao. Esta e a defesa que impede um
  //    comando vindo de fora de apontar para um firmware qualquer.
  const size_t tamPrefixo = strlen(cfg_.prefixoUrlOta);
  if (tamPrefixo == 0) {
    erro = "Atualizacao remota desligada: prefixo de URL nao configurado.";
    return false;
  }
  if (!url.startsWith(cfg_.prefixoUrlOta)) {
    erro = "URL fora do prefixo permitido.";
    relatar("ota_refused_url");
    return false;
  }
  if (!url.startsWith("https://")) {
    erro = "A atualizacao remota exige https.";
    relatar("ota_refused_url");
    return false;
  }

  // 3. Nao aceita versao igual ou anterior, para fechar o downgrade.
  if (versao.length() > 0 &&
      compararVersoes(versao, cfg_.versaoFirmware) <= 0) {
    erro = "Versao " + versao + " nao e posterior a " + String(cfg_.versaoFirmware) + ".";
    relatar("ota_refused_version");
    return false;
  }

  atualizando_ = true;
  relatar("ota_remote_started");

  WiFiClientSecure cliente;
  cliente.setCACertBundle(rootca_crt_bundle_start);
  cliente.setTimeout(15000);

  HTTPClient http;
  http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);
  http.setTimeout(20000);

  if (!http.begin(cliente, url)) {
    erro = "Nao foi possivel abrir a conexao.";
    atualizando_ = false;
    relatar("ota_remote_failed");
    return false;
  }

  const int codigo = http.GET();
  if (codigo != HTTP_CODE_OK) {
    erro = "HTTP " + String(codigo);
    http.end();
    atualizando_ = false;
    relatar("ota_remote_failed");
    return false;
  }

  const int tamanho = http.getSize();
  if (tamanho <= 0) {
    erro = "Servidor nao informou o tamanho do firmware.";
    http.end();
    atualizando_ = false;
    relatar("ota_remote_failed");
    return false;
  }
  if (!Update.begin((size_t)tamanho, U_FLASH)) {
    erro = String("Update.begin: ") + Update.errorString();
    http.end();
    atualizando_ = false;
    relatar("ota_remote_failed");
    return false;
  }

  // Grava em blocos e calcula o SHA-256 no caminho, para nao precisar reler a
  // particao depois.
  mbedtls_md_context_t ctx;
  mbedtls_md_init(&ctx);
  mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), 0);
  mbedtls_md_starts(&ctx);

  WiFiClient *fluxo = http.getStreamPtr();
  uint8_t buffer[1024];
  int restante = tamanho;
  bool falhou = false;

  while (http.connected() && restante > 0) {
    const size_t disponivel = fluxo->available();
    if (disponivel == 0) {
      delay(1);
      continue;
    }

    const int lidos = fluxo->readBytes(
        buffer, disponivel > sizeof(buffer) ? sizeof(buffer) : disponivel);
    if (lidos <= 0) continue;

    if (Update.write(buffer, lidos) != (size_t)lidos) {
      erro = String("Update.write: ") + Update.errorString();
      falhou = true;
      break;
    }
    mbedtls_md_update(&ctx, buffer, lidos);
    restante -= lidos;
  }

  uint8_t resumo[32];
  mbedtls_md_finish(&ctx, resumo);
  mbedtls_md_free(&ctx);
  http.end();

  if (!falhou && restante > 0) {
    erro = "Download interrompido antes do fim.";
    falhou = true;
  }

  if (falhou) {
    Update.abort();
    atualizando_ = false;
    relatar("ota_remote_failed");
    return false;
  }

  if (!Update.end(true)) {
    erro = String("Update.end: ") + Update.errorString();
    atualizando_ = false;
    relatar("ota_remote_failed");
    return false;
  }

  char hexResumo[65];
  for (int i = 0; i < 32; i++) snprintf(hexResumo + i * 2, 3, "%02x", resumo[i]);
  Serial.print("[ota] sha256 da imagem gravada: ");
  Serial.println(hexResumo);

  relatar("ota_remote_applied");
  delay(400);
  ESP.restart();
  return true;  // inalcancavel
}

// -----------------------------------------------------------------------------
// Ciclo de vida
// -----------------------------------------------------------------------------
void Rede::begin(const Config &config) {
  cfg_ = config;

  if (cfg_.portaHttp != 80) {
    // O WebServer ja foi construido na porta 80; avisa em vez de mentir.
    Serial.println("[rede] portaHttp diferente de 80 nao e suportada; usando 80.");
  }

  registrarRotas();
  iniciarArduinoOta();

  if (MDNS.begin(cfg_.deviceId)) {
    MDNS.addService("http", "tcp", 80);
    Serial.print("[rede] mDNS: http://");
    Serial.print(cfg_.deviceId);
    Serial.println(".local/health");
  }

  iniciado_ = true;
  Serial.print("[rede] Servico local ativo. Firmware ");
  Serial.println(cfg_.versaoFirmware);
}

void Rede::loop(bool wifiConectado) {
  if (!iniciado_) return;

  servidor.handleClient();
  if (arduinoOtaAtivo_) ArduinoOTA.handle();
  manterApDeFallback(wifiConectado, millis());
}

}  // namespace iotmotor
