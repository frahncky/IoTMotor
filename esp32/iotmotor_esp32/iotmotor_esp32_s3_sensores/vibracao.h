#pragma once
// Vibracao pelo padrao de maquinas eletricas: velocidade RMS em mm/s
// (ISO 10816-3 / ISO 20816-3, IEC 60034-14), medida nos 3 eixos do MPU6050.
//
// O MPU mede aceleracao. A placa le 1000 amostras/s pela FIFO do sensor,
// tira o que esta abaixo de 10 Hz (gravidade e inclinacao), integra para
// velocidade e filtra de novo para a integral nao derivar. A cada
// janela de 1 s sai o RMS de cada eixo; vale o maior, como a norma pede
// (a pior direcao de medicao).
//
// Faixa: 10 Hz ate ~180 Hz (filtro interno do MPU a 1 kHz). A norma vai ate
// 1 kHz, mas num motor de 2 ou 4 polos o que pesa na severidade (1x e 2x a
// rotacao: desbalanceamento, desalinhamento, folga) esta abaixo de 180 Hz.
//
// Tambem sai a aceleracao dinamica em g (RMS e pico), como antes.
#include <Arduino.h>
#include <Wire.h>
#include <math.h>

namespace vibracao {

constexpr uint8_t ENDERECO = 0x68;
constexpr double TAXA_HZ = 1000.0;  // SMPLRT_DIV=0 com DLPF ligado: 1 kHz.
// Dois passa-altas em serie (antes e depois da integral) em 8 Hz somam -3 dB
// em 10 Hz, o inicio da faixa da norma.
constexpr double CORTE_HZ = 8.0;
constexpr double G = 9.80665;
constexpr float LSB_POR_G = 8192.0f;  // +/-4 g.
// Depois de ligar ou de uma perda de amostras, os filtros precisam assentar.
constexpr uint16_t AMOSTRAS_ASSENTAR = 300;
// Janela com menos que isso (placa travada, I2C falhando) nao vira leitura.
// A velocidade pede meia janela; o RMS em g, como antes, bem menos.
constexpr uint16_t MINIMO_JANELA = 500;
constexpr uint16_t MINIMO_ACELERACAO = 100;

// Filtro passa-altas Butterworth de 2a ordem (transformada bilinear).
struct PassaAltas {
  double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
  double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  void configurar(double fc, double fs) {
    const double k = tan(M_PI * fc / fs), q = M_SQRT1_2;
    const double n = 1.0 / (1.0 + k / q + k * k);
    b0 = n; b1 = -2.0 * n; b2 = n;
    a1 = 2.0 * (k * k - 1.0) * n;
    a2 = (1.0 - k / q + k * k) * n;
    zerar();
  }
  void zerar() { x1 = x2 = y1 = y2 = 0; }
  double passar(double x) {
    const double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    return y;
  }
};

struct Eixo {
  PassaAltas aceleracao, velocidade;
  double aAnterior = 0, integral = 0;
  void configurar() {
    aceleracao.configurar(CORTE_HZ, TAXA_HZ);
    velocidade.configurar(CORTE_HZ, TAXA_HZ);
    zerar();
  }
  void zerar() {
    aceleracao.zerar(); velocidade.zerar();
    aAnterior = integral = 0;
  }
  // Recebe g, devolve a aceleracao filtrada (m/s^2) e a velocidade (m/s).
  void passar(float g, double& a, double& v) {
    a = aceleracao.passar(g * G);
    integral += (a + aAnterior) * 0.5 / TAXA_HZ;  // Trapezio.
    aAnterior = a;
    v = velocidade.passar(integral);
  }
};

inline Eixo eixos[3];
inline uint16_t assentando = AMOSTRAS_ASSENTAR;

// Janela em andamento.
inline double somaV2[3] = {0, 0, 0}, somaG2 = 0;
inline uint32_t nVelocidade = 0, nAceleracao = 0;
inline float picoParcial = 0;  // Pico em g ate agora, para o alarme reagir antes do fim da janela.

// Resultado da ultima janela fechada.
inline float rmsG = 0, picoG = 0, mmS = 0;
inline char eixo = 'x';
inline uint32_t amostras = 0;
inline bool velocidadeValida = false, aceleracaoValida = false;
inline uint32_t perdas = 0;  // FIFO cheia (amostras perdidas), para o serial.

inline bool escrever(uint8_t reg, uint8_t valor) {
  Wire.beginTransmission(ENDERECO);
  Wire.write(reg); Wire.write(valor);
  return Wire.endTransmission() == 0;
}

inline bool lerRegistros(uint8_t reg, uint8_t* destino, uint8_t n) {
  Wire.beginTransmission(ENDERECO);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0 || Wire.requestFrom(ENDERECO, n, (uint8_t)true) != n) return false;
  for (uint8_t i = 0; i < n; ++i) destino[i] = Wire.read();
  return true;
}

inline void recomecarFiltros() {
  for (Eixo& e : eixos) e.zerar();
  assentando = AMOSTRAS_ASSENTAR;
}

inline bool reiniciarFifo() {
  recomecarFiltros();
  return escrever(0x6A, 0x04) && escrever(0x6A, 0x40);  // Zera e liga a FIFO.
}

// Configura o MPU (ja acordado) para 1 kHz com a FIFO so de acelerometro.
// 'id' e o WHO_AM_I: os clones MPU6500/9250 tem o filtro do acelerometro
// num registrador proprio (0x1D).
inline bool iniciar(uint8_t id) {
  for (Eixo& e : eixos) e.configurar();
  bool ok = escrever(0x1A, 0x01);         // DLPF 184 Hz: 1 kHz de amostragem.
  ok = ok && escrever(0x19, 0x00);        // Sem divisor: 1000 amostras/s.
  ok = ok && escrever(0x1C, 0x08);        // +/-4 g.
  if (ok && id != 0x68) ok = escrever(0x1D, 0x01);  // MPU6500: filtro de 218 Hz.
  ok = ok && escrever(0x23, 0x08);        // Na FIFO, so a aceleracao.
  ok = ok && reiniciarFifo();
  somaV2[0] = somaV2[1] = somaV2[2] = somaG2 = 0;
  nVelocidade = nAceleracao = 0;
  picoParcial = 0;
  return ok;
}

inline void amostra(const uint8_t* d) {
  const float g[3] = {
    (int16_t)((d[0] << 8) | d[1]) / LSB_POR_G,
    (int16_t)((d[2] << 8) | d[3]) / LSB_POR_G,
    (int16_t)((d[4] << 8) | d[5]) / LSB_POR_G,
  };
  double a[3], v[3];
  for (uint8_t i = 0; i < 3; ++i) eixos[i].passar(g[i], a[i], v[i]);
  if (assentando) {
    --assentando;
    return;
  }
  const float dinamica = sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]) / G;
  if (!isfinite(dinamica) || dinamica >= 8.0f) return;
  somaG2 += (double)dinamica * dinamica;
  picoParcial = fmaxf(picoParcial, dinamica);
  ++nAceleracao;
  for (uint8_t i = 0; i < 3; ++i) somaV2[i] += v[i] * v[i];
  ++nVelocidade;
}

// Le tudo o que esta na FIFO. false = o sensor nao respondeu.
inline bool ler() {
  uint8_t contagem[2], estado;
  if (!lerRegistros(0x3A, &estado, 1) || !lerRegistros(0x72, contagem, 2)) return false;
  uint16_t bytes = (contagem[0] << 8) | contagem[1];
  // FIFO cheia (1024 bytes): perdeu amostras e a integral ficou torta.
  if ((estado & 0x10) || bytes >= 1020) {
    ++perdas;
    return reiniciarFifo();
  }
  bytes -= bytes % 6;
  uint8_t bloco[120];  // 20 amostras: cabe no buffer do Wire (128 bytes).
  while (bytes) {
    const uint8_t n = bytes > sizeof(bloco) ? sizeof(bloco) : bytes;
    if (!lerRegistros(0x74, bloco, n)) return false;
    for (uint8_t i = 0; i < n; i += 6) amostra(bloco + i);
    bytes -= n;
  }
  return true;
}

// Fecha a janela: calcula RMS de velocidade (maior eixo) e de aceleracao.
inline void fecharJanela(bool sensorOk) {
  amostras = sensorOk ? nAceleracao : 0;
  aceleracaoValida = amostras >= MINIMO_ACELERACAO;
  rmsG = aceleracaoValida ? sqrt(somaG2 / nAceleracao) : 0;
  picoG = aceleracaoValida ? picoParcial : 0;
  velocidadeValida = sensorOk && nVelocidade >= MINIMO_JANELA;
  mmS = 0;
  if (velocidadeValida) {
    for (uint8_t i = 0; i < 3; ++i) {
      const float rms = sqrt(somaV2[i] / nVelocidade) * 1000.0;
      if (rms > mmS || i == 0) { mmS = rms; eixo = 'x' + i; }
    }
  }
  somaV2[0] = somaV2[1] = somaV2[2] = somaG2 = 0;
  nVelocidade = nAceleracao = 0;
  picoParcial = 0;
}

}  // namespace vibracao
