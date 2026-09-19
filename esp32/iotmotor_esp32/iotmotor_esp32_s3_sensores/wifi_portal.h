#pragma once
// Portal de primeiro cadastro de rede, sem cabo.
//
// So e usado quando nenhuma rede da lista (wifi_store.h) responde: nesse caso
// o painel nao alcanca a placa, entao ela cria a propria rede aberta (por
// exemplo "IoTMotor-esp32-01"). No celular, conecte nela e informe o Wi-Fi.
// A rede entra no topo da lista gravada; o resto da lista e gerenciado pela
// aba "Wi-Fi" do painel.
//
// Mantenha este arquivo identico nas pastas dos dois firmwares.
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiManager.h>
#include "wifi_store.h"

// Abre o portal por "segundos". Retorna true se uma rede foi cadastrada.
inline bool abrirPortalDeRede(const char* nomeDaRede, uint16_t segundos) {
  Serial.printf("[WiFi] nenhuma rede da lista respondeu; abrindo portal \"%s\" por %u s\n",
                nomeDaRede, segundos);
  WiFiManager portal;
  portal.setConfigPortalTimeout(segundos);
  portal.setConfigPortalBlocking(true);
  portal.setTitle("IoTMotor");
  portal.setBreakAfterConfig(true);
  if (!portal.startConfigPortal(nomeDaRede)) {
    Serial.println("[WiFi] portal encerrado sem configuracao");
    return false;
  }
  // Mesmo se a nova rede ainda nao conectou, ela entra no topo da lista.
  const bool ok = wifistore::adicionar(WiFi.SSID().c_str(), WiFi.psk().c_str(), 0);
  Serial.printf("[WiFi] rede %s %s na lista da placa\n", WiFi.SSID().c_str(),
                ok ? "gravada" : "NAO gravada (lista cheia?)");
  return ok;
}
