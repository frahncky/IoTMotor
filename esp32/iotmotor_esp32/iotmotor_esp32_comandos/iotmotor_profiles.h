#pragma once
// Perfis de ensaio MQTT: nao ha habilitacao por jumper GPIO32.
// O circuito de ensaio deve permanecer desconectado de motores e contatores no broker publico.
// Desligamento automatico de seguranca: 5 minutos por ensaio.
constexpr unsigned long LIMITE_BANCADA_MS = 300000UL;
constexpr unsigned long TEMPO_MORTO_MS = 700UL;
uint8_t etapaPartida = 0; // 0 parado, 1 aguarda, 2 estrela, 3 tempo morto, 4 triangulo, 5 direta.
uint8_t modoPartida = 0;  // 0 direta, 1 sequencia.
uint8_t mascaraDireta = 0;
uint8_t indicePrincipal = 0, indiceEstrela = 1, indiceTriangulo = 2;
unsigned long momentoPartida = 0, momentoEtapa = 0, tempoEstrelaMs = 5000;

// Diferenca com sinal: o comando MQTT chega depois de "agora" ser lido no loop,
// entao marcos podem ficar no futuro. Sem sinal, isso virava um numero enorme
// e a partida era cancelada como "tempo limite" antes de ligar os reles.
static inline int32_t decorrido(unsigned long agora, unsigned long marco) {
  return static_cast<int32_t>(static_cast<uint32_t>(agora) - static_cast<uint32_t>(marco));
}

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
  // Desligar antes de ligar; manter principal na transicao estrela-triangulo.
  for (uint8_t i = 0; i < NUM_RELES; ++i) if (!(mascara & (1U << i)) && estadoReles[i]) {
    estadoReles[i] = false;
    aplicarEstadoRele(i);
  }
  for (uint8_t i = 0; i < NUM_RELES; ++i) if ((mascara & (1U << i)) && !estadoReles[i]) {
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
  for (uint8_t i = 0; i < NUM_RELES; ++i) ligada = ligada || estadoReles[i];
  if (!ligada) return;
  // Falha da rede e limite de sessao desligam todas as saidas.
  if (WiFi.status() != WL_CONNECTED || decorrido(agora, momentoPartida) > (int32_t)LIMITE_BANCADA_MS) {
    pararBancada();
    Serial.println("[BANCADA] saidas desligadas por perda da rede ou tempo limite");
    return;
  }
  if (etapaPartida == 1 && decorrido(agora, momentoEtapa) >= 500) {
    momentoEtapa = agora;
    if (modoPartida == 0) {
      aplicarMascaraReles(mascaraDireta);
      etapaPartida = 5;
    } else {
      aplicarMascaraReles((1U << indicePrincipal) | (1U << indiceEstrela));
      etapaPartida = 2;
    }
  } else if (etapaPartida == 2 && decorrido(agora, momentoEtapa) >= (int32_t)tempoEstrelaMs) {
    aplicarMascaraReles(1U << indicePrincipal);
    etapaPartida = 3;
    momentoEtapa = agora;
  } else if (etapaPartida == 3 && decorrido(agora, momentoEtapa) >= (int32_t)TEMPO_MORTO_MS) {
    aplicarMascaraReles((1U << indicePrincipal) | (1U << indiceTriangulo));
    etapaPartida = 4;
    momentoEtapa = agora;
  }
}
