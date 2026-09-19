#pragma once
// Comandos MQTT sem autenticacao para ensaios com motor/contatores desconectados.
// O identificador de boot evita aceitar comandos antigos, mas NAO e uma chave.
#include <esp_system.h>
#include <stdlib.h>

bool controleMqttConfigurado = true;
char sessaoControle[17] = {0};
uint64_t ultimaSequenciaControle = 0;

void iniciarControleMqtt() {
  static const char hex[] = "0123456789abcdef";
  uint8_t bytes[8];
  esp_fill_random(bytes, sizeof(bytes));
  for (int i = 0; i < 8; ++i) {
    sessaoControle[i * 2] = hex[bytes[i] >> 4];
    sessaoControle[i * 2 + 1] = hex[bytes[i] & 15];
  }
  sessaoControle[16] = '\0';
  Serial.println("[MQTT] Controle sem chave e sem jumper; boot publicado na telemetria.");
}

bool lerSequencia(const char* s, uint64_t& n) {
  if (!s || !s[0] || strlen(s) > 18 || s[0] == '0') return false;
  for (size_t i = 0; s[i]; ++i) if (s[i] < '0' || s[i] > '9') return false;
  char* fim = nullptr;
  unsigned long long v = strtoull(s, &fim, 10);
  if (!fim || *fim || !v) return false;
  n = static_cast<uint64_t>(v);
  return true;
}

void publicarRespostaControle(const char* seq, bool aceito, const char* acao, const char* motivo) {
  if (!mqttClient.connected()) return;
  StaticJsonDocument<256> resposta;
  resposta["device_id"] = DEVICE_ID;
  resposta["seq"] = seq;
  resposta["accepted"] = aceito;
  resposta["action"] = acao;
  resposta["reason"] = motivo;
  resposta["phase"] = nomeEtapa();
  char payload[256];
  size_t len = serializeJson(resposta, payload, sizeof(payload));
  if (len) mqttClient.publish(topicoResposta, reinterpret_cast<const uint8_t*>(payload),
                              static_cast<unsigned int>(len), false);
}

// Lista de redes gravada na placa, sem senhas, com a chave publica para o
// painel cifrar senhas novas. Retida para a aba "Wi-Fi" abrir ja preenchida.
void publicarRedes() {
  if (!mqttClient.connected()) return;
  StaticJsonDocument<1024> doc;
  doc["device_id"] = DEVICE_ID;
  wifistore::descrever(doc);
  char payload[1024];
  const size_t len = serializeJson(doc, payload, sizeof(payload));
  if (len) mqttClient.publish(topicoWifi, reinterpret_cast<const uint8_t*>(payload),
                              static_cast<unsigned int>(len), true);
}

void receberComandoMqtt(char* topico, uint8_t* payload, unsigned int tamanho) {
  if (!topico || strcmp(topico, topicoComandos) || !tamanho || tamanho > 700) return;
  StaticJsonDocument<512> doc;
  if (deserializeJson(doc, payload, tamanho) || doc["v"].as<int>() != 1 ||
      strcmp(doc["device_id"] | "", DEVICE_ID)) return;
  const char* seq = doc["seq"] | "";
  uint64_t numero = 0;
  if (!lerSequencia(seq, numero)) return;
  const char* acao = doc["action"] | "";

  // Lista de redes (aba "Wi-Fi" do painel). A senha chega cifrada para a
  // chave desta placa; o broker publico nunca ve a senha em texto aberto.
  const char* motivoWifi = "";
  const wifistore::Resultado resultadoWifi =
      wifistore::tratarComando(acao, doc.as<JsonVariantConst>(), motivoWifi);
  if (resultadoWifi != wifistore::Resultado::NaoEWifi) {
    publicarRespostaControle(seq, resultadoWifi == wifistore::Resultado::Aceito, acao, motivoWifi);
    publicarRedes();
    return;
  }

  // Abre o portal de cadastro de rede na propria placa (ultimo recurso).
  if (!strcmp(acao, "wifi_portal")) {
    for (uint8_t i = 0; i < NUM_RELES; ++i) if (estadoReles[i] || etapaPartida) {
      publicarRespostaControle(seq, false, acao, "saidas ligadas: pare antes de configurar");
      return;
    }
    publicarRespostaControle(seq, true, acao, "rede da placa aberta por 180 s");
    delay(200);  // Tempo de a resposta sair antes de o Wi-Fi virar ponto de acesso.
    abrirPortalDeRede(PORTAL_SEGUNDOS);
    ESP.restart();  // Volta ao funcionamento normal ja com a rede nova.
    return;
  }

  // Atualizacao pela internet: URL fixa no firmware, nunca vinda da mensagem.
  if (!strcmp(acao, "update")) {
    for (uint8_t i = 0; i < NUM_RELES; ++i) if (estadoReles[i] || etapaPartida) {
      publicarRespostaControle(seq, false, acao, "saidas ligadas: pare antes de atualizar");
      return;
    }
    publicarRespostaControle(seq, true, acao, "baixando firmware");
    String motivo;
    atualizarPelaInternet(OTA_ARQUIVO, motivo);  // Sucesso reinicia a placa.
    publicarRespostaControle(seq, false, acao, motivo.c_str());
    return;
  }

  // Parar sempre: nao depende de telemetria, boot, estado ou partida pendente.
  if (!strcmp(acao, "stop")) {
    pararBancada();
    publicarRespostaControle(seq, true, acao, "stopped");
    return;
  }
  if (strcmp(acao, "start")) {
    publicarRespostaControle(seq, false, acao, "unknown_action");
    return;
  }
  if (strcmp(doc["boot"] | "", sessaoControle)) {
    publicarRespostaControle(seq, false, acao, "session_mismatch");
    return;
  }
  if (numero <= ultimaSequenciaControle) {
    publicarRespostaControle(seq, false, acao, "duplicate");
    return;
  }
  ultimaSequenciaControle = numero;
  if (etapaPartida || WiFi.status() != WL_CONNECTED) {
    publicarRespostaControle(seq, false, acao, "busy_or_offline");
    return;
  }
  for (uint8_t i = 0; i < NUM_RELES; ++i) if (estadoReles[i]) {
    publicarRespostaControle(seq, false, acao, "already_on");
    return;
  }
  if (!doc["mask"].is<int>() || !doc["main"].is<int>() || !doc["star"].is<int>() ||
      !doc["delta"].is<int>() || !doc["seconds"].is<int>()) {
    publicarRespostaControle(seq, false, acao, "invalid_profile");
    return;
  }
  const char* modo = doc["mode"] | "";
  const int mascara = doc["mask"].as<int>();
  const int principal = doc["main"].as<int>();
  const int estrela = doc["star"].as<int>();
  const int triangulo = doc["delta"].as<int>();
  const int segundos = doc["seconds"].as<int>();
  const bool direta = !strcmp(modo, "direct") && mascara >= 1 && mascara <= 15 &&
                      principal == 0 && estrela == 0 && triangulo == 0 && segundos == 0;
  const bool sequencia = !strcmp(modo, "sequence") && mascara == 0 &&
                         principal >= 1 && principal <= 4 && estrela >= 1 && estrela <= 4 &&
                         triangulo >= 1 && triangulo <= 4 && principal != estrela &&
                         principal != triangulo && estrela != triangulo && segundos >= 2 && segundos <= 30;
  if (!direta && !sequencia) {
    publicarRespostaControle(seq, false, acao, "invalid_profile");
    return;
  }
  aplicarMascaraReles(0);
  modoPartida = sequencia ? 1 : 0;
  mascaraDireta = static_cast<uint8_t>(mascara);
  if (sequencia) {
    indicePrincipal = principal - 1;
    indiceEstrela = estrela - 1;
    indiceTriangulo = triangulo - 1;
    tempoEstrelaMs = static_cast<unsigned long>(segundos) * 1000UL;
  }
  momentoPartida = millis();
  momentoEtapa = momentoPartida;
  etapaPartida = 1;
  publicarRespostaControle(seq, true, acao, "accepted");
}
