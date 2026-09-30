// Vibracao RMS em mm/s (vibracao.h), com o filtro e a integral reais do
// firmware. Uma senoide conhecida entra como se viesse da FIFO do MPU6050 e a
// velocidade que sai tem de bater com a conta feita a mao (docs/vibracao.md).
#include "teste.h"
#include "Arduino.h"
#include "../iotmotor_esp32/iotmotor_esp32_s3_sensores/vibracao.h"
#include "../iotmotor_esp32/iotmotor_esp32_s3_sensores/vibracao_json.h"
#include <string>

// Uma amostra de 6 bytes da FIFO (+/-4 g), como o MPU6050 entrega.
static void amostraG(double gx, double gy, double gz) {
  uint8_t d[6];
  const double g[3] = {gx, gy, gz};
  for (int i = 0; i < 3; ++i) {
    const int16_t bruto = static_cast<int16_t>(lround(g[i] * vibracao::LSB_POR_G));
    d[2 * i] = static_cast<uint8_t>(bruto >> 8);
    d[2 * i + 1] = static_cast<uint8_t>(bruto & 0xFF);
  }
  vibracao::amostra(d);
}

// Liga o sensor, passa 'segundos' de senoide no eixo y (com 1 g no z) e
// devolve o mm/s da ultima janela de 1 s.
static float medir(double hz, double picoG, int segundos = 4) {
  vibracao::iniciar(0x68);
  double t = 0;
  for (int s = 0; s < segundos; ++s) {
    for (int n = 0; n < 1000; ++n, t += 1.0 / vibracao::TAXA_HZ)
      amostraG(0, picoG * sin(2 * M_PI * hz * t), 1.0);
    vibracao::fecharJanela(true);
  }
  return vibracao::mmS;
}

// Velocidade RMS de uma aceleracao senoidal: v = a / (2 pi f); RMS = pico / raiz(2).
static double esperadoMmS(double hz, double picoG) {
  return picoG * vibracao::G / (2 * M_PI * hz) / M_SQRT2 * 1000.0;
}

TESTE("senoide de 60 Hz da a velocidade RMS teorica") {
  const float mmS = medir(60, 0.1);
  PERTO(mmS, esperadoMmS(60, 0.1), esperadoMmS(60, 0.1) * 0.01);
  CONFERE(vibracao::eixo == 'y');
  CONFERE(vibracao::velocidadeValida);
}

// Integrador de Al-Alaoui: erro de ganho de no maximo ~1,3 % ate 180 Hz
// (o trapezio de antes perdia 7,5 % em 150 Hz e 10,9 % em 180 Hz).
TESTE("faixa util: 30, 120, 150 e 180 Hz batem com a conta em 2 %") {
  for (double hz : {30.0, 120.0, 150.0, 180.0}) {
    const double esperado = esperadoMmS(hz, 0.2);
    PERTO(medir(hz, 0.2), esperado, esperado * 0.02);
  }
}

TESTE("gravidade parada nao vira vibracao") {
  PERTO(medir(60, 0.0), 0.0, 0.05);  // So 1 g constante no z.
}

TESTE("perto de 10 Hz o filtro corta cerca de 3 dB") {
  const double razao = medir(10, 0.05, 6) / esperadoMmS(10, 0.05);
  PERTO(razao, M_SQRT1_2, 0.12);
}

TESTE("abaixo da faixa (2 Hz, inclinacao lenta) quase nao conta") {
  CONFERE(medir(2, 0.05, 6) < esperadoMmS(2, 0.05) * 0.1);
}

TESTE("pico absurdo (ruido no I2C) fica fora da janela") {
  vibracao::iniciar(0x68);
  for (int n = 0; n < 1000; ++n) amostraG(0, 0, 1.0);
  vibracao::fecharJanela(true);
  const uint32_t normal = vibracao::amostras;
  for (int n = 0; n < 1000; ++n) amostraG(0, n == 500 ? 3.99 : 0.0, n == 500 ? -3.99 : 1.0);
  vibracao::fecharJanela(true);
  CONFERE(vibracao::amostras < normal + 1000);  // A leitura estranha nao entrou.
}

TESTE("janela curta ou sensor falhando nao viram leitura") {
  vibracao::iniciar(0x68);
  for (int n = 0; n < 1000; ++n) amostraG(0, 0.1 * sin(n * 0.3), 1.0);
  vibracao::fecharJanela(true);  // 300 amostras ainda assentando os filtros.
  CONFERE(vibracao::amostras == 700);
  for (int n = 0; n < 400; ++n) amostraG(0, 0.1 * sin(n * 0.3), 1.0);
  vibracao::fecharJanela(true);
  CONFERE(!vibracao::velocidadeValida);  // 400 < 500.
  for (int n = 0; n < 1000; ++n) amostraG(0, 0.1 * sin(n * 0.3), 1.0);
  vibracao::fecharJanela(false);
  CONFERE(!vibracao::velocidadeValida && vibracao::mmS == 0);
}

// Passa 'segundos' de sinal (funcao do tempo -> g em x, y, z) e fecha as janelas.
template <typename F>
static void passar(F sinal, int segundos) {
  vibracao::iniciar(0x68);
  double t = 0;
  for (int s = 0; s < segundos; ++s) {
    for (int n = 0; n < 1000; ++n, t += 0.001) {
      double g[3];
      sinal(t, g);
      amostraG(g[0], g[1], g[2]);
    }
    vibracao::fecharJanela(true);
  }
}

static int faixaDe(double hz) { return static_cast<int>(lround((hz - 20) / 10)); }

TESTE("por eixo: RMS, pico, crista e curtose de uma senoide") {
  passar([](double t, double* g) { g[0] = 0; g[1] = 0.1 * sin(2 * M_PI * 60 * t); g[2] = 1; }, 4);
  const double aRms = 0.1 * vibracao::G / M_SQRT2;
  PERTO(vibracao::mmSEixo[1], esperadoMmS(60, 0.1), esperadoMmS(60, 0.1) * 0.01);
  PERTO(vibracao::aRms[1], aRms, aRms * 0.02);
  PERTO(vibracao::aPico[1], 0.1 * vibracao::G, 0.1 * vibracao::G * 0.03);
  PERTO(vibracao::crista[1], M_SQRT2, 0.05);
  PERTO(vibracao::curtose[1], 1.5, 0.05);  // Senoide pura.
  CONFERE(vibracao::mmSEixo[0] < 0.05 && vibracao::mmSEixo[2] < 0.05);
}

TESTE("impactos sobem a crista e a curtose") {
  // 30 Hz com um impacto de 1 g a cada 100 ms (folga, rolamento batendo).
  passar([](double t, double* g) {
    const long n = lround(t * 1000);
    g[0] = 0.05 * sin(2 * M_PI * 30 * t) + (n % 100 == 0 ? 1.0 : 0.0);
    g[1] = 0; g[2] = 1;
  }, 4);
  CONFERE(vibracao::crista[0] > 4);
  CONFERE(vibracao::curtose[0] > 6);
}

TESTE("espectro so sai com 1024 amostras no anel") {
  vibracao::iniciar(0x68);
  for (int n = 0; n < 1000; ++n) amostraG(0, 0.1 * sin(2 * M_PI * 60 * n / 1000.0), 1);
  vibracao::fecharJanela(true);  // 700 uteis: janela valida, anel incompleto.
  CONFERE(vibracao::velocidadeValida && !vibracao::espectroValido);
  for (int n = 1000; n < 2000; ++n) amostraG(0, 0.1 * sin(2 * M_PI * 60 * n / 1000.0), 1);
  vibracao::fecharJanela(true);
  CONFERE(vibracao::espectroValido);
}

TESTE("espectro: 60 Hz cai na faixa de 60 Hz e o pico bate") {
  passar([](double t, double* g) { g[0] = 0; g[1] = 0.1 * sin(2 * M_PI * 60 * t); g[2] = 1; }, 4);
  const double esperado = esperadoMmS(60, 0.1);
  PERTO(vibracao::picoHz[1], 60, 0.3);
  PERTO(vibracao::picoMmS[1], esperado, esperado * 0.05);
  PERTO(vibracao::faixas[1][faixaDe(60)], esperado, esperado * 0.05);
  for (int f = 0; f < vibracao::NUM_FAIXAS; ++f)
    if (f != faixaDe(60)) CONFERE(vibracao::faixas[1][f] < esperado * 0.05);
}

TESTE("espectro: pico entre duas linhas (29,5 Hz, 1x de um 4 polos)") {
  passar([](double t, double* g) { g[0] = 0.2 * sin(2 * M_PI * 29.5 * t); g[1] = 0; g[2] = 1; }, 4);
  const double esperado = esperadoMmS(29.5, 0.2);
  PERTO(vibracao::picoHz[0], 29.5, 0.3);
  PERTO(vibracao::picoMmS[0], esperado, esperado * 0.06);
  PERTO(vibracao::faixas[0][faixaDe(30)], esperado, esperado * 0.05);
}

TESTE("espectro: dois tons (30 e 120 Hz) em faixas separadas; soma bate com o RMS") {
  passar([](double t, double* g) {
    g[0] = 0; g[1] = 0;
    g[2] = 1 + 0.2 * sin(2 * M_PI * 30 * t) + 0.3 * sin(2 * M_PI * 120 * t);
  }, 4);
  const double e30 = esperadoMmS(30, 0.2), e120 = esperadoMmS(120, 0.3);
  PERTO(vibracao::faixas[2][faixaDe(30)], e30, e30 * 0.05);
  PERTO(vibracao::faixas[2][faixaDe(120)], e120, e120 * 0.06);
  PERTO(vibracao::picoHz[2], 30, 0.3);  // O de 30 Hz tem mais velocidade.
  double soma = 0;
  for (int f = 0; f < vibracao::NUM_FAIXAS; ++f) soma += vibracao::faixas[2][f] * vibracao::faixas[2][f];
  PERTO(sqrt(soma), vibracao::mmSEixo[2], vibracao::mmSEixo[2] * 0.05);
}

// A telemetria do S3 no pior caso (todos os campos, numeros compridos, 8
// alarmes disparados) tem de caber no documento (3072) e no buffer do MQTT
// (2048, com o topico e o cabecalho).
TESTE("telemetria completa com o diagnostico cabe no documento e no MQTT") {
  vibracao::espectroValido = true;
  for (int i = 0; i < 3; ++i) {
    vibracao::mmSEixo[i] = vibracao::aRms[i] = vibracao::aPico[i] = 123.4567f;
    vibracao::crista[i] = vibracao::curtose[i] = vibracao::picoMmS[i] = 99.9999f;
    vibracao::picoHz[i] = 179.123f;
    for (int f = 0; f < vibracao::NUM_FAIXAS; ++f) vibracao::faixas[i][f] = 12.3456f + f;
  }
  DocumentoPc doc(16384);  // Mede no PC; a conta do ESP32 vem de bytesNoEsp32.
  doc["device_id"] = "esp32-02"; doc["seq"] = 4294967295u; doc["demo"] = false;
  doc["data_source"] = "mpu6050_ds18b20"; doc["mpu_ok"] = true; doc["temperature_ok"] = true;
  doc["sample_count"] = 1000u; doc["secure"] = true; doc["ts"] = 1790000000u;
  doc["alarm_enabled"] = true; doc["event_sounds"] = true; doc["buzzer_hz"] = 5000;
  doc["alarm_active"] = true; doc["motor_on"] = true; doc["command_telemetry_fresh"] = true;
  doc["vibration_mms"] = 12.3456789f; doc["vibration_axis"] = std::string("z");
  doc["temperature"] = 125.1234567f;
  JsonArray disparados = doc.createNestedArray("alarms_firing");
  for (int i = 0; i < 8; ++i) disparados.add(std::string(12, 'a' + i));
  vibracaojson::descrever(doc.createNestedObject("vib"));
  CONFERE(!doc.overflowed());
  // Texto copiado para o documento: o eixo ("z") e os 8 ids de alarme.
  const size_t noEsp32 = bytesNoEsp32(doc, 2 + 8 * 13);
  char payload[2048];
  const size_t n = serializeJson(doc, payload, sizeof(payload));
  std::printf("    telemetria no pior caso: %zu bytes; documento %zu de 3072 no ESP32\n", n, noEsp32);
  CONFERE(noEsp32 <= 3072);
  CONFERE(n > 0 && n + 5 + 2 + strlen("iotmotor/esp32-02/telemetry") < 2048);
  CONFERE(strstr(payload, "\"y\":{\"mms\":123.457") != nullptr);  // Eixo com o nome certo.
}

TESTE("vale o eixo com mais vibracao") {
  vibracao::iniciar(0x68);
  double t = 0;
  for (int s = 0; s < 3; ++s) {
    for (int n = 0; n < 1000; ++n, t += 0.001)
      amostraG(0.05 * sin(2 * M_PI * 50 * t), 0.02 * sin(2 * M_PI * 50 * t),
               1.0 + 0.2 * sin(2 * M_PI * 50 * t));
    vibracao::fecharJanela(true);
  }
  CONFERE(vibracao::eixo == 'z');
  PERTO(vibracao::mmS, esperadoMmS(50, 0.2), esperadoMmS(50, 0.2) * 0.03);
}
