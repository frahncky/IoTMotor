// Partidas do quadro de comando (iotmotor_profiles.h), com o codigo real do
// firmware. O que esta aqui protege o motor: ordem dos contatores, tempo morto
// da estrela-triangulo e o desligamento pelo limite do ensaio.
#include <vector>
#include "teste.h"
#include "Arduino.h"
#include "ArduinoJson.h"
#include "Preferences.h"

// O que o .ino declara antes de incluir o cabecalho.
constexpr uint8_t NUM_RELES = 4;
bool estadoReles[NUM_RELES] = {false, false, false, false};
bool lcdPrecisaAtualizar = false;
struct Troca { unsigned long ms; uint8_t rele; bool liga; };
std::vector<Troca> trocas;
void aplicarEstadoRele(uint8_t i) { trocas.push_back({relogioFalsoMs, i, estadoReles[i]}); }

#include "../iotmotor_esp32/iotmotor_esp32_comandos/iotmotor_profiles.h"

static void recomecar() {
  prefsFalsas::apagar();
  for (bool& r : estadoReles) r = false;
  partidaAtiva = false;
  mascaraAplicada = 0;
  limiteDoEnsaioMs = LIMITE_BANCADA_MS;
  trocas.clear();
}

// Roda a partida como o loop faz, de 1 em 1 ms, de 'de' ate 'ate'.
static void rodar(unsigned long de, unsigned long ate) {
  for (relogioFalsoMs = de; relogioFalsoMs <= ate; ++relogioFalsoMs) manterPartidaBancada(relogioFalsoMs);
}

static const PerfilDePartida& perfilPadrao(const char* id) {
  return perfis[indiceDePerfil(id)];
}

TESTE("primeiro boot cria as partidas direta e estrela-triangulo") {
  recomecar();
  carregarPerfis();
  CONFERE(totalPerfis == 2);
  CONFERE(indiceDePerfil("direta") == 0);
  CONFERE(indiceDePerfil("estrela") == 1);
  CONFERE(prefsFalsas::dados.count("iot-perfis/lista") == 1);  // Ja fica gravado.
}

TESTE("estrela-triangulo nunca fecha estrela e triangulo juntos") {
  recomecar();
  semearPerfisPadrao();
  iniciarPerfil(perfilPadrao("estrela"), 1000);
  bool juntos = false;
  for (relogioFalsoMs = 1000; relogioFalsoMs <= 20000; ++relogioFalsoMs) {
    manterPartidaBancada(relogioFalsoMs);
    juntos = juntos || (estadoReles[1] && estadoReles[2]);
  }
  CONFERE(!juntos);
  CONFERE(estadoReles[0] && !estadoReles[1] && estadoReles[2]);  // Termina em triangulo.
}

TESTE("estrela-triangulo: atraso inicial, 5 s em estrela e 700 ms de tempo morto") {
  recomecar();
  semearPerfisPadrao();
  iniciarPerfil(perfilPadrao("estrela"), 0);
  rodar(0, 8000);
  unsigned long ligaPrincipal = 0, ligaEstrela = 0, desligaEstrela = 0, ligaTriangulo = 0;
  for (const Troca& t : trocas) {
    if (t.rele == 0 && t.liga) ligaPrincipal = t.ms;
    if (t.rele == 1 && t.liga) ligaEstrela = t.ms;
    if (t.rele == 1 && !t.liga) desligaEstrela = t.ms;
    if (t.rele == 2 && t.liga) ligaTriangulo = t.ms;
  }
  CONFERE(ligaPrincipal == ATRASO_INICIAL_MS);
  CONFERE(ligaEstrela == ATRASO_INICIAL_MS);
  CONFERE(desligaEstrela == ATRASO_INICIAL_MS + 5000);
  CONFERE(ligaTriangulo - desligaEstrela == TEMPO_MORTO_MS);
}

TESTE("na troca de mascara, desliga antes de ligar") {
  recomecar();
  aplicarMascaraReles(0b0011);
  trocas.clear();
  aplicarMascaraReles(0b0101);  // Sai o 2, entra o 3, o 1 fica.
  CONFERE(trocas.size() == 2);
  CONFERE(trocas.size() == 2 && trocas[0].rele == 1 && !trocas[0].liga);
  CONFERE(trocas.size() == 2 && trocas[1].rele == 2 && trocas[1].liga);
}

TESTE("limite do ensaio desliga tudo") {
  recomecar();
  semearPerfisPadrao();
  limiteDoEnsaioMs = 10000;
  iniciarPerfil(perfilPadrao("direta"), 0);
  rodar(0, 10000);
  CONFERE(partidaAtiva && estadoReles[0]);
  rodar(10001, 10001);
  CONFERE(!partidaAtiva);
  for (bool r : estadoReles) CONFERE(!r);
}

TESTE("sem limite, a partida direta segue ligada") {
  recomecar();
  semearPerfisPadrao();
  limiteDoEnsaioMs = SEM_LIMITE_ENSAIO;
  iniciarPerfil(perfilPadrao("direta"), 0);
  for (relogioFalsoMs = 0; relogioFalsoMs <= 3600000UL; relogioFalsoMs += 50) manterPartidaBancada(relogioFalsoMs);
  CONFERE(partidaAtiva && estadoReles[0]);
}

TESTE("partida atravessando o estouro do millis() continua certa") {
  recomecar();
  semearPerfisPadrao();
  const unsigned long inicio = 0xFFFFFFFFUL - 2000;  // Estoura aos ~49,7 dias.
  iniciarPerfil(perfilPadrao("estrela"), inicio);
  bool juntos = false;
  for (unsigned long passo = 0; passo <= 8000; ++passo) {
    relogioFalsoMs = static_cast<uint32_t>(inicio + passo);
    manterPartidaBancada(relogioFalsoMs);
    juntos = juntos || (estadoReles[1] && estadoReles[2]);
  }
  CONFERE(!juntos);
  CONFERE(partidaAtiva);
  CONFERE(estadoReles[0] && estadoReles[2]);
}

TESTE("perfil que termina sozinho desliga no fim") {
  recomecar();
  PerfilDePartida pulso;
  strcpy(pulso.id, "pulso");
  strcpy(pulso.nome, "Pulso");
  pulso.contator[3] = {true, 100, 600};
  CONFERE(fimDoPerfil(pulso) == 600);
  iniciarPerfil(pulso, 0);
  rodar(0, 599);
  CONFERE(estadoReles[3]);
  rodar(600, 600);
  CONFERE(!partidaAtiva && !estadoReles[3]);
}

TESTE("validacao recusa perfis sem contator, invertidos ou longos demais") {
  PerfilDePartida p;
  strcpy(p.id, "x");
  strcpy(p.nome, "X");
  CONFERE(!perfilValido(p));                        // Nenhum contator.
  p.contator[0] = {true, 1000, 1000};
  CONFERE(!perfilValido(p));                        // Desliga no mesmo instante.
  p.contator[0] = {true, 2000, 1000};
  CONFERE(!perfilValido(p));                        // Desliga antes de ligar.
  p.contator[0] = {true, LIMITE_BANCADA_MS + 1, 0};
  CONFERE(!perfilValido(p));                        // Liga depois do limite.
  p.contator[0] = {true, 0, 0};
  CONFERE(perfilValido(p));
  strcpy(p.id, "");
  CONFERE(!perfilValido(p));                        // Sem id.
}

TESTE("seis partidas com nomes longos sobrevivem a gravar e reiniciar") {
  recomecar();
  totalPerfis = 0;
  for (uint8_t i = 0; i < MAX_PERFIS; ++i) {
    PerfilDePartida p;
    snprintf(p.id, sizeof(p.id), "perfil_%05u", i);
    snprintf(p.nome, sizeof(p.nome), "Nome bem comprido n%02u", i);
    for (uint8_t c = 0; c < NUM_RELES; ++c) p.contator[c] = {true, 250000U + c, 299999U};
    perfis[totalPerfis++] = p;
  }
  gravarPerfis();
  totalPerfis = 0;
  carregarPerfis();
  CONFERE(totalPerfis == MAX_PERFIS);
  CONFERE(totalPerfis == MAX_PERFIS && perfis[5].contator[3].ligaMs == 250003U);
}

TESTE("seis partidas no tamanho maximo cabem nos 3 KB do ESP32") {
  recomecar();
  totalPerfis = 0;
  size_t texto = 0;  // id e nome sao copiados para dentro do documento.
  for (uint8_t i = 0; i < MAX_PERFIS; ++i) {
    PerfilDePartida p;
    memset(p.id, 'i', MAX_ID_PERFIL);
    memset(p.nome, 'n', MAX_NOME_PERFIL);
    for (uint8_t c = 0; c < NUM_RELES; ++c) p.contator[c] = {true, 250000U + c, 299999U};
    perfis[totalPerfis++] = p;
    texto += MAX_ID_PERFIL + 1 + MAX_NOME_PERFIL + 1;
  }
  DocumentoPc doc(16384);
  descreverPerfis(doc);
  const size_t noEsp32 = bytesNoEsp32(doc, texto);
  std::printf("    6 partidas: %zu de %zu bytes no ESP32\n", noEsp32, TAMANHO_DOC_PERFIS);
  CONFERE(noEsp32 <= TAMANHO_DOC_PERFIS);
}

TESTE("perfil vindo do painel em JSON e lido e validado") {
  recomecar();
  semearPerfisPadrao();
  StaticJsonDocument<512> doc;
  deserializeJson(doc, R"({"id":"suave","name":"Suave","cnt":[
    {"use":true,"on":500,"off":0},{"use":false,"on":0,"off":0},
    {"use":false,"on":0,"off":0},{"use":false,"on":0,"off":0}]})");
  const char* motivo = "";
  CONFERE(salvarPerfil(doc.as<JsonVariantConst>(), motivo));
  CONFERE(!strcmp(motivo, "partida criada"));
  CONFERE(totalPerfis == 3);
  deserializeJson(doc, R"({"id":"ruim","name":"Ruim","cnt":[{"use":true,"on":500,"off":100}]})");
  CONFERE(!salvarPerfil(doc.as<JsonVariantConst>(), motivo));  // Faltam contatores e o tempo e invertido.
  CONFERE(totalPerfis == 3);
}

TESTE("nao remove a ultima partida") {
  recomecar();
  semearPerfisPadrao();
  const char* motivo = "";
  CONFERE(removerPerfil("direta", motivo));
  CONFERE(!removerPerfil("estrela", motivo));
  CONFERE(totalPerfis == 1);
}
