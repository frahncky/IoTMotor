#pragma once
// Atualizacao pela internet (OTA): a placa baixa o firmware publicado pelo CI
// do GitHub e se regrava. Funciona em qualquer rede com saida HTTPS (porta 443),
// inclusive onde as portas MQTT estao bloqueadas.
//
// A URL e FIXA no firmware: o comando MQTT apenas dispara a atualizacao e nao
// escolhe de onde baixar. Como o broker e publico e sem autenticacao, isso
// impede que um terceiro instale outro programa na placa.
//
// Mantenha este arquivo identico nas pastas dos dois firmwares.
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPUpdate.h>
#include <esp_ota_ops.h>
#include "watchdog.h"

// ---- Volta automatica para a versao anterior ------------------------------
// O bootloader ja vem com rollback ligado (CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE),
// mas o core Arduino confirma o programa novo logo no boot, e a volta nunca
// acontecia. Adiando a confirmacao ate a placa falar com o broker, uma versao
// que trava, entra em laco de reinicio ou nao consegue chegar ao MQTT volta
// sozinha para a anterior no proximo boot, sem precisar de cabo. Definida no
// core em C (esp32-hal-misc.c), por isso o extern "C".
extern "C" bool verifyRollbackLater() { return true; }

namespace ota {
inline bool versaoConfirmada = false;

// Chamar quando a placa conectar no broker: Wi-Fi, TLS e MQTT funcionam nesta
// versao, que e o que precisa para receber a proxima atualizacao. Sem OTA
// pendente (gravacao por cabo, ou versao ja confirmada), nao faz nada.
inline void confirmarVersao() {
  if (versaoConfirmada) return;
  versaoConfirmada = true;
  esp_ota_img_states_t estado;
  if (esp_ota_get_state_partition(esp_ota_get_running_partition(), &estado) == ESP_OK &&
      estado == ESP_OTA_IMG_PENDING_VERIFY) {
    esp_ota_mark_app_valid_cancel_rollback();
    Serial.println("[OTA] versao nova confirmada: a volta automatica foi cancelada");
  }
}
}  // namespace ota

// Release fixo "firmware-latest", atualizado pelo workflow publish-firmware.yml.
#define OTA_BASE_URL "https://iotmotor.pages.dev/firmware/"
#define OTA_FALLBACK_URL "https://github.com/frahncky/IoTMotor/releases/download/firmware-latest/"

// Certificados raiz da Mozilla que ja vem compilados no mbedTLS do core ESP32
// (CONFIG_MBEDTLS_CERTIFICATE_BUNDLE_DEFAULT_FULL). Com eles a placa confere
// que fala mesmo com o GitHub (e com o servidor para onde ele redireciona o
// download): numa rede com DNS ou Wi-Fi falso, o download e recusado em vez de
// gravar um programa qualquer. Vale para qualquer autoridade que o GitHub use,
// entao uma troca de certificado do lado dele nao quebra o OTA. A data dos
// certificados nao e conferida (MBEDTLS_HAVE_TIME_DATE desligado), entao a
// placa sem hora do NTP atualiza do mesmo jeito.
extern const uint8_t otaCertificadosRaiz[] asm("_binary_x509_crt_bundle_start");
extern const uint8_t otaCertificadosRaizFim[] asm("_binary_x509_crt_bundle_end");

// Baixa OTA_BASE_URL + arquivo e regrava a placa. Em caso de sucesso reinicia
// e nao retorna. Em caso de falha devolve false e preenche "motivo".
inline bool tentarAtualizacaoUrl(const String& url, String& motivo) {
  WiFiClientSecure tls;
  tls.setCACertBundle(otaCertificadosRaiz, otaCertificadosRaizFim - otaCertificadosRaiz);
  tls.setTimeout(60000);
  HTTPUpdate atualizador(60000);
  atualizador.rebootOnUpdate(true);
  atualizador.setFollowRedirects(HTTPC_FORCE_FOLLOW_REDIRECTS);
  Serial.printf("[OTA] baixando %s\n", url.c_str());
  watchdog::pausar();
  const t_httpUpdate_return resultado = atualizador.update(tls, url);
  watchdog::retomar();
  switch (resultado) {
    case HTTP_UPDATE_OK:
      motivo = "atualizado";
      return true;
    case HTTP_UPDATE_NO_UPDATES:
      motivo = "sem atualizacao disponivel";
      break;
    default:
      motivo = String("falha ") + atualizador.getLastError() + ": " + atualizador.getLastErrorString();
      break;
  }
  Serial.printf("[OTA] %s\n", motivo.c_str());
  return false;
}

inline bool atualizarPelaInternet(const char* arquivo, String& motivo) {
  if (WiFi.status() != WL_CONNECTED) { motivo = "sem Wi-Fi"; return false; }
  // O pedido chegou pelo MQTT, entao esta versao funciona; e o ESP-IDF recusa
  // gravar outra enquanto a atual ainda espera confirmacao.
  ota::confirmarVersao();

  const String principal = String(OTA_BASE_URL) + arquivo;
  if (tentarAtualizacaoUrl(principal, motivo)) return true;

  const String primeiraFalha = motivo;
  const String fallback = String(OTA_FALLBACK_URL) + arquivo;
  if (tentarAtualizacaoUrl(fallback, motivo)) return true;

  motivo = String("proxy: ") + primeiraFalha + " | github: " + motivo;
  return false;
}
