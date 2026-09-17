#pragma once
// Perfis MQTT de bancada: ensaios de saídas lógicas, sem motor ou contatores conectados.
// Contato físico GPIO32-GND é necessário para habilitar uma partida.
constexpr uint8_t PINO_HABILITACAO_BANCADA = 32;
constexpr unsigned long LIMITE_BANCADA_MS = 60000UL;
constexpr unsigned long TEMPO_MORTO_MS = 700UL;
uint8_t etapaPartida = 0; // 0 parado, 1 aguarda, 2 estrela, 3 tempo morto, 4 triângulo, 5 direta.
uint8_t modoPartida = 0;  // 0 direta, 1 sequência.
uint8_t mascaraDireta = 0;
uint8_t indicePrincipal = 0, indiceEstrela = 1, indiceTriangulo = 2;
unsigned long momentoPartida = 0, momentoEtapa = 0, tempoEstrelaMs = 5000;

bool bancadaHabilitada() { return digitalRead(PINO_HABILITACAO_BANCADA) == LOW; }
const char* nomeEtapa() {
  switch (etapaPartida) {
    case 1: return "Aguardando tempo de seguranca";
    case 2: return "Estrela (somente ensaio)";
    case 3: return "Tempo morto";
    case 4: return "Triangulo (somente ensaio)";
    case 5: return "Partida direta (somente ensaio)";
    default: return "Parado / comando manual";
  }
}
void aplicarMascaraReles(uint8_t mascara) {
  // Desligamentos antes dos ligamentos; o principal não desliga na transição.
  for (uint8_t i = 0; i < NUM_RELES; i++) if (!(mascara & (1U << i)) && estadoReles[i]) {
    estadoReles[i] = false;
    aplicarEstadoRele(i);
  }
  for (uint8_t i = 0; i < NUM_RELES; i++) if ((mascara & (1U << i)) && !estadoReles[i]) {
    estadoReles[i] = true;
    aplicarEstadoRele(i);
  }
  lcdPrecisaAtualizar = true;
}
void pararBancada() {
  etapaPartida = 0;
  aplicarMascaraReles(0);
}
void manterPartidaBancada(unsigned long agora) {
  bool ligada = etapaPartida != 0;
  for (uint8_t i = 0; i < NUM_RELES; i++) ligada = ligada || estadoReles[i];
  if (!ligada) return;
  // Jumper removido, Wi-Fi perdido ou tempo excedido: todas as saídas desligadas.
  if (!bancadaHabilitada() || WiFi.status() != WL_CONNECTED || agora - momentoPartida > LIMITE_BANCADA_MS) {
    pararBancada();
    Serial.println("[BANCADA] saidas desligadas por habilitacao, rede ou tempo limite");
    return;
  }
  if (etapaPartida == 1 && agora - momentoEtapa >= 500UL) {
    momentoEtapa = agora;
    if (modoPartida == 0) {
      aplicarMascaraReles(mascaraDireta);
      etapaPartida = 5;
    } else {
      aplicarMascaraReles((1U << indicePrincipal) | (1U << indiceEstrela));
      etapaPartida = 2;
    }
  } else if (etapaPartida == 2 && agora - momentoEtapa >= tempoEstrelaMs) {
    aplicarMascaraReles(1U << indicePrincipal);
    etapaPartida = 3;
    momentoEtapa = agora;
  } else if (etapaPartida == 3 && agora - momentoEtapa >= TEMPO_MORTO_MS) {
    aplicarMascaraReles((1U << indicePrincipal) | (1U << indiceTriangulo));
    etapaPartida = 4;
    momentoEtapa = agora;
  }
}
