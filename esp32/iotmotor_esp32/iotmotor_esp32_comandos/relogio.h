#pragma once
// Hora real das medicoes, por NTP.
//
// Sem isto a telemetria so tem sequencia e tempo desde o boot: um CSV
// exportado carrega a hora de quem exportou, nao a da medicao. Com a hora
// sincronizada, cada amostra sai carimbada em UTC (campo "ts", em segundos).
//
// A hora e pedida assim que a placa entra na rede e reconferida de hora em
// hora. Enquanto nao chega, o campo simplesmente nao aparece: ninguem publica
// uma hora inventada.
#include <Arduino.h>
#include <WiFi.h>
#include <time.h>

namespace relogio {

// Qualquer instante depois de 2024 serve para saber que o NTP respondeu.
constexpr time_t MINIMO_VALIDO = 1700000000;
constexpr uint32_t REPETIR_MS = 3600000UL;  // Confere de hora em hora.

inline uint32_t ultimoPedido = 0;
inline bool pedidoFeito = false;

inline bool valido() { return time(nullptr) > MINIMO_VALIDO; }

// Segundos desde 1970 em UTC, ou 0 enquanto a hora nao chegou.
inline uint32_t agoraUtc() {
  const time_t t = time(nullptr);
  return t > MINIMO_VALIDO ? (uint32_t)t : 0;
}

// Chamada no laco: pede a hora quando ha rede e ainda nao ha hora.
inline void manter(uint32_t agora) {
  if (WiFi.status() != WL_CONNECTED) return;
  const bool naHora = pedidoFeito && (agora - ultimoPedido) < REPETIR_MS;
  if (naHora && valido()) return;
  if (pedidoFeito && (agora - ultimoPedido) < 15000UL) return;  // Nao insiste.
  ultimoPedido = agora;
  pedidoFeito = true;
  configTime(0, 0, "a.st1.ntp.br", "pool.ntp.org", "time.google.com");
}

// Texto curto para o Serial e para as telas: 2026-09-20 16:45 UTC.
inline String texto() {
  const time_t t = time(nullptr);
  if (t <= MINIMO_VALIDO) return String("sem hora");
  struct tm utc;
  gmtime_r(&t, &utc);
  char buffer[24];
  strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M UTC", &utc);
  return String(buffer);
}

}  // namespace relogio
