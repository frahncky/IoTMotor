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

// Release fixo "firmware-latest", atualizado pelo workflow publish-firmware.yml.
#define OTA_BASE_URL "https://github.com/frahncky/IoTMotor/releases/download/firmware-latest/"

// Baixa OTA_BASE_URL + arquivo e regrava a placa. Em caso de sucesso reinicia
// e nao retorna. Em caso de falha devolve false e preenche "motivo".
inline bool atualizarPelaInternet(const char* arquivo, String& motivo) {
  if (WiFi.status() != WL_CONNECTED) { motivo = "sem Wi-Fi"; return false; }
  WiFiClientSecure tls;
  tls.setInsecure();  // Sem raiz fixada: o release do GitHub e publico e assinado por HTTPS.
  tls.setTimeout(20000);
  httpUpdate.rebootOnUpdate(true);
  httpUpdate.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);  // O GitHub redireciona o download.
  const String url = String(OTA_BASE_URL) + arquivo;
  Serial.printf("[OTA] baixando %s\n", url.c_str());
  const t_httpUpdate_return resultado = httpUpdate.update(tls, url);
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
