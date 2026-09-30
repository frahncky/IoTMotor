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
// Para diagnostico (deteccao e classificacao de falhas), cada janela tambem
// da, por eixo: RMS, pico, fator de crista e curtose da aceleracao, e o
// espectro da velocidade (FFT de 1024 pontos, janela de Hann) resumido em
// faixas de 10 Hz e no pico dominante.
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
constexpr uint16_t MINIMO_JANELA = 500;

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
    // Integrador de Al-Alaoui (7/8 da amostra atual, 1/8 da anterior). O
    // trapezio lia a menos nas frequencias altas (-7,5 % em 150 Hz); este
    // erra no maximo 1,3 % ate 180 Hz, com o mesmo custo.
    integral += (7.0 * a + aAnterior) / (8.0 * TAXA_HZ);
    aAnterior = a;
    v = velocidade.passar(integral);
  }
};

inline Eixo eixos[3];
inline uint16_t assentando = AMOSTRAS_ASSENTAR;

// Espectro: as ultimas N velocidades de cada eixo, num anel.
constexpr uint16_t N_FFT = 1024;  // ~1 s a 1 kHz; resolucao de ~0,98 Hz.
// Faixas de 10 Hz centradas em 20, 30, ... 180 Hz. Bordas em 15, 25...:
// 60 e 120 Hz (rede e 2x rede) e 1x/2x a rotacao ficam no meio de uma faixa.
constexpr uint8_t NUM_FAIXAS = 17;
constexpr float PRIMEIRA_FAIXA_HZ = 20.0f, LARGURA_FAIXA_HZ = 10.0f;
// Pico dominante procurado entre 10 e 185 Hz.
constexpr float PICO_MIN_HZ = 10.0f, PICO_MAX_HZ = 185.0f;
inline float anel[3][N_FFT];
inline uint16_t posAnel = 0, cheioAnel = 0;

// Janela em andamento.
inline double somaV2[3] = {0, 0, 0};
inline double somaA2[3] = {0, 0, 0}, somaA4[3] = {0, 0, 0};
inline float picoA[3] = {0, 0, 0};
inline uint32_t nVelocidade = 0;

// Resultado da ultima janela fechada.
inline float mmS = 0;
inline char eixo = 'x';
inline uint32_t amostras = 0;
inline bool velocidadeValida = false;
inline uint32_t perdas = 0;  // FIFO cheia (amostras perdidas), para o serial.
// Por eixo (0 = x, 1 = y, 2 = z), validos junto com velocidadeValida.
inline float mmSEixo[3] = {0, 0, 0};
inline float aRms[3] = {0, 0, 0};    // Aceleracao RMS, m/s^2 (sem a gravidade).
inline float aPico[3] = {0, 0, 0};   // Maior |aceleracao| da janela, m/s^2.
inline float crista[3] = {0, 0, 0};  // Pico / RMS: impactos sobem este numero.
// Curtose: 1,5 numa senoide pura, 3 num ruido aleatorio; impactos passam disso.
inline float curtose[3] = {0, 0, 0};
// Espectro da velocidade, valido quando o anel ja tem N_FFT amostras.
inline bool espectroValido = false;
inline float faixas[3][NUM_FAIXAS];  // RMS da velocidade em cada faixa, mm/s.
inline float picoHz[3] = {0, 0, 0};  // Frequencia do pico dominante.
inline float picoMmS[3] = {0, 0, 0}; // RMS do pico dominante, mm/s.

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
  cheioAnel = 0;  // Velocidade de antes da perda nao se emenda com a de depois.
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
  for (uint8_t i = 0; i < 3; ++i) somaV2[i] = somaA2[i] = somaA4[i] = picoA[i] = 0;
  nVelocidade = 0;
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
  // Leitura absurda (ruido no I2C) nao entra na janela.
  const double dinamica = sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]) / G;
  if (!isfinite(dinamica) || dinamica >= 8.0) return;
  for (uint8_t i = 0; i < 3; ++i) {
    somaV2[i] += v[i] * v[i];
    const double a2 = a[i] * a[i];
    somaA2[i] += a2;
    somaA4[i] += a2 * a2;
    if (fabs(a[i]) > picoA[i]) picoA[i] = fabs(a[i]);
    anel[i][posAnel] = static_cast<float>(v[i]);
  }
  posAnel = (posAnel + 1) % N_FFT;
  if (cheioAnel < N_FFT) ++cheioAnel;
  ++nVelocidade;
}

// FFT complexa radix-2 no lugar (float: o S3 so tem FPU de precisao simples).
inline float fftRe[N_FFT], fftIm[N_FFT];
inline float hann[N_FFT], cosTab[N_FFT / 2], senTab[N_FFT / 2];
inline float somaHann2 = 0;

inline void prepararFft() {
  if (somaHann2 > 0) return;
  for (uint16_t n = 0; n < N_FFT; ++n) {
    hann[n] = 0.5f - 0.5f * cosf(2.0f * static_cast<float>(M_PI) * n / N_FFT);
    somaHann2 += hann[n] * hann[n];
  }
  for (uint16_t k = 0; k < N_FFT / 2; ++k) {
    cosTab[k] = cosf(2.0f * static_cast<float>(M_PI) * k / N_FFT);
    senTab[k] = -sinf(2.0f * static_cast<float>(M_PI) * k / N_FFT);
  }
}

inline void fft() {
  for (uint16_t i = 1, j = 0; i < N_FFT; ++i) {  // Ordem de bits invertida.
    uint16_t bit = N_FFT >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      float t = fftRe[i]; fftRe[i] = fftRe[j]; fftRe[j] = t;
      t = fftIm[i]; fftIm[i] = fftIm[j]; fftIm[j] = t;
    }
  }
  for (uint16_t tam = 2; tam <= N_FFT; tam <<= 1) {
    const uint16_t metade = tam / 2, passo = N_FFT / tam;
    for (uint16_t ini = 0; ini < N_FFT; ini += tam) {
      for (uint16_t k = 0; k < metade; ++k) {
        const float c = cosTab[k * passo], s = senTab[k * passo];
        const uint16_t p = ini + k, q = p + metade;
        const float re = fftRe[q] * c - fftIm[q] * s, im = fftRe[q] * s + fftIm[q] * c;
        fftRe[q] = fftRe[p] - re; fftIm[q] = fftIm[p] - im;
        fftRe[p] += re; fftIm[p] += im;
      }
    }
  }
}

// Linha espectral k -> Hz, e Hz -> primeira linha a partir dela.
inline float hzDaLinha(float k) { return k * static_cast<float>(TAXA_HZ) / N_FFT; }
inline uint16_t linhaDoHz(float hz) {
  return static_cast<uint16_t>(ceilf(hz * N_FFT / static_cast<float>(TAXA_HZ)));
}

// Espectro da velocidade de um eixo: faixas e pico dominante, em mm/s RMS.
// Potencia de uma faixa (Parseval com a janela): 2 / (N * soma(w^2)) * soma(|X|^2).
inline void espectroDoEixo(uint8_t e) {
  float media = 0;
  for (uint16_t n = 0; n < N_FFT; ++n) media += anel[e][n];
  media /= N_FFT;
  for (uint16_t n = 0; n < N_FFT; ++n) {  // Da mais antiga para a mais nova.
    fftRe[n] = (anel[e][(posAnel + n) % N_FFT] - media) * hann[n];
    fftIm[n] = 0;
  }
  fft();
  float* potencia = fftRe;  // Reaproveita: so a metade de baixo interessa.
  for (uint16_t k = 0; k < N_FFT / 2; ++k)
    potencia[k] = fftRe[k] * fftRe[k] + fftIm[k] * fftIm[k];
  const float escala = 2.0f / (N_FFT * somaHann2);
  auto rmsMmS = [&](uint16_t de, uint16_t ate) {  // [de, ate)
    float soma = 0;
    for (uint16_t k = de; k < ate && k < N_FFT / 2; ++k) soma += potencia[k];
    return sqrtf(escala * soma) * 1000.0f;
  };
  for (uint8_t f = 0; f < NUM_FAIXAS; ++f) {
    const float centro = PRIMEIRA_FAIXA_HZ + f * LARGURA_FAIXA_HZ;
    faixas[e][f] = rmsMmS(linhaDoHz(centro - LARGURA_FAIXA_HZ / 2),
                          linhaDoHz(centro + LARGURA_FAIXA_HZ / 2));
  }
  uint16_t k = linhaDoHz(PICO_MIN_HZ);
  const uint16_t ultima = linhaDoHz(PICO_MAX_HZ);
  for (uint16_t i = k + 1; i < ultima; ++i) if (potencia[i] > potencia[k]) k = i;
  // Interpolacao parabolica nas amplitudes: o pico fica entre duas linhas.
  const float a = sqrtf(potencia[k - 1]), b = sqrtf(potencia[k]), c = sqrtf(potencia[k + 1]);
  const float den = a - 2 * b + c;
  const float desvio = den != 0 ? 0.5f * (a - c) / den : 0;
  picoHz[e] = hzDaLinha(k + (desvio > 0.5f ? 0.5f : desvio < -0.5f ? -0.5f : desvio));
  picoMmS[e] = rmsMmS(k - 1, k + 2);  // A janela de Hann espalha o pico em 3 linhas.
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

// Fecha a janela: RMS da velocidade de cada eixo (vale o maior), as
// estatisticas da aceleracao e o espectro.
inline void fecharJanela(bool sensorOk) {
  amostras = sensorOk ? nVelocidade : 0;
  velocidadeValida = sensorOk && nVelocidade >= MINIMO_JANELA;
  mmS = 0;
  if (velocidadeValida) {
    for (uint8_t i = 0; i < 3; ++i) {
      const float rms = sqrt(somaV2[i] / nVelocidade) * 1000.0;
      mmSEixo[i] = rms;
      if (rms > mmS || i == 0) { mmS = rms; eixo = 'x' + i; }
      aRms[i] = sqrt(somaA2[i] / nVelocidade);
      aPico[i] = picoA[i];
      crista[i] = aRms[i] > 0 ? aPico[i] / aRms[i] : 0;
      // Curtose = N * soma(a^4) / soma(a^2)^2 (a aceleracao ja tem media ~0).
      curtose[i] = somaA2[i] > 0 ? nVelocidade * somaA4[i] / (somaA2[i] * somaA2[i]) : 0;
    }
  }
  espectroValido = velocidadeValida && cheioAnel >= N_FFT;
  if (espectroValido) {
    prepararFft();
    for (uint8_t i = 0; i < 3; ++i) espectroDoEixo(i);
  }
  for (uint8_t i = 0; i < 3; ++i) somaV2[i] = somaA2[i] = somaA4[i] = picoA[i] = 0;
  nVelocidade = 0;
}

}  // namespace vibracao
