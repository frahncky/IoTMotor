#pragma once
// Controle de perfis da bancada: chamadas HTTP no proprio ESP32, NUNCA no MQTT publico.
// Nao comanda motores/contatores sem intertravamento e protecoes independentes.
constexpr uint8_t PINO_HABILITACAO_BANCADA = 32; // Jumper removivel GPIO32 -> GND.
constexpr unsigned long LIMITE_BANCADA_MS = 60000UL;
constexpr unsigned long TEMPO_MORTO_MS = 700UL;
uint8_t etapaPartida = 0; // 0 parado, 1 aguarda, 2 estrela, 3 tempo morto, 4 triangulo, 5 direta.
uint8_t modoPartida = 0;  // 0 direta, 1 sequencia.
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
  // Desligamentos antes dos ligamentos, sem desligar o relé principal na transicao.
  for (uint8_t i=0;i<NUM_RELES;i++) if (!(mascara & (1U<<i)) && estadoReles[i]) {
    estadoReles[i] = false; aplicarEstadoRele(i);
  }
  for (uint8_t i=0;i<NUM_RELES;i++) if ((mascara & (1U<<i)) && !estadoReles[i]) {
    estadoReles[i] = true; aplicarEstadoRele(i);
  }
  lcdPrecisaAtualizar = true;
}
void pararBancada() {
  etapaPartida = 0;
  aplicarMascaraReles(0);
}
void manterPartidaBancada(unsigned long agora) {
  bool ligada = etapaPartida != 0;
  for (uint8_t i=0;i<NUM_RELES;i++) ligada = ligada || estadoReles[i];
  if (!ligada) return;
  // A habilitacao e um contato fisico: retirar jumper desenergiza todas as saidas.
  if (!bancadaHabilitada() || WiFi.status() != WL_CONNECTED || agora-momentoPartida>LIMITE_BANCADA_MS) {
    pararBancada();
    Serial.println("[BANCADA] saidas desligadas por habilitacao, rede ou tempo limite");
    return;
  }
  if (etapaPartida == 1 && agora-momentoEtapa>=500UL) {
    momentoEtapa=agora;
    if (modoPartida==0) { aplicarMascaraReles(mascaraDireta); etapaPartida=5; }
    else { aplicarMascaraReles((1U<<indicePrincipal)|(1U<<indiceEstrela)); etapaPartida=2; }
  } else if (etapaPartida==2 && agora-momentoEtapa>=tempoEstrelaMs) {
    aplicarMascaraReles(1U<<indicePrincipal);
    etapaPartida=3; momentoEtapa=agora;
  } else if (etapaPartida==3 && agora-momentoEtapa>=TEMPO_MORTO_MS) {
    aplicarMascaraReles((1U<<indicePrincipal)|(1U<<indiceTriangulo));
    etapaPartida=4; momentoEtapa=agora;
  }
}

bool numeroEstrito(const String& value, int& numero) {
  if (!value.length() || value.length()>2) return false;
  for (size_t i=0;i<value.length();++i) if (value[i]<'0'||value[i]>'9') return false;
  numero=value.toInt();return true;
}
void tratarPararBancada() {
  pararBancada();
  server.send(200,"text/plain; charset=utf-8","TODAS AS SAIDAS DESLIGADAS");
}
void tratarPartidaBancada() {
  if (!bancadaHabilitada()) { server.send(423,"text/plain","Jumper GPIO32-GND ausente");return; }
  if (etapaPartida) { server.send(409,"text/plain","Pare antes de configurar outra partida");return; }
  for (uint8_t i=0;i<NUM_RELES;i++) if (estadoReles[i]) {
    server.send(409,"text/plain","Desligue relés manuais antes de iniciar");return;
  }
  const String modo=server.arg("modo");
  uint8_t novaMascara=0,principal=0,estrela=1,triangulo=2;
  unsigned long tempo=5000;
  if (modo=="direct") {
    int valor=0;
    if (!numeroEstrito(server.arg("mascara"),valor)||valor<1||valor>15) {
      server.send(400,"text/plain","Mascara de relés inválida: 1 a 15");return;
    }
    novaMascara=static_cast<uint8_t>(valor);
  } else if (modo=="sequence") {
    int p=0,e=0,d=0,t=0;
    if (!numeroEstrito(server.arg("principal"),p)||!numeroEstrito(server.arg("estrela"),e)||
        !numeroEstrito(server.arg("triangulo"),d)||!numeroEstrito(server.arg("tempo"),t)||
        p<1||p>4||e<1||e>4||d<1||d>4||p==e||p==d||e==d||t<2||t>30) {
      server.send(400,"text/plain","Requer tres relés distintos e tempo estrela 2 a 30 s");return;
    }
    principal=p-1;estrela=e-1;triangulo=d-1;tempo=t*1000UL;
  } else { server.send(400,"text/plain","Modo inválido");return; }
  // Todas as saidas permanecem desligadas ate transcorrer a pausa inicial.
  aplicarMascaraReles(0);
  modoPartida=(modo=="sequence")?1:0;
  mascaraDireta=novaMascara;indicePrincipal=principal;indiceEstrela=estrela;indiceTriangulo=triangulo;
  tempoEstrelaMs=tempo;momentoPartida=millis();momentoEtapa=momentoPartida;etapaPartida=1;
  server.send(202,"text/plain; charset=utf-8","PARTIDA RECEBIDA; consulte /dados");
}
void tratarCanalBancada() {
  int canal=0,ligar=0;
  if (!numeroEstrito(server.arg("canal"),canal)||canal<1||canal>4||
      !numeroEstrito(server.arg("estado"),ligar)||ligar>1) {
    server.send(400,"text/plain","Canal e estado invalidos");return;
  }
  if (etapaPartida) { server.send(409,"text/plain","Sequencia em andamento: use parada geral");return; }
  if (ligar && !bancadaHabilitada()) { server.send(423,"text/plain","Jumper GPIO32-GND ausente");return; }
  estadoReles[canal-1]=(ligar==1);aplicarEstadoRele(canal-1);
  if (ligar) momentoPartida=millis();
  lcdPrecisaAtualizar=true;
  server.send(200,"text/plain",ligar?"RELE LIGADO":"RELE DESLIGADO");
}
