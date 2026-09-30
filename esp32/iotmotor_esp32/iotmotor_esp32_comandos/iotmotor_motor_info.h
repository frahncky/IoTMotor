#pragma once
// Dados de placa do motor (monofasico ou trifasico, com uma ou duas tensoes,
// potencia em cv) e contadores de uso (horimetro e partidas),
// gravados nesta placa: o painel e o app leem os mesmos valores, e eles
// sobrevivem a reinicio. Todos os dados de placa sao opcionais (0 = nao
// cadastrado); sem a corrente nominal o painel apenas nao mostra a carga.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <Preferences.h>

namespace motorinfo {

struct Dados {
  float potenciaCv = 0;
  float tensaoV = 0;
  float correnteA = 0;
  float fatorServico = 0;
  float frequenciaHz = 0;
  float fatorPotencia = 0;
  float rendimentoPct = 0;
  float ambienteC = 0;
  float elevacaoK = 0;
  uint16_t rpm = 0;
  uint8_t fases = 0;  // 1 = monofasico, 3 = trifasico, 0 = nao informado.
  // Trifasico de dupla tensao (ex.: 220/380 V - 12,6/7,3 A): tensaoV e
  // correnteA sao os da ligacao triangulo (menor tensao), estes os da
  // estrela. 0 = placa com uma tensao so.
  float tensaoEstrelaV = 0;
  float correnteEstrelaA = 0;
  bool emEstrela = false;  // Ligacao em que o motor trabalha (padrao: triangulo).
  char classeRendimento[4] = "";  // IE1 a IE5.
  char regime[4] = "";            // S1 a S10.
  char classeIsolacao[3] = "";    // A, E, B, F, H, N ou R.
  char grauIp[8] = "";
  char fabricante[41] = "";
  char modelo[41] = "";
  char numeroSerie[33] = "";
  uint32_t manutencaoH = 0;  // Manutencao a cada tantas horas de uso (0 = sem lembrete).
};

inline Dados dados;

// Contadores. O dia e o numero de dias desde 1970 no horario de Brasilia
// (UTC-3); 0 enquanto o relogio nao sincroniza.
inline uint32_t segundosLigado = 0;
inline uint32_t partidas = 0;
inline uint32_t partidasHoje = 0;
inline uint32_t diaDasPartidas = 0;

// Ultima manutencao: o horimetro naquele momento e a data (0 = sem registro).
inline uint32_t manutencaoEmS = 0;
inline uint32_t manutencaoUtc = 0;

// Instantes (millis) das ultimas partidas, para contar as da ultima hora:
// partidas seguidas aquecem o enrolamento.
constexpr uint8_t MAX_PARTIDAS_HORA = 60;
inline unsigned long partidasRecentes[MAX_PARTIDAS_HORA];
inline uint8_t totalRecentes = 0;

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
  dados.potenciaCv = memoria.getFloat("cv", 0);
  dados.tensaoV = memoria.getFloat("v", 0);
  dados.correnteA = memoria.getFloat("a", 0);
  dados.fatorServico = memoria.getFloat("fs", 0);
  dados.frequenciaHz = memoria.getFloat("freq", 0);
  dados.fatorPotencia = memoria.getFloat("fp", 0);
  dados.rendimentoPct = memoria.getFloat("rend", 0);
  dados.ambienteC = memoria.getFloat("amb_c", 0);
  dados.elevacaoK = memoria.getFloat("elev_k", 0);
  dados.rpm = memoria.getUShort("rpm", 0);
  dados.fases = memoria.getUChar("fases", 0);
  dados.tensaoEstrelaV = memoria.getFloat("vy", 0);
  dados.correnteEstrelaA = memoria.getFloat("ay", 0);
  dados.emEstrela = memoria.getBool("estrela", false);
  memoria.getString("ie", dados.classeRendimento, sizeof(dados.classeRendimento));
  memoria.getString("regime", dados.regime, sizeof(dados.regime));
  memoria.getString("isol", dados.classeIsolacao, sizeof(dados.classeIsolacao));
  memoria.getString("ip", dados.grauIp, sizeof(dados.grauIp));
  memoria.getString("fabric", dados.fabricante, sizeof(dados.fabricante));
  memoria.getString("modelo", dados.modelo, sizeof(dados.modelo));
  memoria.getString("serie", dados.numeroSerie, sizeof(dados.numeroSerie));
  dados.manutencaoH = memoria.getUInt("manut_h", 0);
  manutencaoEmS = memoria.getUInt("manut_s", 0);
  manutencaoUtc = memoria.getUInt("manut_utc", 0);
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
    if (totalRecentes == MAX_PARTIDAS_HORA) {  // Fila cheia: a mais antiga sai.
      for (uint8_t i = 0; i + 1 < MAX_PARTIDAS_HORA; ++i) partidasRecentes[i] = partidasRecentes[i + 1];
      --totalRecentes;
    }
    partidasRecentes[totalRecentes++] = agora;
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

// Partidas nos ultimos 60 minutos (so desde que a placa ligou).
inline uint8_t partidasNaUltimaHora(unsigned long agora) {
  uint8_t n = 0;
  for (uint8_t i = 0; i < totalRecentes; ++i)
    if (agora - partidasRecentes[i] < 3600000UL) ++n;
  return n;
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
  auto lerTexto = [&](const char* campo, char* saida, size_t capacidade) {
    JsonVariantConst v = doc[campo];
    if (v.isNull()) { saida[0] = '\0'; return true; }
    if (!v.is<const char*>()) return false;
    const char* texto = v.as<const char*>();
    const size_t tamanho = strlen(texto);
    if (!tamanho || tamanho >= capacidade) return false;
    for (size_t i = 0; i < tamanho; ++i)
      if (static_cast<uint8_t>(texto[i]) < 32) return false;
    strlcpy(saida, texto, capacidade);
    return true;
  };
  Dados novo;
  float rpm = 0;
  if (!ler("power_cv", 3000, novo.potenciaCv)) { motivo = "potencia: use de 0 a 3000 cv"; return false; }
  if (!ler("voltage_v", 1000, novo.tensaoV)) { motivo = "tensao: use de 0 a 1000 V"; return false; }
  if (!ler("current_a", 2000, novo.correnteA)) { motivo = "corrente: use de 0 a 2000 A"; return false; }
  if (!ler("rpm", 10000, rpm)) { motivo = "rotacao: use de 0 a 10000 rpm"; return false; }
  if (!ler("service_factor", 3, novo.fatorServico) ||
      (novo.fatorServico > 0 && novo.fatorServico < 1)) {
    motivo = "fator de servico: use de 1 a 3 (ou vazio)";
    return false;
  }
  if (!ler("frequency_hz", 1000, novo.frequenciaHz)) { motivo = "frequencia: use de 0 a 1000 Hz"; return false; }
  if (!ler("power_factor", 1, novo.fatorPotencia)) { motivo = "fator de potencia: use de 0 a 1"; return false; }
  if (!ler("efficiency_pct", 100, novo.rendimentoPct)) { motivo = "rendimento: use de 0 a 100%"; return false; }
  if (!ler("ambient_temp_c", 100, novo.ambienteC)) { motivo = "temperatura ambiente: use de 0 a 100 C"; return false; }
  if (!ler("temperature_rise_k", 250, novo.elevacaoK)) { motivo = "elevacao termica: use de 0 a 250 K"; return false; }
  if (!lerTexto("efficiency_class", novo.classeRendimento, sizeof(novo.classeRendimento)) && !doc["efficiency_class"].isNull()) {
    motivo = "classe de rendimento invalida"; return false;
  }
  if (novo.classeRendimento[0] && (strncmp(novo.classeRendimento, "IE", 2) || novo.classeRendimento[2] < '1' || novo.classeRendimento[2] > '5')) {
    motivo = "classe de rendimento: use IE1 a IE5"; return false;
  }
  if (!lerTexto("duty", novo.regime, sizeof(novo.regime)) && !doc["duty"].isNull()) { motivo = "regime invalido"; return false; }
  if (novo.regime[0] &&
      (novo.regime[0] != 'S' || atoi(novo.regime + 1) < 1 || atoi(novo.regime + 1) > 10 ||
       (atoi(novo.regime + 1) < 10 && novo.regime[2]))) {
    motivo = "regime: use S1 a S10"; return false;
  }
  if (!lerTexto("insulation_class", novo.classeIsolacao, sizeof(novo.classeIsolacao)) && !doc["insulation_class"].isNull()) {
    motivo = "classe de isolacao invalida"; return false;
  }
  if (novo.classeIsolacao[0] &&
      (novo.classeIsolacao[1] || !strchr("AEBFHNR", novo.classeIsolacao[0]))) {
    motivo = "classe de isolacao: use A, E, B, F, H, N ou R"; return false;
  }
  if (!lerTexto("ip_rating", novo.grauIp, sizeof(novo.grauIp)) && !doc["ip_rating"].isNull()) { motivo = "grau IP invalido"; return false; }
  if (novo.grauIp[0] &&
      (strncmp(novo.grauIp, "IP", 2) || strlen(novo.grauIp) < 4 ||
       novo.grauIp[2] < '0' || novo.grauIp[2] > '9' ||
       novo.grauIp[3] < '0' || novo.grauIp[3] > '9')) {
    motivo = "grau de protecao: use formato IP55"; return false;
  }
  if (!lerTexto("manufacturer", novo.fabricante, sizeof(novo.fabricante)) && !doc["manufacturer"].isNull()) { motivo = "fabricante: use ate 40 caracteres"; return false; }
  if (!lerTexto("model", novo.modelo, sizeof(novo.modelo)) && !doc["model"].isNull()) { motivo = "modelo: use ate 40 caracteres"; return false; }
  if (!lerTexto("serial_number", novo.numeroSerie, sizeof(novo.numeroSerie)) && !doc["serial_number"].isNull()) { motivo = "numero de serie: use ate 32 caracteres"; return false; }
  float fases = 0;
  if (!ler("phases", 3, fases) || (fases != 0 && fases != 1 && fases != 3)) {
    motivo = "fases: use 1 (monofasico) ou 3 (trifasico)";
    return false;
  }
  novo.fases = static_cast<uint8_t>(fases);
  // Segunda tensao/corrente (estrela): so em trifasico, e coerente com a
  // placa: tensao maior e corrente menor que as do triangulo.
  if (!ler("voltage_y_v", 1000, novo.tensaoEstrelaV) || !ler("current_y_a", 2000, novo.correnteEstrelaA)) {
    motivo = "estrela: tensao de 0 a 1000 V e corrente de 0 a 2000 A";
    return false;
  }
  const bool duplaTensao = novo.tensaoEstrelaV > 0 || novo.correnteEstrelaA > 0;
  if (duplaTensao && novo.fases != 3) { motivo = "duas tensoes so em motor trifasico"; return false; }
  if (novo.tensaoEstrelaV > 0 && !(novo.tensaoV > 0 && novo.tensaoEstrelaV > novo.tensaoV)) {
    motivo = "tensao: informe a menor (triangulo) e depois a maior (estrela)";
    return false;
  }
  if (novo.correnteEstrelaA > 0 && !(novo.correnteA > 0 && novo.correnteEstrelaA < novo.correnteA)) {
    motivo = "corrente: informe a maior (triangulo) e depois a menor (estrela)";
    return false;
  }
  JsonVariantConst ligacao = doc["connection"];
  if (!ligacao.isNull() && ligacao != "delta" && ligacao != "star") {
    motivo = "ligacao: use delta ou star";
    return false;
  }
  novo.emEstrela = duplaTensao && ligacao == "star";
  float manutencao = 0;
  if (!ler("maint_interval_h", 100000, manutencao)) { motivo = "manutencao: use de 0 a 100000 h"; return false; }
  novo.manutencaoH = static_cast<uint32_t>(manutencao + 0.5f);
  novo.rpm = static_cast<uint16_t>(rpm + 0.5f);
  Preferences memoria;
  if (!memoria.begin("iot-motor", false)) { motivo = "falha ao gravar"; return false; }
  memoria.putFloat("cv", novo.potenciaCv);
  memoria.putFloat("v", novo.tensaoV);
  memoria.putFloat("a", novo.correnteA);
  memoria.putFloat("fs", novo.fatorServico);
  memoria.putFloat("freq", novo.frequenciaHz);
  memoria.putFloat("fp", novo.fatorPotencia);
  memoria.putFloat("rend", novo.rendimentoPct);
  memoria.putFloat("amb_c", novo.ambienteC);
  memoria.putFloat("elev_k", novo.elevacaoK);
  memoria.putUShort("rpm", novo.rpm);
  memoria.putUChar("fases", novo.fases);
  memoria.putFloat("vy", novo.tensaoEstrelaV);
  memoria.putFloat("ay", novo.correnteEstrelaA);
  memoria.putBool("estrela", novo.emEstrela);
  memoria.putString("ie", novo.classeRendimento);
  memoria.putString("regime", novo.regime);
  memoria.putString("isol", novo.classeIsolacao);
  memoria.putString("ip", novo.grauIp);
  memoria.putString("fabric", novo.fabricante);
  memoria.putString("modelo", novo.modelo);
  memoria.putString("serie", novo.numeroSerie);
  memoria.putUInt("manut_h", novo.manutencaoH);
  memoria.end();
  dados = novo;
  motivo = "dados do motor gravados";
  return true;
}

// Grava o horimetro e a data da ultima manutencao.
inline void gravarManutencao() {
  Preferences memoria;
  if (!memoria.begin("iot-motor", false)) return;
  memoria.putUInt("manut_s", manutencaoEmS);
  memoria.putUInt("manut_utc", manutencaoUtc);
  memoria.end();
}

// "Manutencao feita": o proximo lembrete conta a partir do horimetro atual.
inline void registrarManutencao(uint32_t utc) {
  manutencaoEmS = segundosLigado;
  manutencaoUtc = utc;
  gravarManutencao();
}

// Zera horimetro e partidas (troca de motor). So com o motor parado.
inline void zerarContadores() {
  segundosLigado = 0;
  partidas = 0;
  partidasHoje = 0;
  restoMs = 0;
  totalRecentes = 0;
  gravarContadores();
  // Motor novo: a contagem da manutencao recomeca junto com o horimetro.
  manutencaoEmS = 0;
  manutencaoUtc = 0;
  gravarManutencao();
}

// O NVS guarda estes campos como float de 32 bits. Valores decimais como
// 1,35 podem existir internamente como 1,350000024; antes de publicar, convertemos
// para double arredondado para que MQTT/painel/app recebam o valor humano esperado.
inline double decimalPublicado(float valor, uint8_t casas) {
  const double escala = casas == 2 ? 100.0 : 1000.0;
  return round(static_cast<double>(valor) * escala) / escala;
}

// Dados de placa para o topico retido "motor_info" (0 = nao cadastrado).
inline void descrever(JsonDocument& doc) {
  if (dados.potenciaCv > 0) doc["power_cv"] = decimalPublicado(dados.potenciaCv, 3);
  if (dados.tensaoV > 0) doc["voltage_v"] = decimalPublicado(dados.tensaoV, 3);
  if (dados.correnteA > 0) doc["current_a"] = decimalPublicado(dados.correnteA, 3);
  if (dados.rpm > 0) doc["rpm"] = dados.rpm;
  if (dados.fatorServico > 0) doc["service_factor"] = decimalPublicado(dados.fatorServico, 2);
  if (dados.frequenciaHz > 0) doc["frequency_hz"] = decimalPublicado(dados.frequenciaHz, 3);
  if (dados.fatorPotencia > 0) doc["power_factor"] = decimalPublicado(dados.fatorPotencia, 3);
  if (dados.rendimentoPct > 0) doc["efficiency_pct"] = decimalPublicado(dados.rendimentoPct, 3);
  if (dados.ambienteC > 0) doc["ambient_temp_c"] = decimalPublicado(dados.ambienteC, 2);
  if (dados.elevacaoK > 0) doc["temperature_rise_k"] = decimalPublicado(dados.elevacaoK, 2);
  if (dados.classeRendimento[0]) doc["efficiency_class"] = dados.classeRendimento;
  if (dados.regime[0]) doc["duty"] = dados.regime;
  if (dados.classeIsolacao[0]) doc["insulation_class"] = dados.classeIsolacao;
  if (dados.grauIp[0]) doc["ip_rating"] = dados.grauIp;
  if (dados.fabricante[0]) doc["manufacturer"] = dados.fabricante;
  if (dados.modelo[0]) doc["model"] = dados.modelo;
  if (dados.numeroSerie[0]) doc["serial_number"] = dados.numeroSerie;
  if (dados.fases) doc["phases"] = dados.fases;
  if (dados.tensaoEstrelaV > 0) doc["voltage_y_v"] = decimalPublicado(dados.tensaoEstrelaV, 3);
  if (dados.correnteEstrelaA > 0) doc["current_y_a"] = decimalPublicado(dados.correnteEstrelaA, 3);
  if (dados.tensaoEstrelaV > 0 || dados.correnteEstrelaA > 0)
    doc["connection"] = dados.emEstrela ? "star" : "delta";
  if (dados.manutencaoH) {
    doc["maint_interval_h"] = dados.manutencaoH;
    doc["maint_done_run_s"] = manutencaoEmS;
  }
  if (manutencaoUtc) doc["maint_done_utc"] = manutencaoUtc;
}

}  // namespace motorinfo
