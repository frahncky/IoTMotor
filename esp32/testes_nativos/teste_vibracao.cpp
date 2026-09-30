// Vibracao RMS em mm/s (vibracao.h), com o filtro e a integral reais do
// firmware. Uma senoide conhecida entra como se viesse da FIFO do MPU6050 e a
// velocidade que sai tem de bater com a conta feita a mao (docs/vibracao.md).
#include "teste.h"
#include "Arduino.h"
#include "../iotmotor_esp32/iotmotor_esp32_s3_sensores/vibracao.h"

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
