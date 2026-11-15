# BitDogLab: painel MQTT do quadro IoT Motor

Painel de bolso em MicroPython para a BitDogLab (Raspberry Pi Pico W). Funciona
em paralelo com o painel web e o app, pelo mesmo broker MQTT:

- mostra a telemetria **real** do quadro de comando (`esp32-01`: PZEM-004T e
  estado do motor) e da placa de sensores (`esp32-02`: temperatura e vibração);
- lista as partidas gravadas no quadro e permite escolher uma;
- liga e desliga o motor pelo protocolo do projeto IoT Motor
  ([`docs/mqtt.md`](../docs/mqtt.md)).

Quem aciona os contatores, aplica intertravamentos, limites e desarmes e
confirma o estado é o **quadro**. A BitDogLab só pede; o resultado volta pela
`command_ack` e pela telemetria.

```
quadro esp32-01 ---telemetry/profiles---> broker ---> BitDogLab, painel, app
sensores esp32-02 ---telemetry----------> broker ---> BitDogLab, painel, app
BitDogLab ---command (start/stop)-------> broker ---> quadro esp32-01
quadro ---command_ack-------------------> broker ---> BitDogLab
```

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `main.py` | Programa: Wi-Fi, MQTT, telas, controles e LED |
| `mqtt_websocket.py` | Cliente `umqtt.simple` sobre WebSocket (porta 8080) |
| `config.example.py` | Modelo de configuração; copie para `config.py` |
| `config.py` | Configuração real com senhas. **Ignorado pelo Git** |

## Telas

O joystick para a esquerda ou a direita troca a tela. O cabeçalho mostra o
nome da tela e a posição (4 quadradinhos). O rodapé é a única linha de estado.

| Tela | Conteúdo |
|---|---|
| Elétrica | Tensão, corrente, potência e fator de potência |
| Sensores | Temperatura, vibração (mm/s) com o eixo e alarmes ativos |
| Uso | Energia (kWh), frequência, horímetro e partidas de hoje |
| Partida | Lista das partidas do quadro, com a escolhida destacada |

Rodapé, por prioridade: mensagem do último comando (4 s), `Aguardando quadro`,
`Sem conexao`, `Quadro offline`, `DESARME <grandeza>`, `LIGADO <tempo>`,
fase da partida ou `Parado`.

> O display OLED não tem acentos: os textos da tela saem sem acento
> (por exemplo, "Eletrica" e "Estrela-triangulo").

## Controles

| Controle | Ação |
|---|---|
| Joystick esquerda/direita | Troca a tela |
| Joystick cima/baixo | Na tela Partida, escolhe a partida |
| A (toque) | Vai para a tela Partida |
| A (segurar 1,2 s) | Liga com a partida escolhida |
| B | Desliga (`stop`); sempre enviado |

**LED RGB** (brilho em `LED_BRIGHTNESS`, padrão 6%): azul parado, verde
ligado, amarelo partindo, vermelho sem conexão, quadro offline ou alarme.

O **buzzer** e a **matriz de LED 5×5** não são usados: ao iniciar, o programa
apaga a matriz e deixa o pino do buzzer em nível baixo. Avisos de comando,
recusas e alarmes aparecem só no rodapé do OLED e no LED RGB.

## Partida e parada

- **Partida:** segure A por 1,2 s. A placa envia `start` com o `boot` da
  telemetria atual e o `id` da partida escolhida. O `seq` é o `ts` da
  telemetria em microssegundos, compatível com o `Date.now()*1000` do painel.
- A partida não é enviada se `ENABLE_MOTOR_COMMANDS = False`, se o quadro
  estiver sem telemetria, exigir comando cifrado (`secure`), estiver em modo
  instrumentação ou já estiver ligado. O quadro ainda faz as próprias
  validações e responde com o aceite ou o motivo da recusa.
- **Parada:** B envia `stop` sempre, mesmo com a partida desativada.
- Sem `command_ack` em 10 s, o rodapé mostra `Sem resposta`.

> [!WARNING]
> O broker `test.mosquitto.org` é público. Sem a senha de comando no quadro,
> qualquer pessoa que conheça os tópicos pode ligar o motor. A BitDogLab não
> gera comandos cifrados: com a senha ativa no quadro, ela só consegue
> **desligar**.

## Tópicos

Prefixo e placas em `IOTMOTOR_PREFIX`, `IOTMOTOR_BOARD` e
`IOTMOTOR_SENSORS_BOARD`.

| Tópico | Direção | Uso |
|---|---|---|
| `iotmotor/esp32-01/telemetry` | recebe | Medições, `boot`, `ts`, `motor_running`, `relays`, `start_phase`, `trip_alarm` |
| `iotmotor/esp32-01/profiles` | recebe | Partidas gravadas (retido) |
| `iotmotor/esp32-01/status` | recebe | `online` / `offline` |
| `iotmotor/esp32-01/command` | envia | `start` e `stop` |
| `iotmotor/esp32-01/command_ack` | recebe | Aceite ou motivo da recusa |
| `iotmotor/esp32-02/telemetry` | recebe | `temperature`, `vibration_mms`, `vibration_axis`, `alarm_active`, `alarms_firing` |

Exemplo de partida enviada:

```json
{"v":1,"device_id":"esp32-01","seq":"1794681416123001","action":"start","boot":"2e7a6cebc599f6e6","profile":"direta"}
```

## Hardware

BitDogLab v6.3 com Raspberry Pi Pico W. Confirme os pinos em outras revisões.

| Função | GPIO | Configuração |
|---|---|---|
| Botão A / B | 5 / 6 | `PIN_BUTTON_A`, `PIN_BUTTON_B` |
| Joystick X / Y (ADC) | 27 / 26 | `PIN_JOYSTICK_X`, `PIN_JOYSTICK_Y` |
| OLED 128×64 SDA / SCL | 14 / 15 | `PIN_OLED_SDA`, `PIN_OLED_SCL` |
| LED R / G / B (PWM) | 13 / 11 / 12 | `PIN_LED_R`, `PIN_LED_G`, `PIN_LED_B` |
| Buzzer (mantido desligado) | 21 | `PIN_BUZZER` |
| Matriz 5×5 WS2812 (mantida apagada) | 7 | `PIN_MATRIX` |

Se o joystick estiver invertido, troque `JOYSTICK_X_SIGN` ou
`JOYSTICK_Y_SIGN` para `-1`.

## Instalação

1. Grave o MicroPython do **Pico W** na BitDogLab.
2. Instale as bibliotecas `umqtt.simple` e `ssd1306` (Thonny ou `mpremote mip install`).
3. Copie `config.example.py` para `config.py` e ajuste:
   - `WIFI_NETWORKS`: redes tentadas em ordem (só as que aparecem no scan).
     O Pico W só usa **2,4 GHz**: cadastre a rede 2G, não a 5G;
   - broker: o padrão do projeto é `test.mosquitto.org`, porta `8080`, com
     `MQTT_USE_WEBSOCKET = True` (a rede do IFMA bloqueia 1883 e 8883);
   - `ENABLE_MOTOR_COMMANDS = True` para liberar a partida pelo botão A.
4. Envie os arquivos e reinicie:

   ```sh
   mpremote connect COM5 cp main.py :main.py + cp mqtt_websocket.py :mqtt_websocket.py + cp config.py :config.py + reset
   ```

5. Acompanhe pelo serial (115200). Esperado:

   ```
   Wi-Fi conectado: MinhaRede 2G 192.168.0.50
   Conectada ao MQTT: test.mosquitto.org:8080
   ```

## Solução de problemas

| Sintoma | Causa provável |
|---|---|
| `Wi-Fi indisponivel` | Rede fora do alcance, só 5 GHz, senha errada ou nome diferente (ex.: `... 2G`) |
| `ETIMEDOUT` no MQTT | Porta bloqueada pela rede; teste a 8080 com WebSocket |
| `Quadro offline` | `esp32-01` desligado ou sem rede (status retido `offline`) |
| `Sensores offline` | `esp32-02` desligado ou sem rede |
| `mpremote` não entra no REPL | O laço principal ocupa a serial: envie Ctrl-C antes ou desconecte e reconecte o USB |

## Segurança

- A BitDogLab é um **terminal de operação**, não um dispositivo de segurança.
- A parada de emergência deve ser **física**, cortando as bobinas dos contatores.
- Intertravamento, limite de ensaio, queda por falta de rede e desarme por
  alarme ficam no quadro (ESP32-01).
- Nenhum comando é enviado com `retain`: um comando antigo nunca é repetido na
  reconexão.
