#pragma once
// Cadastro de rede Wi-Fi sem cabo.
//
// Se nenhuma rede conhecida responder, a placa cria a propria rede aberta
// (por exemplo "IoTMotor-esp32-01"). Basta conectar o celular nela: abre uma
// pagina onde voce escolhe a rede e digita a senha. A credencial fica gravada
// na memoria da placa (NVS) e passa a ser usada junto com as de wifi_local.h.
//
// A senha nunca passa pelo broker publico, so pela rede da propria placa.
// Mantenha este arquivo identico nas pastas dos dois firmwares.
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiMulti.h>
#include <WiFiManager.h>
#include <Preferences.h>

inline void carregarRedeSalva(WiFiMulti& redes) {
  Preferences memoria;
  if (!memoria.begin("iotmotor-wifi", true)) return;
  const String ssid = memoria.getString("ssid", "");
  const String senha = memoria.getString("pass", "");
  memoria.end();
  if (!ssid.length()) return;
  redes.addAP(ssid.c_str(), senha.c_str());
  Serial.printf("[WiFi] rede cadastrada pelo portal: %s\n", ssid.c_str());
}

inline void salvarRedeAtual() {
  Preferences memoria;
  if (!memoria.begin("iotmotor-wifi", false)) return;
  memoria.putString("ssid", WiFi.SSID());
  memoria.putString("pass", WiFi.psk());
  memoria.end();
  Serial.printf("[WiFi] rede %s gravada na placa\n", WiFi.SSID().c_str());
}

// Abre o portal por "segundos". Retorna true se uma rede nova foi configurada.
inline bool abrirPortalDeRede(const char* nomeDaRede, uint16_t segundos, WiFiMulti& redes) {
  Serial.printf("[WiFi] nenhuma rede conhecida; abrindo portal \"%s\" por %u s\n", nomeDaRede, segundos);
  WiFiManager portal;
  portal.setConfigPortalTimeout(segundos);
  portal.setConfigPortalBlocking(true);
  portal.setTitle("IoTMotor");
  if (!portal.startConfigPortal(nomeDaRede)) {
    Serial.println("[WiFi] portal encerrado sem configuracao");
    return false;
  }
  salvarRedeAtual();
  redes.addAP(WiFi.SSID().c_str(), WiFi.psk().c_str());
  return true;
}
