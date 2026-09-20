#pragma once
// Lista de alarmes gravada na placa (NVS), editada pelo painel.
//
// Cada alarme diz de onde vem a grandeza, qual e ela, se dispara acima ou
// abaixo do limite, e o limite. As grandezas do quadro de comando (tensao,
// corrente, potencia...) chegam pela telemetria do outro ESP32, que esta placa
// assina; as de vibracao e temperatura sao medidas aqui mesmo.
//
// Um alarme so vale com leitura recente: valor velho nao dispara nem silencia.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <Preferences.h>

namespace alarmes {

constexpr uint8_t MAX_ALARMES = 8;
constexpr size_t MAX_ID_ALARME = 12;
constexpr size_t MAX_CAMPO = 16;
constexpr uint32_t VALIDADE_MS = 15000;  // Leitura mais velha que isso e ignorada.

struct Alarme {
  char id[MAX_ID_ALARME + 1] = "";
  char campo[MAX_CAMPO + 1] = "";  // voltage, current, power, vibration, temperature...
  bool doQuadro = false;           // true = vem do ESP32 de comandos.
  bool acima = true;               // true = dispara acima do limite.
  float limite = 0;
  bool habilitado = true;
  bool disparado = false;          // Estado atual, nao gravado.
};

inline Alarme lista[MAX_ALARMES];
inline uint8_t total = 0;

// Ultimos valores recebidos do quadro de comando, com o instante da leitura.
inline StaticJsonDocument<512> medidasDoQuadro;
inline uint32_t medidasDoQuadroEm = 0;

inline int indiceDe(const char* id) {
  for (uint8_t i = 0; i < total; ++i)
    if (!strcmp(lista[i].id, id)) return i;
  return -1;
}

inline void gravar() {
  StaticJsonDocument<1536> doc;
  JsonArray array = doc.to<JsonArray>();
  for (uint8_t i = 0; i < total; ++i) {
    JsonObject item = array.createNestedObject();
    item["id"] = lista[i].id;
    item["field"] = lista[i].campo;
    item["board"] = lista[i].doQuadro ? "command" : "sensors";
    item["above"] = lista[i].acima;
    item["limit"] = lista[i].limite;
    item["on"] = lista[i].habilitado;
  }
  String texto;
  serializeJson(doc, texto);
  Preferences memoria;
  if (!memoria.begin("iot-alarmes", false)) return;
  memoria.putString("lista", texto);
  memoria.end();
}

inline bool lerDeJson(JsonVariantConst origem, Alarme& destino) {
  const char* id = origem["id"] | "";
  const char* campo = origem["field"] | "";
  if (!id[0] || strlen(id) > MAX_ID_ALARME || !campo[0] || strlen(campo) > MAX_CAMPO) return false;
  if (!origem["limit"].is<float>()) return false;
  strncpy(destino.id, id, MAX_ID_ALARME);
  destino.id[MAX_ID_ALARME] = '\0';
  strncpy(destino.campo, campo, MAX_CAMPO);
  destino.campo[MAX_CAMPO] = '\0';
  destino.doQuadro = !strcmp(origem["board"] | "sensors", "command");
  destino.acima = origem["above"] | true;
  destino.limite = origem["limit"].as<float>();
  destino.habilitado = origem["on"] | true;
  destino.disparado = false;
  return isfinite(destino.limite);
}

inline bool salvar(JsonVariantConst origem, const char*& motivo) {
  Alarme alarme;
  if (!lerDeJson(origem, alarme)) {
    motivo = "alarme invalido: confira grandeza e limite";
    return false;
  }
  const int existente = indiceDe(alarme.id);
  if (existente >= 0) {
    alarme.disparado = lista[existente].disparado;
    lista[existente] = alarme;
  } else {
    if (total >= MAX_ALARMES) {
      motivo = "limite de alarmes atingido";
      return false;
    }
    lista[total++] = alarme;
  }
  gravar();
  motivo = existente >= 0 ? "alarme atualizado" : "alarme criado";
  return true;
}

inline bool remover(const char* id, const char*& motivo) {
  const int i = indiceDe(id ? id : "");
  if (i < 0) {
    motivo = "alarme nao encontrado";
    return false;
  }
  for (uint8_t j = i; j + 1 < total; ++j) lista[j] = lista[j + 1];
  --total;
  gravar();
  motivo = "alarme removido";
  return true;
}

// Alarmes iniciais: os mesmos limites que a placa usava antes da lista.
inline void semear(float vibracao, float temperatura) {
  total = 0;
  Alarme vib;
  strcpy(vib.id, "vib");
  strcpy(vib.campo, "vibration_peak");
  vib.limite = vibracao;
  lista[total++] = vib;
  Alarme temp;
  strcpy(temp.id, "temp");
  strcpy(temp.campo, "temperature");
  temp.limite = temperatura;
  lista[total++] = temp;
  gravar();
}

inline void carregar(float vibracaoPadrao, float temperaturaPadrao) {
  Preferences memoria;
  String texto;
  if (memoria.begin("iot-alarmes", true)) {
    texto = memoria.getString("lista", "");
    memoria.end();
  }
  total = 0;
  if (texto.length()) {
    StaticJsonDocument<1536> doc;
    if (!deserializeJson(doc, texto)) {
      for (JsonVariantConst item : doc.as<JsonArrayConst>()) {
        if (total >= MAX_ALARMES) break;
        Alarme alarme;
        if (lerDeJson(item, alarme)) lista[total++] = alarme;
      }
    }
  }
  if (!total) semear(vibracaoPadrao, temperaturaPadrao);
  Serial.printf("[ALARMES] %u na placa\n", total);
}

// Guarda a telemetria do quadro de comando para os alarmes eletricos.
inline void receberMedidasDoQuadro(const uint8_t* payload, unsigned int tamanho, uint32_t agora) {
  StaticJsonDocument<1024> entrada;
  if (deserializeJson(entrada, payload, tamanho)) return;
  medidasDoQuadro.clear();
  for (const char* campo : {"voltage", "current", "power", "energy", "frequency", "pf"})
    if (entrada[campo].is<float>()) medidasDoQuadro[campo] = entrada[campo].as<float>();
  medidasDoQuadroEm = agora;
}

// Valor atual de um campo, se houver leitura valida e recente.
inline bool valorDe(const Alarme& alarme, uint32_t agora, bool mpuOk, bool tempOk,
                    float vibracaoRms, float vibracaoPico, float temperatura, float& saida) {
  if (alarme.doQuadro) {
    if (!medidasDoQuadroEm || agora - medidasDoQuadroEm > VALIDADE_MS) return false;
    if (!medidasDoQuadro[alarme.campo].is<float>()) return false;
    saida = medidasDoQuadro[alarme.campo].as<float>();
    return true;
  }
  if (!strcmp(alarme.campo, "vibration_peak") || !strcmp(alarme.campo, "vibration")) {
    if (!mpuOk) return false;
    saida = !strcmp(alarme.campo, "vibration") ? vibracaoRms : vibracaoPico;
    return true;
  }
  if (!strcmp(alarme.campo, "temperature")) {
    if (!tempOk) return false;
    saida = temperatura;
    return true;
  }
  return false;
}

// Avalia todos e devolve true se algum disparou.
inline bool avaliar(uint32_t agora, bool mpuOk, bool tempOk, float vibracaoRms,
                    float vibracaoPico, float temperatura) {
  bool algum = false;
  for (uint8_t i = 0; i < total; ++i) {
    Alarme& a = lista[i];
    float valor = 0;
    a.disparado = a.habilitado &&
                  valorDe(a, agora, mpuOk, tempOk, vibracaoRms, vibracaoPico, temperatura, valor) &&
                  (a.acima ? valor > a.limite : valor < a.limite);
    algum = algum || a.disparado;
  }
  return algum;
}

inline void descrever(JsonDocument& doc) {
  JsonArray array = doc.createNestedArray("alarms");
  for (uint8_t i = 0; i < total; ++i) {
    JsonObject item = array.createNestedObject();
    item["id"] = lista[i].id;
    item["field"] = lista[i].campo;
    item["board"] = lista[i].doQuadro ? "command" : "sensors";
    item["above"] = lista[i].acima;
    item["limit"] = lista[i].limite;
    item["on"] = lista[i].habilitado;
    item["firing"] = lista[i].disparado;
  }
  doc["max"] = MAX_ALARMES;
}

}  // namespace alarmes
