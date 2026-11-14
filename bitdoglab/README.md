# BitDogLab: painel MQTT do quadro IoT Motor

Painel de bolso em MicroPython para a BitDogLab (Raspberry Pi Pico W). Funciona
em paralelo com o painel web e o app, pelo mesmo broker MQTT:

- mostra a telemetria **real** do quadro de comando (`esp32-01`: PZEM-004T e
  estado do motor) e da placa de sensores (`esp32-02`: temperatura e vibracao);
- lista as partidas gravadas no quadro e permite escolher uma;
- liga e desliga o motor pelo protocolo do projeto IoT Motor
  ([`docs/mqtt.md`](../docs/mqtt.md)).

Quem aciona os contatores, aplica intertravamentos, limites e desarmes e
confirma o estado e o **quadro**. A BitDogLab so pede; o resultado volta pela
`command_ack` e pela telemetria.

```
quadro esp32-01 ---telemetry/profiles---> broker ---> BitDogLab, painel, app
sensores esp32-02 ---telemetry----------> broker ---> BitDogLab, painel, app
BitDogLab ---command (start/stop)-------> broker ---> quadro esp32-01
quadro ---command_ack-------------------> broker ---> BitDogLab
```

## Arquivos

| Arquivo | Conteudo |
|---|---|
| `main.py` | Programa: Wi-Fi, MQTT, telas, controles, LED e buzzer |
| `matrix.py` | Matriz 5x5 WS2812: icones e barras |
| `mqtt_websocket.py` | Cliente `umqtt.simple` sobre WebSocket (porta 8080) |
| `config.example.py` | Modelo de configuracao; copie para `config.py` |
| `config.py` | Configuracao real com senhas. **Ignorado pelo Git** |

## Telas

O joystick para esquerda/direita troca a tela. O cabecalho mostra o nome da
tela e a posicao (4 quadradinhos). O rodape e a unica linha de estado.

| Tela | Conteudo |
|---|---|
| Eletrica | Tensao, corrente, potencia e fator de potencia |
| Sensores | Temperatura, vibracao (mm/s) com o eixo e alarmes ativos |
| Uso | Energia (kWh), frequencia, horimetro e partidas de hoje |
| Partida | Lista das partidas do quadro, com a escolhida destacada |

Rodape, por prioridade: mensagem do ultimo comando (4 s), `Aguardando quadro`,
`Sem conexao`, `Quadro offline`, `DESARME <grandeza>`, `LIGADO <tempo>`,
fase da partida ou `Parado`.

## Controles

| Controle | Acao |
|---|---|
| Joystick esquerda/direita | Troca a tela |
| Joystick cima/baixo | Na tela Partida, escolhe a partida |
| A (toque) | Vai para a tela Partida |
| A (segurar 1,2 s) | Liga com a partida escolhida |
| B | Desliga (`stop`); sempre enviado |
| SW (botao do joystick) | Silencia o alarme sonoro atual |

**LED RGB** (brilho em `LED_BRIGHTNESS`, padrao 6%): azul parado, verde
ligado, amarelo partindo, vermelho sem conexao, quadro offline ou alarme.

**Buzzer** (`BUZZER_ENABLED`): clique em cada controle, dois bipes agudos
quando o quadro aceita, bipe grave na recusa e bipe duplo a cada 3 s com
alarme ou desarme ativo. O SW silencia; um alarme diferente volta a tocar.

## Matriz de LED 5x5

A matriz mostra o estado de longe, com brilho baixo (`MATRIX_BRIGHTNESS`, 4%).
Prioridade:

| Situacao | Matriz |
|---|---|
| Sem conexao ou quadro offline | X azul |
| Alarme ou desarme | ! vermelho piscando |
| Estrela-triangulo em curso | Y ciano na estrela, traco no tempo morto, triangulo por 3 s apos a troca |
| Motor ligado, tela Sensores | Barra de vibracao (mm/s / limite do alarme de vibracao) |
| Motor ligado | Barra de carga (corrente / corrente nominal) |
| Partindo (rele ligado, sem corrente) | Play amarelo piscando |
| Parado | Quadrado azul |

Barras: so a linha de baixo da matriz. 4 LEDs = 100% (nominal ou limite); o 5o, vermelho, acende acima
disso. Verde ate 75%, amarelo ate 100%.

- A corrente nominal vem de `iotmotor/esp32-01/motor_info` (`current_a`, ou
  `current_y_a` com o motor ligado em estrela). Sem ela, o motor ligado
  aparece como play verde. `MOTOR_NOMINAL_A` no `config.py` e a reserva.
- O limite de vibracao vem do alarme `vibration_mms` em
  `iotmotor/esp32-02/alarms`; reserva `VIBRATION_LIMIT_MMS` (4,5 mm/s).
- Estrela e triangulo saem da partida gravada: o contator que desliga no
  meio (`off > 0`) e a estrela; o que liga depois dele e o triangulo.
- Icones de cabeca para baixo: `MATRIX_FLIP = True`.

## Partida e parada

- **Partida:** segure A por 1,2 s. A placa envia `start` com o `boot` da
  telemetria atual e o `id` da partida escolhida. O `seq` e o `ts` da
  telemetria em microssegundos, compativel com o `Date.now()*1000` do painel.
- A partida nao e enviada se `ENABLE_MOTOR_COMMANDS = False`, se o quadro
  estiver sem telemetria, exigir comando cifrado (`secure`), estiver em modo
  instrumentacao ou ja estiver ligado. O quadro ainda faz as proprias
  validacoes e responde aceite ou motivo da recusa.
- **Parada:** B envia `stop` sempre, mesmo com a partida desativada.
- Sem `command_ack` em 10 s, o rodape mostra `Sem resposta`.

> [!WARNING]
> O broker `test.mosquitto.org` e publico. Sem a senha de comando no quadro,
> qualquer pessoa que conheca os topicos pode ligar o motor. A BitDogLab nao
> gera comandos cifrados: com a senha ativa no quadro, ela so consegue
> **desligar**.

## Topicos

Prefixo e placas em `IOTMOTOR_PREFIX`, `IOTMOTOR_BOARD` e
`IOTMOTOR_SENSORS_BOARD`.

| Topico | Direcao | Uso |
|---|---|---|
| `iotmotor/esp32-01/telemetry` | recebe | Medicoes, `boot`, `ts`, `motor_running`, `relays`, `start_phase`, `trip_alarm` |
| `iotmotor/esp32-01/profiles` | recebe | Partidas gravadas (retido) |
| `iotmotor/esp32-01/status` | recebe | `online` / `offline` |
| `iotmotor/esp32-01/command` | envia | `start` e `stop` |
| `iotmotor/esp32-01/command_ack` | recebe | Aceite ou motivo da recusa |
| `iotmotor/esp32-01/motor_info` | recebe | Corrente nominal para a barra de carga (retido) |
| `iotmotor/esp32-02/alarms` | recebe | Limite de vibracao para a barra (retido) |
| `iotmotor/esp32-02/telemetry` | recebe | `temperature`, `vibration_mms`, `vibration_axis`, `alarm_active`, `alarms_firing` |

Exemplo de partida enviada:

```json
{"v":1,"device_id":"esp32-01","seq":"1794681416123001","action":"start","boot":"2e7a6cebc599f6e6","profile":"direta"}
```

## Hardware

BitDogLab v6.3 com Raspberry Pi Pico W. Confirme os pinos em outras revisoes.

| Funcao | GPIO | Configuracao |
|---|---|---|
| Botao A / B | 5 / 6 | `PIN_BUTTON_A`, `PIN_BUTTON_B` |
| Joystick X / Y (ADC) | 27 / 26 | `PIN_JOYSTICK_X`, `PIN_JOYSTICK_Y` |
| Botao do joystick | 22 | `PIN_JOYSTICK_BUTTON` |
| OLED 128x64 SDA / SCL | 14 / 15 | `PIN_OLED_SDA`, `PIN_OLED_SCL` |
| LED R / G / B (PWM) | 13 / 11 / 12 | `PIN_LED_R`, `PIN_LED_G`, `PIN_LED_B` |
| Buzzer (PWM) | 21 | `PIN_BUZZER` |
| Matriz 5x5 WS2812 | 7 | `PIN_MATRIX` |

Se o joystick estiver invertido, troque `JOYSTICK_X_SIGN` ou
`JOYSTICK_Y_SIGN` para `-1`.

## Instalacao

1. Grave o MicroPython do **Pico W** na BitDogLab.
2. Instale as bibliotecas `umqtt.simple` e `ssd1306` (Thonny ou `mpremote mip install`).
3. Copie `config.example.py` para `config.py` e ajuste:
   - `WIFI_NETWORKS`: redes tentadas em ordem (so as que aparecem no scan).
     O Pico W so usa **2,4 GHz**: cadastre a rede 2G, nao a 5G;
   - broker: o padrao do projeto e `test.mosquitto.org`, porta `8080`, com
     `MQTT_USE_WEBSOCKET = True` (a rede do IFMA bloqueia 1883 e 8883);
   - `ENABLE_MOTOR_COMMANDS = True` para liberar a partida pelo botao A.
4. Envie os arquivos e reinicie:

   ```sh
   mpremote connect COM5 cp main.py :main.py + cp matrix.py :matrix.py + cp mqtt_websocket.py :mqtt_websocket.py + cp config.py :config.py + reset
   ```

5. Acompanhe pelo serial (115200). Esperado:

   ```
   Wi-Fi conectado: MinhaRede 2G 192.168.0.50
   Conectada ao MQTT: test.mosquitto.org:8080
   ```

## Solucao de problemas

| Sintoma | Causa provavel |
|---|---|
| `Wi-Fi indisponivel` | Rede fora do alcance, so 5 GHz, senha errada ou nome diferente (ex.: `... 2G`) |
| `ETIMEDOUT` no MQTT | Porta bloqueada pela rede; teste a 8080 com WebSocket |
| `Quadro offline` | `esp32-01` desligado ou sem rede (status retido `offline`) |
| `Sensores offline` | `esp32-02` desligado ou sem rede |
| `mpremote` nao entra no REPL | O laco principal ocupa a serial: envie Ctrl-C antes ou desconecte e reconecte o USB |

## Seguranca

- A BitDogLab e um **terminal de operacao**, nao um dispositivo de seguranca.
- A parada de emergencia deve ser **fisica**, cortando as bobinas dos contatores.
- Intertravamento, limite de ensaio, queda por falta de rede e desarme por
  alarme ficam no quadro (ESP32-01).
- Nenhum comando e enviado com `retain`: um comando antigo nunca e repetido na
  reconexao.
