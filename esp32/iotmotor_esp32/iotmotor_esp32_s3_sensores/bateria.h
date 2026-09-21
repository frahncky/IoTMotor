#pragma once
// Tensao da bateria 18650 que alimenta a placa pela fonte UPS.
//
// A fonte entrega 5 V regulados ate a celula chegar ao corte (2,6 V), entao
// medir a alimentacao da placa nao diz nada: ela le 5 V ate desligar de uma
// vez. Quem conta a historia e a tensao da propria celula, que precisa vir por
// um divisor resistivo, porque 4,2 V passam do limite do ADC.
//
//   BAT+ (terminal positivo do suporte) ---[ 100k ]---+---[ 100k ]--- GND
//                                                     |
//                                                   GPIO6   (+ 100 nF para GND)
//
// Com dois resistores iguais o pino le metade da tensao: 4,2 V viram 2,10 V e
// 3,0 V viram 1,50 V, dentro da faixa do ADC. O divisor consome ~21 uA, contra
// os ~2 mA que a propria fonte gasta parada.
//
// Sem o divisor ligado o pino fica proximo de zero: nesse caso a placa nao
// publica tensao nenhuma, em vez de inventar uma leitura.
#include <Arduino.h>
#include <math.h>

namespace bateria {

constexpr uint8_t PINO = 6;             // ADC1_CH5, livre nesta placa.
constexpr float DIVISOR = 2.0f;         // 100k + 100k: o pino le metade.
constexpr float MINIMO_VALIDO = 1.20f;  // Abaixo disso: nada ligado no pino.
constexpr float MAXIMO_VALIDO = 5.00f;  // Acima disso: divisor errado.
constexpr uint32_t INTERVALO_MS = 5000;
constexpr uint8_t AMOSTRAS = 16;        // Media simples tira o ruido do ADC.

inline float tensao = NAN;
inline uint32_t ultimaLeitura = 0;

inline void iniciar() {
  analogSetPinAttenuation(PINO, ADC_11db);  // Faixa util ate ~3,1 V no pino.
}

inline void medir(uint32_t agora) {
  if (ultimaLeitura && (uint32_t)(agora - ultimaLeitura) < INTERVALO_MS) return;
  ultimaLeitura = agora;
  uint32_t soma = 0;
  for (uint8_t i = 0; i < AMOSTRAS; ++i) soma += analogReadMilliVolts(PINO);
  const float lido = (soma / (float)AMOSTRAS) / 1000.0f * DIVISOR;
  tensao = (lido >= MINIMO_VALIDO && lido <= MAXIMO_VALIDO) ? lido : NAN;
}

inline bool valida() { return isfinite(tensao); }

}  // namespace bateria
