#pragma once
// MQTT remoto SOMENTE para ensaios com motor e contatores desconectados.
// Chave aleatoria por placa no NVS: NUNCA a publique no GitHub ou na telemetria.
// A assinatura autentica quem envia; o broker de testes continua publico.
#include <Preferences.h>
#include <esp_system.h>
#include <mbedtls/md.h>
#include <stdlib.h>

uint8_t chaveControle[16] = {0};
bool controleMqttConfigurado = false;
char sessaoControle[17] = {0};
uint64_t ultimaSequenciaControle = 0;

int nibbleHex(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}
bool decodificarHex(const char* texto, uint8_t* bytes, size_t quantidade) {
  if (!texto || strlen(texto) != quantidade * 2) return false;
  for (size_t i = 0; i < quantidade; ++i) {
    int hi = nibbleHex(texto[2*i]), lo = nibbleHex(texto[2*i+1]);
    if (hi < 0 || lo < 0) return false;
    bytes[i] = static_cast<uint8_t>((hi << 4) | lo);
  }
  return true;
}
String converterHex(const uint8_t* bytes, size_t quantidade) {
  static const char letras[] = "0123456789abcdef";
  String resultado;
  resultado.reserve(quantidade * 2);
  for (size_t i = 0; i < quantidade; ++i) {
    resultado += letras[bytes[i] >> 4];
    resultado += letras[bytes[i] & 15];
  }
  return resultado;
}
void iniciarControleMqtt() {
  // Uma sessao aleatoria nova em todo boot invalida comandos da sessao anterior.
  uint8_t aleatorio[8];
  esp_fill_random(aleatorio, sizeof(aleatorio));
  String boot = converterHex(aleatorio, sizeof(aleatorio));
  boot.toCharArray(sessaoControle, sizeof(sessaoControle));
  Preferences preferencias;
  if (!preferencias.begin("iotmotor", false)) {
    Serial.println("[MQTT] NVS indisponivel: controle remoto DESATIVADO");
    return;
  }
  String segredo = preferencias.getString("cmd_key", "");
  if (!decodificarHex(segredo.c_str(), chaveControle, sizeof(chaveControle))) {
    uint8_t novoSegredo[sizeof(chaveControle)];
    esp_fill_random(novoSegredo, sizeof(novoSegredo));
    segredo = converterHex(novoSegredo, sizeof(novoSegredo));
    if (preferencias.putString("cmd_key", segredo) != segredo.length()) {
      preferencias.end();
      Serial.println("[MQTT] Nao foi possivel salvar chave: controle remoto DESATIVADO");
      return;
    }
    memcpy(chaveControle, novoSegredo, sizeof(chaveControle));
  }
  preferencias.end();
  controleMqttConfigurado = true;
  Serial.println("[MQTT] Chave de comandos (copie apenas do Monitor Serial; nao divulgue):");
  Serial.println(segredo);
  Serial.println("[MQTT] A chave e persistente; o nonce muda em cada reinicializacao.");
}

bool lerSequencia(const char* texto, uint64_t& numero) {
  if (!texto) return false;
  const size_t n = strlen(texto);
  if (n < 13 || n > 18 || texto[0] == '0') return false;
  for (size_t i = 0; i < n; ++i) if (texto[i] < '0' || texto[i] > '9') return false;
  char* fim = nullptr;
  unsigned long long valor = strtoull(texto, &fim, 10);
  if (!fim || *fim || valor == 0) return false;
  numero = static_cast<uint64_t>(valor);
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
  if (len > 0) mqttClient.publish(topicoResposta, reinterpret_cast<const uint8_t*>(payload),
                                  static_cast<unsigned int>(len), false);
}

// Formato assinado: todos os campos tem uma ordem canonica fixa. Nao inclui JSON em si.
// iotmotor-v1|device|boot|seq|action|mode|mask|main|star|delta|seconds
bool assinaturaControleValida(const char* seq, const char* acao, const char* modo,
                              int mask, int principal, int estrela, int triangulo,
                              int segundos, const char* assinatura) {
  uint8_t fornecida[32];
  if (!decodificarHex(assinatura, fornecida, sizeof(fornecida))) return false;
  char mensagem[256];
  int tamanho = snprintf(mensagem, sizeof(mensagem),
    "iotmotor-v1|%s|%s|%s|%s|%s|%d|%d|%d|%d|%d",
    DEVICE_ID, sessaoControle, seq, acao, modo, mask, principal, estrela, triangulo, segundos);
  if (tamanho <= 0 || tamanho >= static_cast<int>(sizeof(mensagem))) return false;
  const mbedtls_md_info_t* tipo = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (!tipo) return false;
  uint8_t calculada[32];
  if (mbedtls_md_hmac(tipo, chaveControle, sizeof(chaveControle),
                      reinterpret_cast<const unsigned char*>(mensagem),
                      static_cast<size_t>(tamanho), calculada) != 0) return false;
  uint8_t diferenca = 0;
  for (size_t i=0;i<sizeof(calculada);++i) diferenca |= calculada[i] ^ fornecida[i];
  return diferenca == 0;
}

void receberComandoMqtt(char* topico, uint8_t* payload, unsigned int tamanho) {
  if (!topico || strcmp(topico, topicoComandos) || !controleMqttConfigurado ||
      tamanho == 0 || tamanho > 700) return;
  StaticJsonDocument<512> doc;
  DeserializationError erro = deserializeJson(doc, payload, tamanho);
  if (erro || doc["v"].as<int>() != 1 ||
      strcmp(doc["device_id"] | "", DEVICE_ID) ||
      strcmp(doc["boot"] | "", sessaoControle)) return;
  const char* seq = doc["seq"] | "";
  uint64_t numero = 0;
  if (!lerSequencia(seq, numero) || numero <= ultimaSequenciaControle) return;
  const char* acao = doc["action"] | "";
  const char* modo = doc["mode"] | "";
  const char* assinatura = doc["sig"] | "";
  // Rejeitar representacoes alternativas evita ambiguidade entre JSON e HMAC.
  if (!doc["mask"].is<int>() || !doc["main"].is<int>() || !doc["star"].is<int>() ||
      !doc["delta"].is<int>() || !doc["seconds"].is<int>()) return;
  int mascara = doc["mask"].as<int>();
  int principal = doc["main"].as<int>();
  int estrela = doc["star"].as<int>();
  int triangulo = doc["delta"].as<int>();
  int segundos = doc["seconds"].as<int>();
  if (!assinaturaControleValida(seq, acao, modo, mascara, principal, estrela,
                                triangulo, segundos, assinatura)) return;
  ultimaSequenciaControle = numero; // Repeticao do mesmo comando nao pode rearmar saidas.
  if (!strcmp(acao, "stop") && !strcmp(modo, "none") && mascara == 0 &&
      principal == 0 && estrela == 0 && triangulo == 0 && segundos == 0) {
    pararBancada();
    publicarRespostaControle(seq, true, acao, "stopped");
    return;
  }
  if (strcmp(acao, "start") || !bancadaHabilitada() || etapaPartida != 0 ||
      WiFi.status() != WL_CONNECTED) {
    publicarRespostaControle(seq, false, acao, "blocked");
    return;
  }
  for (uint8_t i=0;i<NUM_RELES;++i) if (estadoReles[i]) {
    publicarRespostaControle(seq, false, acao, "already_on");
    return;
  }
  bool direta = !strcmp(modo,"direct") && mascara>=1 && mascara<=15 &&
      principal==0 && estrela==0 && triangulo==0 && segundos==0;
  bool sequencia = !strcmp(modo,"sequence") && mascara==0 &&
      principal>=1 && principal<=4 && estrela>=1 && estrela<=4 &&
      triangulo>=1 && triangulo<=4 && principal!=estrela &&
      principal!=triangulo && estrela!=triangulo && segundos>=2 && segundos<=30;
  if (!direta && !sequencia) {
    publicarRespostaControle(seq, false, acao, "invalid_profile");
    return;
  }
  aplicarMascaraReles(0);
  modoPartida = sequencia ? 1 : 0;
  mascaraDireta = static_cast<uint8_t>(mascara);
  if (sequencia) {
    indicePrincipal=principal-1; indiceEstrela=estrela-1; indiceTriangulo=triangulo-1;
    tempoEstrelaMs=static_cast<unsigned long>(segundos)*1000UL;
  }
  momentoPartida=millis(); momentoEtapa=momentoPartida; etapaPartida=1;
  publicarRespostaControle(seq, true, acao, "accepted");
}
