#pragma once
// Vigia do loop(): se o programa travar, a placa reinicia sozinha.
//
// Travado, o loop() tambem deixa de rodar a protecao que desliga as saidas
// quando o MQTT/Wi-Fi cai. Reiniciar e o lado seguro: no boot as saidas
// voltam para o repouso antes de qualquer outra coisa.
//
// O core ja reseta o vigia a cada volta do loop(). Esperas longas de
// proposito alimentam o vigia por dentro (tentativas de Wi-Fi) ou o pausam
// (download do OTA e rede propria da placa, que levam minutos e so rodam com
// as saidas paradas).
//
// Mantenha este arquivo identico nas pastas dos dois firmwares.
#include <Arduino.h>
#include <esp_task_wdt.h>

extern bool loopTaskWDTEnabled;  // Do core (main.cpp): loop() inscrito no vigia.

namespace watchdog {

// Folga larga: uma volta normal leva milissegundos, e a mais lenta de
// proposito (conectar no MQTT por WebSocket: 6 s de TCP, 6 s de handshake e
// ate 15 s esperando o CONNACK) fica abaixo de ~30 s.
constexpr uint32_t TEMPO_MS = 60000;

inline bool ativo = false;
inline bool pausado = false;  // So retomar() o que pausar() desligou.

// Chamar no fim do setup(), depois das esperas longas do boot.
inline void iniciar() {
  esp_task_wdt_config_t config = {};
  config.timeout_ms = TEMPO_MS;
#if CONFIG_ESP_TASK_WDT_CHECK_IDLE_TASK_CPU0
  config.idle_core_mask |= 1 << 0;  // Mantem o que o core ja vigiava.
#endif
#if CONFIG_ESP_TASK_WDT_CHECK_IDLE_TASK_CPU1
  config.idle_core_mask |= 1 << 1;
#endif
  config.trigger_panic = true;  // Reinicia em vez de so avisar no Serial.
  esp_err_t erro = esp_task_wdt_reconfigure(&config);
  if (erro == ESP_ERR_INVALID_STATE) erro = esp_task_wdt_init(&config);
  if (erro != ESP_OK) {
    Serial.printf("[WDT] vigia nao configurado (%d)\n", (int)erro);
    return;
  }
  enableLoopWDT();
  ativo = loopTaskWDTEnabled;
  if (ativo) Serial.printf("[WDT] vigia do loop ativo (%lu s)\n", (unsigned long)(TEMPO_MS / 1000));
  else Serial.println("[WDT] loop() nao entrou no vigia");
}

// Dentro de esperas longas no loop(), como as tentativas de rede.
inline void alimentar() {
  if (ativo) esp_task_wdt_reset();
}

// Antes de uma espera de minutos (OTA, rede propria da placa).
inline void pausar() {
  if (!ativo) return;
  disableLoopWDT();
  ativo = false;
  pausado = true;
}

// Depois dela, se a placa nao reiniciou (OTA que falhou, por exemplo).
inline void retomar() {
  if (!pausado) return;  // Ex.: rede propria aberta no boot, antes de iniciar().
  pausado = false;
  enableLoopWDT();
  ativo = loopTaskWDTEnabled;
}

}  // namespace watchdog
