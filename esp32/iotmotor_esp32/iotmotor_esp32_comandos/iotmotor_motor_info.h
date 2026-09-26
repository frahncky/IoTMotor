#pragma once
// Dados de placa do motor e contadores de uso (horimetro e partidas),
// gravados nesta placa: o painel e o app leem os mesmos valores, e eles
// sobrevivem a reinicio. Todos os dados de placa sao opcionais (0 = nao
// cadastrado); sem a corrente nominal o painel apenas nao mostra a carga.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <Preferences.h>

namespace motorinfo {

struct Dados {
  float potenciaKw = 0;
  float tensaoV = 0;
  float correnteA = 0;
  float fatorServico = 0;
  uint16_t rpm = 0;
};

inline Dados dados;

// Contadores. O dia e o numero de dias desde 1970 no horario de Brasilia
// (UTC-3); 0 enquanto o relogio nao sincroniza.
inline uint32_t segundosLigado = 0;
inline uint32_t partidas = 0;
inline uint32_t partidasHoje = 0;
inline uint32_t diaDasPartidas = 0;

inline bool girando = false;
inline unsigned long inicioSessao = 0;
inline unsigned long ultimoTique = 0;
inline uint32_t restoMs = 0;
inline uint32_t segundosSemGravar = 0;
// Gravar a cada 10 min ligado (alem de a cada parada) poupa a flash e perde
// no maximo esse tempo numa queda de energia.
constexpr uint32_t GRAVAR_A_CADA_S = 600;

inline void carregar() {
  Preferences memoria;
  if (!memoria.begin("iot-motor", true)) return;
  dados.potenciaKw = memoria.getFloat("kw", 0);
  dados.tensaoV = memoria.getFloat("v", 0);
  dados.correnteA = memoria.getFloat("a", 0);
  dados.fatorServico = memoria.getFloat("fs", 0);
  dados.rpm = memoria.getUShort("rpm", 0);
  segundosLigado = memoria.getUInt("horas_s", 0);
  partidas = memoria.getUInt("partidas", 0);
  partidasHoje = memoria.getUInt("hoje", 0);
  diaDasPartidas = memoria.getUInt("dia", 0);
  memoria.end();
}

inline void gravarContadores() {
  Preferences memoria;
  if (!memoria.begin("iot-motor", false)) return;
  memoria.putUInt("horas_s", segundosLigado);
  memoria.putUInt("partidas", partidas);
  memoria.putUInt("hoje", partidasHoje);
  memoria.putUInt("dia", diaDasPartidas);
  memoria.end();
  segundosSemGravar = 0;
}

inline uint32_t diaDeHoje(uint32_t utc) {
  return utc ? (utc - 3UL * 3600UL) / 86400UL : 0;
}

// Troca de dia zera as partidas de hoje (so quando o relogio sabe o dia).
inline void conferirDia(uint32_t utc) {
  const uint32_t hoje = diaDeHoje(utc);
  if (hoje && hoje != diaDasPartidas) {
    diaDasPartidas = hoje;
    partidasHoje = 0;
  }
}

// Chamada a cada volta do loop com o estado atual do motor.
inline void manter(unsigned long agora, bool ligado, uint32_t utc) {
  conferirDia(utc);
  if (ligado && !girando) {
    girando = true;
    inicioSessao = agora;
    ultimoTique = agora;
    restoMs = 0;
    ++partidas;
    ++partidasHoje;
    gravarContadores();
    return;
  }
  if (!ligado) {
    if (girando) {
      girando = false;
      gravarContadores();
    }
    return;
  }
  restoMs += static_cast<uint32_t>(agora - ultimoTique);
  ultimoTique = agora;
  while (restoMs >= 1000) {
    restoMs -= 1000;
    ++segundosLigado;
    ++segundosSemGravar;
  }
  if (segundosSemGravar >= GRAVAR_A_CADA_S) gravarContadores();
}

inline uint32_t segundosDaSessao(unsigned long agora) {
  return girando ? static_cast<uint32_t>(agora - inicioSessao) / 1000UL : 0;
}

// Aceita os dados de placa vindos do painel/app. Campo ausente ou 0 = nao
// cadastrado; valores fora da faixa recusam o pedido inteiro.
inline bool salvar(JsonVariantConst doc, const char*& motivo) {
  auto ler = [&](const char* campo, float maximo, float& saida) {
    JsonVariantConst v = doc[campo];
    if (v.isNull()) { saida = 0; return true; }
    if (!v.is<float>()) return false;
    const float n = v.as<float>();
    if (!isfinite(n) || n < 0 || n > maximo) return false;
    saida = n;
    return true;
  };
  Dados novo;
  float rpm = 0;
  if (!ler("power_kw", 2000, novo.potenciaKw)) { motivo = "potencia: use de 0 a 2000 kW"; return false; }
  if (!ler("voltage_v", 1000, novo.tensaoV)) { motivo = "tensao: use de 0 a 1000 V"; return false; }
  if (!ler("current_a", 2000, novo.correnteA)) { motivo = "corrente: use de 0 a 2000 A"; return false; }
  if (!ler("rpm", 10000, rpm)) { motivo = "rotacao: use de 0 a 10000 rpm"; return false; }
  if (!ler("service_factor", 3, novo.fatorServico) ||
      (novo.fatorServico > 0 && novo.fatorServico < 1)) {
    motivo = "fator de servico: use de 1 a 3 (ou vazio)";
    return false;
  }
  novo.rpm = static_cast<uint16_t>(rpm + 0.5f);
  Preferences memoria;
  if (!memoria.begin("iot-motor", false)) { motivo = "falha ao gravar"; return false; }
  memoria.putFloat("kw", novo.potenciaKw);
  memoria.putFloat("v", novo.tensaoV);
  memoria.putFloat("a", novo.correnteA);
  memoria.putFloat("fs", novo.fatorServico);
  memoria.putUShort("rpm", novo.rpm);
  memoria.end();
  dados = novo;
  motivo = "dados do motor gravados";
  return true;
}

// Zera horimetro e partidas (troca de motor). So com o motor parado.
inline void zerarContadores() {
  segundosLigado = 0;
  partidas = 0;
  partidasHoje = 0;
  restoMs = 0;
  gravarContadores();
}

// Dados de placa para o topico retido "motor_info" (0 = nao cadastrado).
inline void descrever(JsonDocument& doc) {
  if (dados.potenciaKw > 0) doc["power_kw"] = dados.potenciaKw;
  if (dados.tensaoV > 0) doc["voltage_v"] = dados.tensaoV;
  if (dados.correnteA > 0) doc["current_a"] = dados.correnteA;
  if (dados.rpm > 0) doc["rpm"] = dados.rpm;
  if (dados.fatorServico > 0) doc["service_factor"] = dados.fatorServico;
}

}  // namespace motorinfo
