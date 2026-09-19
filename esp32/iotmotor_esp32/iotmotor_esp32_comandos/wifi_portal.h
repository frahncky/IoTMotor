#pragma once
// Rede propria da placa (ponto de acesso) com o portal de cadastro.
//
// Abre sozinha quando nenhuma rede da lista (wifi_store.h) responde, e tambem
// sob demanda pelo botao "Abrir rede da placa" da aba "Wi-Fi" do painel.
// Nome e senha dessa rede sao definidos na mesma aba (padrao: IoTMotor-<id>,
// aberta). No celular, conecte nela e informe o Wi-Fi; a rede escolhida entra
// no topo da lista gravada.
//
// Mantenha este arquivo identico nas pastas dos dois firmwares.
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiManager.h>
#include "wifi_store.h"

// Abre a rede propria por "segundos". Retorna true se uma rede foi cadastrada.
inline bool abrirPortalDeRede(uint16_t segundos) {
  const bool comSenha = *wifistore::apSenha;
  Serial.printf("[WiFi] abrindo a rede da placa \"%s\" (%s) por %u s\n", wifistore::apNome,
                comSenha ? "com senha" : "aberta", segundos);
  WiFiManager portal;
  portal.setConfigPortalTimeout(segundos);
  portal.setConfigPortalBlocking(true);
  portal.setTitle("IoTMotor");
  portal.setBreakAfterConfig(true);
  if (!portal.startConfigPortal(wifistore::apNome, comSenha ? wifistore::apSenha : nullptr)) {
    Serial.println("[WiFi] rede da placa encerrada sem cadastro");
    return false;
  }
  // Mesmo se a nova rede ainda nao conectou, ela entra no topo da lista.
  const bool ok = wifistore::adicionar(WiFi.SSID().c_str(), WiFi.psk().c_str(), 0);
  Serial.printf("[WiFi] rede %s %s na lista da placa\n", WiFi.SSID().c_str(),
                ok ? "gravada" : "NAO gravada (lista cheia?)");
  return ok;
}
