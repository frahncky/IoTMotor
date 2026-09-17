#pragma once
// Comandos MQTT sem autenticação: ensaios SOMENTE com motor/contatores desconectados.
// boot identifica a sessão atual e é publicado na telemetria; NÃO é uma chave.
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
  Serial.println("[MQTT] Controle sem chave; sessao publicada em telemetria.");
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

void receberComandoMqtt(char* topico, uint8_t* payload, unsigned int tamanho) {
  if (!topico || strcmp(topico, topicoComandos) || !tamanho || tamanho > 700) return;
  StaticJsonDocument<512> doc;
  if (deserializeJson(doc, payload, tamanho) || doc["v"].as<int>() != 1 ||
      strcmp(doc["device_id"] | "", DEVICE_ID)) return;
  const char* seq = doc["seq"] | "";
  uint64_t numero = 0;
  if (!lerSequencia(seq, numero)) return;
  const char* acao = doc["action"] | "";

  // PARAR é prioritário e não depende do boot, da telemetria ou do jumper.
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
  if (!bancadaHabilitada() || etapaPartida || WiFi.status() != WL_CONNECTED) {
    publicarRespostaControle(seq, false, acao, "jumper_or_busy");
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
  int mascara = doc["mask"].as<int>();
  int principal = doc["main"].as<int>();
  int estrela = doc["star"].as<int>();
  int triangulo = doc["delta"].as<int>();
  int segundos = doc["seconds"].as<int>();
  bool direta = !strcmp(modo, "direct") && mascara >= 1 && mascara <= 15 &&
                principal == 0 && estrela == 0 && triangulo == 0 && segundos == 0;
  bool sequencia = !strcmp(modo, "sequence") && mascara == 0 &&
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
