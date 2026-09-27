# Documentação do IoTMotor

| Documento | Para quem | O que tem |
| --- | --- | --- |
| 📘 [Guia de uso](guia-de-uso.md) | Quem opera a bancada | Conectar, dar partida, aquisição sincronizada, alarmes, dados do motor, manutenção, histórico, atualizar as placas e app |
| 📡 [Referência MQTT](mqtt.md) | Quem integra outro sistema | Tópicos, telemetria, configuração de aquisição, mensagens retidas, comandos e motivos de recusa |
| 🔌 [Hardware](hardware.md) | Quem monta | Lista de materiais, pinos das duas placas, LED, buzzer |
| 🔧 [Firmware](firmware.md) | Quem grava as placas | Primeira gravação, OTA, versões, partições, Wi-Fi, senha de comando |
| 🛠️ [Desenvolvimento](desenvolvimento.md) | Quem programa | Estrutura, testes, simuladores, CI, publicação do painel, do firmware e do app |

## Visão geral

```mermaid
flowchart LR
    P["🖥️ Painel web"] <--> B(("☁️ Broker MQTT"))
    A["📱 App Android"] <--> B
    B <--> Q["ESP32-01<br/>Quadro de comando"]
    B <--> S["ESP32-S3<br/>Sensores do motor"]
    Q -- contatores --> M["⚙️ Motor"]
    S -. mede .- M
```

- O **quadro de comando** mede a energia (PZEM-004T), aciona os contatores, guarda as partidas, os dados do motor e o horímetro e é a autoridade da configuração de aquisição sincronizada.
- A **placa de sensores** mede vibração e temperatura, cuida dos alarmes (LED e buzzer) e guarda o histórico de 7 dias.
- O **painel** e o **app** trocam telemetria e comandos pelo broker; as configurações operacionais que precisam valer para todo o sistema ficam gravadas nas placas.
- A configuração de aquisição fica gravada no ESP32-01 e é compartilhada com web, app e ESP32-S3; a vibração permanece em 1000 Hz com janela RMS de 1 s.
