#pragma once
// A mesma versao do firmware publicado (publish-firmware.yml), em cabecalho
// unico baixado por rodar.sh para .cache/. Com String do Arduino de mentira.
#include "Arduino.h"
#define ARDUINOJSON_ENABLE_ARDUINO_STRING 1
#define ARDUINOJSON_ENABLE_ARDUINO_STREAM 0
#define ARDUINOJSON_ENABLE_ARDUINO_PRINT 0
#define ARDUINOJSON_ENABLE_PROGMEM 0
#include "../.cache/ArduinoJson-v6.21.5.h"

// No PC cada valor do JSON ocupa 32 bytes; no ESP32, 16 (ponteiros de 4 bytes).
// Para a logica rodar igual, os documentos do firmware ganham o dobro aqui.
// O orcamento real do ESP32 e conferido a parte por bytesNoEsp32().
constexpr size_t SLOT_PC = sizeof(ArduinoJson::detail::VariantSlot), SLOT_ESP32 = 16;
struct DocumentoDobrado : ArduinoJson::DynamicJsonDocument {
  explicit DocumentoDobrado(size_t n) : ArduinoJson::DynamicJsonDocument(n * SLOT_PC / SLOT_ESP32) {}
};
template <size_t N>
struct EstaticoDobrado : ArduinoJson::StaticJsonDocument<N * SLOT_PC / SLOT_ESP32> {};
// Documento do tamanho pedido, sem dobrar (para medir no PC).
using DocumentoPc = ArduinoJson::DynamicJsonDocument;
#define DynamicJsonDocument DocumentoDobrado
#define StaticJsonDocument EstaticoDobrado

// Quanto um documento montado no PC ocuparia no ESP32: o texto copiado e o
// mesmo; so os valores (slots) encolhem. 'texto' = bytes das strings copiadas.
inline size_t bytesNoEsp32(const ArduinoJson::JsonDocument& doc, size_t texto) {
  return (doc.memoryUsage() - texto) / SLOT_PC * SLOT_ESP32 + texto;
}
