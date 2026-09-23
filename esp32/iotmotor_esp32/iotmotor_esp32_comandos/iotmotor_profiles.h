#pragma once
// Perfis de partida guardados na placa: cada contator tem o instante em que
// liga e o instante em que desliga, contados do inicio da partida.
//
// A lista mora aqui (NVS) e e publicada em .../profiles, entao o painel e o
// app mostram e editam a MESMA lista: criar uma partida em um aparece no outro.
// Partida direta e estrela-triangulo sao apenas casos particulares:
//   direta        -> contatores ligam em 0 e ficam ate parar
//   estrela-tri.  -> principal 0 ate parar, estrela 0 a T, triangulo T+morto
//
// Nao ha habilitacao por jumper GPIO32. O circuito de ensaio deve permanecer
// desconectado de motores e contatores no broker publico.
// Desligamento automatico de seguranca: 5 minutos por ensaio.
constexpr unsigned long LIMITE_BANCADA_MS = 300000UL;
// Limite em uso, gravado na placa. SEM_LIMITE_ENSAIO = o ensaio nao cai por
// tempo: ai o que o encerra e o fim do proprio perfil, o Desligar, a queda de
// rede (quando configurada) e, sempre, a parada eletrica.
constexpr uint32_t SEM_LIMITE_ENSAIO = 0xFFFFFFFFUL;
uint32_t limiteDoEnsaioMs = LIMITE_BANCADA_MS;
constexpr unsigned long TEMPO_MORTO_MS = 700UL;
// Espera antes de acionar qualquer saida, para o comando ser confirmado antes.
constexpr unsigned long ATRASO_INICIAL_MS = 500UL;
// Quedas curtas de MQTT/Wi-Fi sao toleradas; acima disso as saidas desligam.
constexpr unsigned long TOLERANCIA_SEM_LINK_MS = 15000UL;
unsigned long inicioSemLink = 0;  // 0 = conexao ok

constexpr uint8_t MAX_PERFIS = 6;
constexpr size_t MAX_ID_PERFIL = 12;
constexpr size_t MAX_NOME_PERFIL = 24;

struct ContatorDoPerfil {
  bool usa = false;
  uint32_t ligaMs = 0;     // Instante em que liga, do inicio da partida.
  uint32_t desligaMs = 0;  // 0 = fica ligado ate parar ou ate o limite.
};

struct PerfilDePartida {
  char id[MAX_ID_PERFIL + 1] = "";
  char nome[MAX_NOME_PERFIL + 1] = "";
  ContatorDoPerfil contator[NUM_RELES];
};

PerfilDePartida perfis[MAX_PERFIS];
uint8_t totalPerfis = 0;
PerfilDePartida perfilEmExecucao;
bool partidaAtiva = false;
unsigned long momentoPartida = 0;
uint8_t mascaraAplicada = 0;

// Diferenca com sinal: o comando MQTT chega depois de "agora" ser lido no loop,
// entao marcos podem ficar no futuro. Sem sinal, isso virava um numero enorme
// e a partida era cancelada como "tempo limite" antes de ligar os reles.
static inline int32_t decorrido(unsigned long agora, unsigned long marco) {
  return static_cast<int32_t>(static_cast<uint32_t>(agora) - static_cast<uint32_t>(marco));
}

// Tempo decorrido da partida, em ms (0 quando parada).
uint32_t tempoDePartidaMs(unsigned long agora) {
  if (!partidaAtiva) return 0;
  const int32_t d = decorrido(agora, momentoPartida);
  return d > 0 ? static_cast<uint32_t>(d) : 0;
}

// Contatores que devem estar ligados neste instante da partida.
uint8_t mascaraNoInstante(const PerfilDePartida& perfil, uint32_t tempoMs) {
  uint8_t mascara = 0;
  for (uint8_t i = 0; i < NUM_RELES; ++i) {
    const ContatorDoPerfil& c = perfil.contator[i];
    if (!c.usa || tempoMs < c.ligaMs) continue;
    if (c.desligaMs && tempoMs >= c.desligaMs) continue;
    mascara |= (1U << i);
  }
  return mascara;
}

// Instante em que o perfil termina sozinho; 0 = so para por comando ou limite.
uint32_t fimDoPerfil(const PerfilDePartida& perfil) {
  uint32_t fim = 0;
  for (uint8_t i = 0; i < NUM_RELES; ++i) {
    const ContatorDoPerfil& c = perfil.contator[i];
    if (!c.usa) continue;
    if (!c.desligaMs) return 0;  // Algum contator fica ligado ate parar.
    if (c.desligaMs > fim) fim = c.desligaMs;
  }
  return fim;
}

const char* nomeEtapa() {
  return partidaAtiva ? perfilEmExecucao.nome : "Parado / comando manual";
}

void aplicarMascaraReles(uint8_t mascara) {
  // Desligar antes de ligar; mantem o principal na transicao estrela-triangulo.
  for (uint8_t i = 0; i < NUM_RELES; ++i) if (!(mascara & (1U << i)) && estadoReles[i]) {
    estadoReles[i] = false;
    aplicarEstadoRele(i);
  }
  for (uint8_t i = 0; i < NUM_RELES; ++i) if ((mascara & (1U << i)) && !estadoReles[i]) {
    estadoReles[i] = true;
    aplicarEstadoRele(i);
  }
  mascaraAplicada = mascara;
  lcdPrecisaAtualizar = true;
}

void pararBancada() {
  partidaAtiva = false;
  aplicarMascaraReles(0);
}

void iniciarPerfil(const PerfilDePartida& perfil, unsigned long agora) {
  perfilEmExecucao = perfil;
  momentoPartida = agora;
  partidaAtiva = true;
  aplicarMascaraReles(0);  // Comeca com tudo desligado; o atraso inicial vale.
}

void manterPartidaBancada(unsigned long agora) {
  bool ligada = partidaAtiva;
  for (uint8_t i = 0; i < NUM_RELES; ++i) ligada = ligada || estadoReles[i];
  if (!ligada) return;
  // Limite de sessao; a perda de rede e tratada no loop com tolerancia.
  if (limiteDoEnsaioMs != SEM_LIMITE_ENSAIO &&
      decorrido(agora, momentoPartida) > (int32_t)limiteDoEnsaioMs) {
    pararBancada();
    Serial.println("[BANCADA] saidas desligadas pelo tempo limite do ensaio");
    return;
  }
  if (!partidaAtiva) return;
  const uint32_t tempo = tempoDePartidaMs(agora);
  const uint32_t fim = fimDoPerfil(perfilEmExecucao);
  if (fim && tempo >= fim) {  // Perfil com fim definido: termina sozinho.
    pararBancada();
    Serial.println("[BANCADA] perfil concluido");
    return;
  }
  const uint8_t desejada = mascaraNoInstante(perfilEmExecucao, tempo);
  if (desejada != mascaraAplicada) aplicarMascaraReles(desejada);
}

// ---- Lista de perfis: validacao, montagem e gravacao ----

bool perfilValido(const PerfilDePartida& perfil) {
  if (!perfil.id[0] || !perfil.nome[0]) return false;
  bool algum = false;
  for (uint8_t i = 0; i < NUM_RELES; ++i) {
    const ContatorDoPerfil& c = perfil.contator[i];
    if (!c.usa) continue;
    algum = true;
    if (c.ligaMs > LIMITE_BANCADA_MS) return false;
    if (c.desligaMs && c.desligaMs <= c.ligaMs) return false;
    if (c.desligaMs > LIMITE_BANCADA_MS) return false;
  }
  return algum;
}

int indiceDePerfil(const char* id) {
  for (uint8_t i = 0; i < totalPerfis; ++i)
    if (!strcmp(perfis[i].id, id)) return i;
  return -1;
}

void descreverPerfis(JsonDocument& doc) {
  JsonArray lista = doc.createNestedArray("profiles");
  for (uint8_t i = 0; i < totalPerfis; ++i) {
    JsonObject item = lista.createNestedObject();
    item["id"] = perfis[i].id;
    item["name"] = perfis[i].nome;
    JsonArray contatores = item.createNestedArray("cnt");
    for (uint8_t c = 0; c < NUM_RELES; ++c) {
      JsonObject saida = contatores.createNestedObject();
      saida["use"] = perfis[i].contator[c].usa;
      saida["on"] = perfis[i].contator[c].ligaMs;
      saida["off"] = perfis[i].contator[c].desligaMs;
    }
  }
  doc["max"] = MAX_PERFIS;
  doc["limit_ms"] = LIMITE_BANCADA_MS;
  doc["run_limit_s"] = limiteDoEnsaioMs == SEM_LIMITE_ENSAIO
                           ? -1
                           : (int)(limiteDoEnsaioMs / 1000UL);
  if (partidaAtiva) doc["running"] = perfilEmExecucao.id;
}

void gravarPerfis() {
  StaticJsonDocument<2048> doc;
  descreverPerfis(doc);
  String texto;
  serializeJson(doc["profiles"], texto);
  Preferences memoria;
  if (!memoria.begin("iot-perfis", false)) return;
  memoria.putString("lista", texto);
  memoria.end();
}

// Le um perfil de um JSON {id,name,cnt:[{use,on,off} x4]}.
bool lerPerfilDeJson(JsonVariantConst origem, PerfilDePartida& destino) {
  const char* id = origem["id"] | "";
  const char* nome = origem["name"] | "";
  if (!id[0] || strlen(id) > MAX_ID_PERFIL || !nome[0] || strlen(nome) > MAX_NOME_PERFIL) return false;
  strncpy(destino.id, id, MAX_ID_PERFIL);
  destino.id[MAX_ID_PERFIL] = '\0';
  strncpy(destino.nome, nome, MAX_NOME_PERFIL);
  destino.nome[MAX_NOME_PERFIL] = '\0';
  JsonArrayConst contatores = origem["cnt"].as<JsonArrayConst>();
  if (contatores.size() != NUM_RELES) return false;
  uint8_t i = 0;
  for (JsonVariantConst item : contatores) {
    destino.contator[i].usa = item["use"] | false;
    destino.contator[i].ligaMs = item["on"] | 0UL;
    destino.contator[i].desligaMs = item["off"] | 0UL;
    ++i;
  }
  return perfilValido(destino);
}

void semearPerfisPadrao() {
  totalPerfis = 0;
  PerfilDePartida direta;
  strcpy(direta.id, "direta");
  strcpy(direta.nome, "Direta");
  direta.contator[0] = {true, ATRASO_INICIAL_MS, 0};
  perfis[totalPerfis++] = direta;

  PerfilDePartida estrela;
  strcpy(estrela.id, "estrela");
  strcpy(estrela.nome, "Estrela-triangulo");
  estrela.contator[0] = {true, ATRASO_INICIAL_MS, 0};
  estrela.contator[1] = {true, ATRASO_INICIAL_MS, ATRASO_INICIAL_MS + 5000};
  estrela.contator[2] = {true, ATRASO_INICIAL_MS + 5000 + TEMPO_MORTO_MS, 0};
  perfis[totalPerfis++] = estrela;
}

void carregarPerfis() {
  Preferences memoria;
  String texto;
  if (memoria.begin("iot-perfis", true)) {
    texto = memoria.getString("lista", "");
    memoria.end();
  }
  totalPerfis = 0;
  if (texto.length()) {
    StaticJsonDocument<2048> doc;
    if (!deserializeJson(doc, texto)) {
      for (JsonVariantConst item : doc.as<JsonArrayConst>()) {
        if (totalPerfis >= MAX_PERFIS) break;
        PerfilDePartida perfil;
        if (lerPerfilDeJson(item, perfil)) perfis[totalPerfis++] = perfil;
      }
    }
  }
  if (!totalPerfis) {  // Primeiro boot ou lista corrompida.
    semearPerfisPadrao();
    gravarPerfis();
  }
  Serial.printf("[PERFIS] %u partida(s) na placa\n", totalPerfis);
}

bool salvarPerfil(JsonVariantConst origem, const char*& motivo) {
  PerfilDePartida perfil;
  if (!lerPerfilDeJson(origem, perfil)) {
    motivo = "perfil invalido: confira nome, contatores e tempos";
    return false;
  }
  const int existente = indiceDePerfil(perfil.id);
  if (existente >= 0) {
    perfis[existente] = perfil;
  } else {
    if (totalPerfis >= MAX_PERFIS) {
      motivo = "limite de partidas atingido";
      return false;
    }
    perfis[totalPerfis++] = perfil;
  }
  gravarPerfis();
  motivo = existente >= 0 ? "partida atualizada" : "partida criada";
  return true;
}

bool removerPerfil(const char* id, const char*& motivo) {
  if (totalPerfis <= 1) {
    motivo = "mantenha ao menos uma partida";
    return false;
  }
  const int i = indiceDePerfil(id ? id : "");
  if (i < 0) {
    motivo = "partida nao encontrada";
    return false;
  }
  for (uint8_t j = i; j + 1 < totalPerfis; ++j) perfis[j] = perfis[j + 1];
  --totalPerfis;
  gravarPerfis();
  motivo = "partida removida";
  return true;
}
