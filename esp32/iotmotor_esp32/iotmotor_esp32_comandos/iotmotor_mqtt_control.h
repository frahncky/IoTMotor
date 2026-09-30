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

// Desafio da vez, retido: sem ele o painel nao tem como cifrar um comando.
void publicarAuth() {
  StaticJsonDocument<192> doc;
  doc["v"] = 1;
  doc["device_id"] = DEVICE_ID;
  comandoseguro::descrever(doc);
  char payload[192];
  const size_t len = serializeJson(doc, payload, sizeof(payload));
  if (len) mqttClient.publish(topicoAuth, reinterpret_cast<const uint8_t*>(payload),
                              static_cast<unsigned int>(len), true);
}

// Desarme automatico: a placa de sensores manda Desligar com reason "alarm"
// quando um alarme com desarme dispara. Guardamos qual foi, para o LCD, o
// painel e o app dizerem por que o motor parou, ate a proxima partida.
char desarmeAlarme[16] = "";
char desarmeCampo[20] = "";

void pararPorComando(JsonVariantConst doc) {
  bool saidas = partidaAtiva;
  for (uint8_t i = 0; i < NUM_RELES; ++i) saidas = saidas || estadoReles[i];
  pararBancada();
  if (saidas && !strcmp(doc["reason"] | "", "alarm")) {
    strncpy(desarmeAlarme, doc["alarm"] | "", sizeof(desarmeAlarme) - 1);
    desarmeAlarme[sizeof(desarmeAlarme) - 1] = '\0';
    strncpy(desarmeCampo, doc["field"] | "", sizeof(desarmeCampo) - 1);
    desarmeCampo[sizeof(desarmeCampo) - 1] = '\0';
    lcdPrecisaAtualizar = true;
    Serial.printf("[BANCADA] desarme pelo alarme %s (%s)\n", desarmeAlarme, desarmeCampo);
  }
}

// Pedido de reinicio remoto (0 = nenhum); atendido no loop() do sketch.
unsigned long reinicioPedidoEm = 0;

void publicarRespostaControle(const char* seq, bool aceito, const char* acao, const char* motivo) {
  if (!mqttClient.connected()) return;
  StaticJsonDocument<256> resposta;
  resposta["device_id"] = DEVICE_ID;
  resposta["seq"] = seq;
  resposta["accepted"] = aceito;
  resposta["action"] = acao;
  resposta["reason"] = motivo;
  resposta["phase"] = nomeEtapa();
  char payload[384];  // Cabe o motivo longo de uma falha de OTA (proxy | github).
  size_t len = serializeJson(resposta, payload, sizeof(payload));
  if (len) mqttClient.publish(topicoResposta, reinterpret_cast<const uint8_t*>(payload),
                              static_cast<unsigned int>(len), false);
}

// Lista de redes gravada na placa, sem senhas, com a chave publica para o
// painel cifrar senhas novas. Retida para a aba "Wi-Fi" abrir ja preenchida.
void publicarRedes() {
  if (!mqttClient.connected()) return;
  StaticJsonDocument<1536> doc;
  doc["device_id"] = DEVICE_ID;
  wifistore::descrever(doc);
  char payload[1536];
  const size_t len = serializeJson(doc, payload, sizeof(payload));
  if (len) mqttClient.publish(topicoWifi, reinterpret_cast<const uint8_t*>(payload),
                              static_cast<unsigned int>(len), true);
}

// Lista de partidas gravada na placa: mesma lista para o painel e para o app.
void publicarPerfis() {
  if (!mqttClient.connected()) return;
  DynamicJsonDocument doc(TAMANHO_DOC_PERFIS);
  doc["device_id"] = DEVICE_ID;
  descreverPerfis(doc);
  String payload;
  serializeJson(doc, payload);
  if (payload.length() &&
      !mqttClient.publish(topicoPerfis, reinterpret_cast<const uint8_t*>(payload.c_str()),
                          static_cast<unsigned int>(payload.length()), true))
    Serial.printf("[MQTT] falha publicando partidas (%u bytes)\n", (unsigned int)payload.length());
}

// Dados de placa do motor, retidos: o painel e o app abrem ja preenchidos.
void publicarMotorInfo() {
  if (!mqttClient.connected()) return;
  StaticJsonDocument<1024> doc;
  doc["device_id"] = DEVICE_ID;
  motorinfo::descrever(doc);
  char payload[1024];
  const size_t len = serializeJson(doc, payload, sizeof(payload));
  if (len) mqttClient.publish(topicoMotorInfo, reinterpret_cast<const uint8_t*>(payload),
                              static_cast<unsigned int>(len), true);
}

// Converte os comandos antigos (mode direct/sequence) em um perfil temporario,
// para o painel e o app anteriores continuarem funcionando.
bool perfilDeComandoAntigo(JsonVariantConst doc, PerfilDePartida& perfil) {
  const char* modo = doc["mode"] | "";
  strncpy(perfil.id, "temp", MAX_ID_PERFIL);
  if (!strcmp(modo, "direct")) {
    const int mascara = doc["mask"] | 0;
    if (mascara < 1 || mascara > 15) return false;
    strncpy(perfil.nome, "Partida direta", MAX_NOME_PERFIL);
    for (uint8_t i = 0; i < NUM_RELES; ++i)
      perfil.contator[i] = {static_cast<bool>(mascara & (1U << i)), ATRASO_INICIAL_MS, 0};
    return true;
  }
  if (strcmp(modo, "sequence")) return false;
  const int principal = doc["main"] | 0, estrela = doc["star"] | 0;
  const int triangulo = doc["delta"] | 0, segundos = doc["seconds"] | 0;
  if (principal < 1 || principal > 4 || estrela < 1 || estrela > 4 || triangulo < 1 || triangulo > 4 ||
      principal == estrela || principal == triangulo || estrela == triangulo ||
      segundos < 2 || segundos > 30) return false;
  strncpy(perfil.nome, "Estrela-triangulo", MAX_NOME_PERFIL);
  const uint32_t fimEstrela = ATRASO_INICIAL_MS + static_cast<uint32_t>(segundos) * 1000UL;
  perfil.contator[principal - 1] = {true, ATRASO_INICIAL_MS, 0};
  perfil.contator[estrela - 1] = {true, ATRASO_INICIAL_MS, fimEstrela};
  perfil.contator[triangulo - 1] = {true, fimEstrela + TEMPO_MORTO_MS, 0};
  return true;
}

void receberComandoMqtt(char* topico, uint8_t* payload, unsigned int tamanho) {
  if (!topico || strcmp(topico, topicoComandos) || !tamanho || tamanho > 1400) return;
  StaticJsonDocument<1536> doc;
  if (deserializeJson(doc, payload, tamanho) || doc["v"].as<int>() != 1 ||
      strcmp(doc["device_id"] | "", DEVICE_ID)) return;

  // Com senha configurada, so passa comando cifrado e com o desafio da vez.
  // Desligar e a excecao: parar e sempre o lado seguro, entao vale sem selo e
  // com desafio vencido (dois clientes mandando ao mesmo tempo nao podem
  // deixar o motor sem poder parar).
  if (comandoseguro::ligado) {
    static char aberto[comandoseguro::MAX_ABERTO];
    const char* motivo = "";
    if (!(doc["sealed"] | "")[0]) {
      if (!strcmp(doc["action"] | "", "stop")) {
        pararPorComando(doc.as<JsonVariantConst>());
        publicarRespostaControle(doc["seq"] | "", true, "stop", "stopped");
        return;
      }
      publicarRespostaControle(doc["seq"] | "", false, doc["action"] | "sealed",
                               "comando sem selo: configure a senha de comando");
      return;
    }
    if (!comandoseguro::abrir(doc["sealed"] | "", DEVICE_ID, aberto, sizeof(aberto), motivo)) {
      publicarRespostaControle(doc["seq"] | "", false, "sealed", motivo);
      return;
    }
    doc.clear();
    if (deserializeJson(doc, aberto) || doc["v"].as<int>() != 1 ||
        strcmp(doc["device_id"] | "", DEVICE_ID)) return;
    const bool parada = !strcmp(doc["action"] | "", "stop");
    if (!parada && !comandoseguro::confereDesafio(doc["ch"] | "")) {
      publicarRespostaControle(doc["seq"] | "", false, doc["action"] | "sealed",
                               "desafio vencido: envie de novo");
      return;
    }
    if (!parada) {
      comandoseguro::usar();  // Comando repetido do ar nao vale mais.
      publicarAuth();
    }
  }

  const char* seq = doc["seq"] | "";
  uint64_t numero = 0;
  if (!lerSequencia(seq, numero)) return;
  const char* acao = doc["action"] | "";

  // Lista de partidas: criada ou editada no painel ou no app, vale nos dois.
  if (!strcmp(acao, "profile_list")) {
    publicarRespostaControle(seq, true, acao, "lista publicada");
    publicarPerfis();
    return;
  }
  if (!strcmp(acao, "profile_save") || !strcmp(acao, "profile_remove")) {
    const char* motivo = "";
    const bool ok = !strcmp(acao, "profile_save")
                        ? salvarPerfil(doc["profile"], motivo)
                        : removerPerfil(doc["id"] | "", motivo);
    publicarRespostaControle(seq, ok, acao, motivo);
    publicarPerfis();
    return;
  }

  // Configuracao unica de aquisicao/telemetria/visualizacao. O ESP32-01
  // e a autoridade: grava em NVS e publica retido para painel, app e ESP32-S3.
  if (!strcmp(acao, "acquisition_config_get")) {
    publicarRespostaControle(seq, true, acao, "configuracao publicada");
    publicarConfiguracaoAquisicao();
    return;
  }
  if (!strcmp(acao, "acquisition_config_set")) {
    const char* motivo = "";
    const bool ok = salvarConfiguracaoAquisicao(doc["config"], motivo);
    publicarRespostaControle(seq, ok, acao, motivo);
    if (ok) publicarConfiguracaoAquisicao();
    return;
  }

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
    for (uint8_t i = 0; i < NUM_RELES; ++i) if (estadoReles[i] || partidaAtiva) {
      publicarRespostaControle(seq, false, acao, "saidas ligadas: pare antes de configurar");
      return;
    }
    publicarRespostaControle(seq, true, acao, "rede da placa aberta por 180 s");
    delay(200);  // Tempo de a resposta sair antes de o Wi-Fi virar ponto de acesso.
    abrirPortalDeRede(PORTAL_SEGUNDOS);
    ESP.restart();  // Volta ao funcionamento normal ja com a rede nova.
    return;
  }

  // Reinicio remoto, como o botao de reset. Reiniciar desliga os reles, entao
  // so com as saidas paradas; o loop() reinicia depois de a resposta sair.
  if (!strcmp(acao, "restart")) {
    for (uint8_t i = 0; i < NUM_RELES; ++i) if (estadoReles[i] || partidaAtiva) {
      publicarRespostaControle(seq, false, acao, "saidas ligadas: pare antes de reiniciar");
      return;
    }
    publicarRespostaControle(seq, true, acao, "reiniciando");
    reinicioPedidoEm = millis() | 1UL;
    return;
  }

  // Atualizacao pela internet: URL fixa no firmware, nunca vinda da mensagem.
  if (!strcmp(acao, "update")) {
    for (uint8_t i = 0; i < NUM_RELES; ++i) if (estadoReles[i] || partidaAtiva) {
      publicarRespostaControle(seq, false, acao, "saidas ligadas: pare antes de atualizar");
      return;
    }
    // seq aponta para o buffer do PubSubClient, que o publish logo abaixo
    // sobrescreve: a resposta de falha usa uma copia.
    char seqDoPedido[20];
    strlcpy(seqDoPedido, seq, sizeof(seqDoPedido));
    publicarRespostaControle(seq, true, acao, "baixando firmware");
    String motivo;
    atualizarPelaInternet(OTA_ARQUIVO, motivo);  // Sucesso reinicia a placa.
    publicarRespostaControle(seqDoPedido, false, "update", motivo.c_str());
    return;
  }

  // Quanto tempo um ensaio pode durar: -1 sem limite, ou de 10 s a 2 h.
  if (!strcmp(acao, "run_limit")) {
    if (!doc["seconds"].is<long>()) {
      publicarRespostaControle(seq, false, acao, "campo seconds ausente");
      return;
    }
    const long segundos = doc["seconds"].as<long>();
    const bool ok = salvarLimiteDoEnsaio(segundos);
    char motivo[80];
    if (!ok) snprintf(motivo, sizeof(motivo), "use de 10 a %ld s, ou -1 para sem limite", MAX_ENSAIO_S);
    else if (segundos < 0) snprintf(motivo, sizeof(motivo), "o ensaio nao cai mais por tempo");
    else snprintf(motivo, sizeof(motivo), "o ensaio cai apos %ld s", segundos);
    publicarRespostaControle(seq, ok, acao, motivo);
    return;
  }

  // Dados de placa do motor (corrente nominal etc.), gravados nesta placa.
  if (!strcmp(acao, "motor_info_set")) {
    const char* motivo = "";
    const bool ok = motorinfo::salvar(doc["motor"], motivo);
    publicarRespostaControle(seq, ok, acao, motivo);
    if (ok) publicarMotorInfo();
    return;
  }
  // Manutencao feita: o lembrete volta a contar do horimetro atual.
  if (!strcmp(acao, "maintenance_done")) {
    motorinfo::registrarManutencao(relogio::agoraUtc());
    publicarRespostaControle(seq, true, acao, "manutencao registrada");
    publicarMotorInfo();
    return;
  }
  // Zera horimetro e partidas (troca de motor); so com as saidas paradas e o
  // motor parado (em modo instrumentacao ele gira sem rele: vale a corrente).
  if (!strcmp(acao, "motor_counters_reset")) {
    for (uint8_t i = 0; i < NUM_RELES; ++i) if (estadoReles[i] || partidaAtiva || motorinfo::girando) {
      publicarRespostaControle(seq, false, acao, "saidas ligadas: pare antes de zerar");
      return;
    }
    motorinfo::zerarContadores();
    publicarRespostaControle(seq, true, acao, "horimetro e partidas zerados");
    publicarMotorInfo();
    return;
  }

  // Quanto tempo o ensaio segue sem rede: -1 sem limite, 0 derruba na hora.
  if (!strcmp(acao, "link_grace")) {
    if (!doc["seconds"].is<long>()) {
      publicarRespostaControle(seq, false, acao, "campo seconds ausente");
      return;
    }
    const long segundos = doc["seconds"].as<long>();
    const bool ok = salvarToleranciaSemLink(segundos);
    char motivo[72];
    if (!ok) snprintf(motivo, sizeof(motivo), "use de 0 a %ld s, ou -1 para sem limite", MAX_TOLERANCIA_S);
    else if (segundos < 0) snprintf(motivo, sizeof(motivo), "o ensaio segue sem rede ate o limite de ensaio");
    else if (!segundos) snprintf(motivo, sizeof(motivo), "as saidas caem assim que a rede cair");
    else snprintf(motivo, sizeof(motivo), "o ensaio segue por %ld s sem rede", segundos);
    publicarRespostaControle(seq, ok, acao, motivo);
    return;
  }

  // Liga e desliga o acionamento. Desligar vale na hora e fica gravado.
  if (!strcmp(acao, "actuation")) {
    if (!doc["on"].is<bool>()) {
      publicarRespostaControle(seq, false, acao, "campo on ausente");
      return;
    }
    const bool ligar = doc["on"].as<bool>();
    const bool ok = salvarAcionamento(ligar);
    publicarRespostaControle(seq, ok, acao,
                             !ok ? "falha ao gravar"
                                 : ligar ? "acionamento liberado"
                                         : "modo instrumentacao: a placa nao aciona contatores");
    return;
  }

  // Parar sempre: nao depende de telemetria, boot, estado ou partida pendente.
  if (!strcmp(acao, "stop")) {
    pararPorComando(doc.as<JsonVariantConst>());
    publicarRespostaControle(seq, true, acao, "stopped");
    return;
  }
  if (strcmp(acao, "start")) {
    publicarRespostaControle(seq, false, acao, "unknown_action");
    return;
  }
  if (!acionamentoLigado) {
    publicarRespostaControle(seq, false, acao, "modo instrumentacao: acionamento desligado");
    return;
  }
  // Intertravamento local: clientes desatualizados tambem nao conseguem
  // partir o motor sem o PZEM confirmar uma leitura valida de tensao.
  if (!pzemOk || !isfinite(ultimaTensao) || ultimaTensao <= 0.0f) {
    publicarRespostaControle(seq, false, acao, "sem leitura valida de tensao");
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
  if (partidaAtiva || WiFi.status() != WL_CONNECTED) {
    publicarRespostaControle(seq, false, acao, "busy_or_offline");
    return;
  }
  for (uint8_t i = 0; i < NUM_RELES; ++i) if (estadoReles[i]) {
    publicarRespostaControle(seq, false, acao, "already_on");
    return;
  }

  // Partida por perfil salvo na placa (painel e app novos) ou pelo formato
  // antigo (mode direct/sequence), convertido no mesmo motor de tempos.
  PerfilDePartida perfil;
  const char* idPerfil = doc["profile"] | "";
  if (idPerfil[0]) {
    const int i = indiceDePerfil(idPerfil);
    if (i < 0) {
      publicarRespostaControle(seq, false, acao, "partida nao encontrada na placa");
      return;
    }
    perfil = perfis[i];
  } else if (!perfilDeComandoAntigo(doc, perfil)) {
    publicarRespostaControle(seq, false, acao, "invalid_profile");
    return;
  }
  iniciarPerfil(perfil, millis());
  desarmeAlarme[0] = desarmeCampo[0] = '\0';  // Nova partida: o desarme ficou para tras.
  lcdPrecisaAtualizar = true;
  publicarRespostaControle(seq, true, acao, "accepted");
}
