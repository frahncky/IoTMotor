#pragma once
// Diagnostico da vibracao na telemetria (deteccao e classificacao de falhas):
// "vib":{"x":{"mms":..,"a_rms":..,"a_peak":..,"crest":..,"kurt":..,
// "pk_hz":..,"pk_mms":..,"bands":[17 faixas de 10 Hz, 20 a 180 Hz]},...}
// Separado do .ino para os testes nativos conferirem o tamanho da mensagem.
#include <ArduinoJson.h>
#include <math.h>
#include "vibracao.h"

namespace vibracaojson {

// Espaco no JsonDocument para o objeto "vib" completo (3 eixos com espectro).
constexpr size_t TAMANHO_DOC =
    JSON_OBJECT_SIZE(3) + 3 * (JSON_OBJECT_SIZE(8) + JSON_ARRAY_SIZE(vibracao::NUM_FAIXAS));

// 3 casas bastam (mm/s, m/s^2, Hz) e encurtam a mensagem: o float sairia com 9.
inline double r3(float x) { return round(static_cast<double>(x) * 1000.0) / 1000.0; }

inline void descrever(JsonObject vib) {
  // Literais: o ArduinoJson guarda so o ponteiro de um const char*.
  static const char* const EIXOS[3] = {"x", "y", "z"};
  for (uint8_t i = 0; i < 3; ++i) {
    JsonObject e = vib.createNestedObject(EIXOS[i]);
    e["mms"] = r3(vibracao::mmSEixo[i]);
    e["a_rms"] = r3(vibracao::aRms[i]);
    e["a_peak"] = r3(vibracao::aPico[i]);
    e["crest"] = r3(vibracao::crista[i]);
    e["kurt"] = r3(vibracao::curtose[i]);
    if (!vibracao::espectroValido) continue;
    e["pk_hz"] = r3(vibracao::picoHz[i]);
    e["pk_mms"] = r3(vibracao::picoMmS[i]);
    JsonArray faixas = e.createNestedArray("bands");
    for (uint8_t f = 0; f < vibracao::NUM_FAIXAS; ++f) faixas.add(r3(vibracao::faixas[i][f]));
  }
}

}  // namespace vibracaojson
