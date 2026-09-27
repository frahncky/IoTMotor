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
#include "watchdog.h"

// Release fixo "firmware-latest", atualizado pelo workflow publish-firmware.yml.
#define OTA_BASE_URL "https://github.com/frahncky/IoTMotor/releases/download/firmware-latest/"

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
inline bool atualizarPelaInternet(const char* arquivo, String& motivo) {
  if (WiFi.status() != WL_CONNECTED) { motivo = "sem Wi-Fi"; return false; }
  WiFiClientSecure tls;
  tls.setCACertBundle(otaCertificadosRaiz, otaCertificadosRaizFim - otaCertificadosRaiz);
  tls.setTimeout(20000);
  httpUpdate.rebootOnUpdate(true);
  httpUpdate.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);  // O GitHub redireciona o download.
  const String url = String(OTA_BASE_URL) + arquivo;
  Serial.printf("[OTA] baixando %s\n", url.c_str());
  watchdog::pausar();  // O download leva minutos; so roda com as saidas paradas.
  const t_httpUpdate_return resultado = httpUpdate.update(tls, url);
  watchdog::retomar();
  switch (resultado) {
    case HTTP_UPDATE_OK:  // Nao deve chegar aqui: rebootOnUpdate reinicia antes.
      motivo = "atualizado";
      return true;
    case HTTP_UPDATE_NO_UPDATES:
      motivo = "sem atualizacao disponivel";
      break;
    default:
      motivo = String("falha ") + httpUpdate.getLastError() + ": " + httpUpdate.getLastErrorString();
      break;
  }
  Serial.printf("[OTA] %s\n", motivo.c_str());
  return false;
}
