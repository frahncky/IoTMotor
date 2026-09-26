#pragma once
// Historico por hora dos ultimos 7 dias, guardado nesta placa (NVS).
//
// O painel so registra enquanto esta aberto; com isto a placa lembra, hora a
// hora, a corrente e a tensao (do quadro de comando), a temperatura e a
// vibracao, e quantos minutos o motor ficou ligado. Cada dia vai para um
// topico retido (history/<0..6>), entao o painel abre ja com os 7 dias.
//
// Corrente e vibracao so entram com o motor ligado: parado, a media diria
// apenas quanto tempo ele ficou desligado. Sem hora do NTP nada e registrado.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <Preferences.h>

namespace historico {

constexpr uint8_t DIAS = 7;
constexpr int16_t VAZIO = INT16_MIN;

// Valores em inteiros para caber na memoria: corrente em centesimos de A,
// tensao e temperatura em decimos, vibracao em milesimos de g.
struct Hora {
  int16_t correnteMedia = VAZIO, correnteMax = VAZIO, tensaoMedia = VAZIO;
  int16_t temperaturaMedia = VAZIO, temperaturaMax = VAZIO;
  int16_t vibracaoMedia = VAZIO, vibracaoMax = VAZIO;
  uint8_t minutosLigado = 0;
  bool usada = false;
};

struct Dia {
  uint32_t dia = 0;  // Dias desde 1970 (UTC); 0 = vazio.
  Hora horas[24];
};

inline Dia dias[DIAS];

// Acumulado da hora em andamento.
struct Acumulado {
  uint32_t hora = 0;  // Horas desde 1970 (UTC).
  double somaCorrente = 0, somaTensao = 0, somaTemperatura = 0, somaVibracao = 0;
  uint32_t nCorrente = 0, nTensao = 0, nTemperatura = 0, nVibracao = 0;
  float maxCorrente = 0, maxTemperatura = -1000, maxVibracao = 0;
  uint32_t segundosLigado = 0;
};

inline Acumulado acumulado;
inline int8_t diaParaPublicar = -1;  // Dia fechado que ainda nao foi publicado.

inline int16_t escalar(double valor, float fator) {
  const double v = valor * fator;
  if (!isfinite(v)) return VAZIO;
  return static_cast<int16_t>(constrain(lround(v), -32767L, 32767L));
}

inline void chave(uint8_t slot, char* saida) { snprintf(saida, 4, "d%u", slot); }

inline void carregar() {
  Preferences memoria;
  if (!memoria.begin("iot-hist", true)) return;
  for (uint8_t i = 0; i < DIAS; ++i) {
    char k[4];
    chave(i, k);
    Dia lido;
    if (memoria.isKey(k) && memoria.getBytesLength(k) == sizeof(Dia) && memoria.getBytes(k, &lido, sizeof(Dia)) == sizeof(Dia))
      dias[i] = lido;
  }
  memoria.end();
}

inline void gravar(uint8_t slot) {
  Preferences memoria;
  if (!memoria.begin("iot-hist", false)) return;
  char k[4];
  chave(slot, k);
  memoria.putBytes(k, &dias[slot], sizeof(Dia));
  memoria.end();
}

// Passa a hora acumulada para o dia dela e grava so esse dia.
inline void fechar() {
  const Acumulado& a = acumulado;
  if (!a.hora) return;
  const uint32_t dia = a.hora / 24;
  const uint8_t slot = dia % DIAS;
  if (dias[slot].dia != dia) {  // Dia novo ocupa o lugar do de 7 dias atras.
    dias[slot] = Dia();
    dias[slot].dia = dia;
  }
  Hora& h = dias[slot].horas[a.hora % 24];
  h = Hora();
  if (a.nCorrente) {
    h.correnteMedia = escalar(a.somaCorrente / a.nCorrente, 100);
    h.correnteMax = escalar(a.maxCorrente, 100);
  }
  if (a.nTensao) h.tensaoMedia = escalar(a.somaTensao / a.nTensao, 10);
  if (a.nTemperatura) {
    h.temperaturaMedia = escalar(a.somaTemperatura / a.nTemperatura, 10);
    h.temperaturaMax = escalar(a.maxTemperatura, 10);
  }
  if (a.nVibracao) {
    h.vibracaoMedia = escalar(a.somaVibracao / a.nVibracao, 1000);
    h.vibracaoMax = escalar(a.maxVibracao, 1000);
  }
  h.minutosLigado = static_cast<uint8_t>(min<uint32_t>(60, (a.segundosLigado + 30) / 60));
  h.usada = a.nCorrente || a.nTensao || a.nTemperatura || a.nVibracao || a.segundosLigado;
  gravar(slot);
  diaParaPublicar = slot;
}

// Uma amostra por segundo. Leituras invalidas vem como NAN.
inline void amostrar(uint32_t utc, bool ligado, float corrente, float tensao,
                     float temperatura, float vibracao) {
  if (!utc) return;
  const uint32_t hora = utc / 3600;
  if (acumulado.hora != hora) {
    fechar();
    acumulado = Acumulado();
    acumulado.hora = hora;
  }
  Acumulado& a = acumulado;
  if (ligado) ++a.segundosLigado;
  if (ligado && isfinite(corrente)) {
    a.somaCorrente += corrente; ++a.nCorrente; a.maxCorrente = max(a.maxCorrente, corrente);
  }
  if (isfinite(tensao)) { a.somaTensao += tensao; ++a.nTensao; }
  if (isfinite(temperatura)) {
    a.somaTemperatura += temperatura; ++a.nTemperatura; a.maxTemperatura = max(a.maxTemperatura, temperatura);
  }
  if (ligado && isfinite(vibracao)) {
    a.somaVibracao += vibracao; ++a.nVibracao; a.maxVibracao = max(a.maxVibracao, vibracao);
  }
}

// Um dia para o topico retido: so as horas com dado, uma linha por hora:
// [hora, corrente media, corrente max, tensao media, temperatura media,
//  temperatura max, vibracao media, vibracao max, minutos ligado]
// nas escalas acima; null = sem leitura.
inline void descrever(uint8_t slot, JsonDocument& doc) {
  doc["day"] = dias[slot].dia;
  doc["v"] = 1;
  JsonArray linhas = doc.createNestedArray("hours");
  if (!dias[slot].dia) return;
  for (uint8_t i = 0; i < 24; ++i) {
    const Hora& h = dias[slot].horas[i];
    if (!h.usada) continue;
    JsonArray linha = linhas.createNestedArray();
    linha.add(i);
    for (int16_t v : {h.correnteMedia, h.correnteMax, h.tensaoMedia, h.temperaturaMedia,
                      h.temperaturaMax, h.vibracaoMedia, h.vibracaoMax}) {
      if (v == VAZIO) linha.add(serialized("null"));
      else linha.add(v);
    }
    linha.add(h.minutosLigado);
  }
}

}  // namespace historico
