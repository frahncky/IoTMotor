#pragma once
// NVS de mentira: um mapa em memoria, compartilhado por todas as instancias,
// como a flash de verdade. prefsFalsas::apagar() simula uma placa nova.
#include <map>
#include <string>
#include "Arduino.h"

namespace prefsFalsas {
inline std::map<std::string, std::string> dados;
inline void apagar() { dados.clear(); }
}  // namespace prefsFalsas

class Preferences {
 public:
  bool begin(const char* nome, bool = false) { ns_ = nome; return true; }
  void end() {}
  String getString(const char* chave, const char* padrao = "") {
    auto it = prefsFalsas::dados.find(ns_ + "/" + chave);
    return it == prefsFalsas::dados.end() ? String(padrao) : String(it->second);
  }
  size_t putString(const char* chave, const String& valor) {
    prefsFalsas::dados[ns_ + "/" + chave] = valor.c_str();
    return valor.length();
  }
  bool getBool(const char* chave, bool padrao = false) {
    auto it = prefsFalsas::dados.find(ns_ + "/" + chave);
    return it == prefsFalsas::dados.end() ? padrao : it->second == "1";
  }
  size_t putBool(const char* chave, bool valor) {
    prefsFalsas::dados[ns_ + "/" + chave] = valor ? "1" : "0";
    return 1;
  }
  bool remove(const char* chave) { return prefsFalsas::dados.erase(ns_ + "/" + chave) > 0; }

 private:
  std::string ns_;
};
