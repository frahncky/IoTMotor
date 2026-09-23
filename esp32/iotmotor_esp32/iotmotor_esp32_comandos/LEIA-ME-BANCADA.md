# IoTMotor — ESP32-01: PZEM-004T, LCD 20x4 e 4 relés via MQTT

Sketch `iotmotor_esp32_comandos.ino` (versão `v10-mqtt-websocket`) para **ESP32 DevKit V1**, identidade MQTT `esp32-01`. Lê as grandezas elétricas do **PZEM-004T v3**, mostra os dados no **LCD I2C 20x4** e aciona **4 relés (K1–K4)** por comandos MQTT. Não hospeda página web, não usa chave de comando e não usa jumper GPIO32. Vibração e temperatura ficam no ESP32-S3 (`esp32-02`), em `../iotmotor_esp32_s3_sensores/`.

A alteração no GitHub **não regrava** a placa. Instale o core ESP32 e as bibliotecas `PZEM004Tv30`, `LiquidCrystal I2C`, `PubSubClient` e `ArduinoJson` (6.x ou 7.x); compile e grave no ESP32. Monitor Serial a **115200 baud**.

## Duração máxima do ensaio

Quanto tempo as saídas podem ficar ligadas numa mesma partida. O padrão de
fábrica são **5 minutos** (`LIMITE_BANCADA_MS`); o valor em uso fica gravado na
placa.

- No painel: **"Duração máxima do ensaio"**, no quadro de comando.
- Por MQTT: `{"v":1,"device_id":"esp32-01","seq":"1","action":"run_limit","seconds":900}`.
- `seconds`: de **10 a 7200**; **-1** tira o limite de tempo.
- Aparece na telemetria como `run_limit_s` (-1 = sem limite).

Com **-1**, nenhum tempo do firmware desliga a bancada: o que a encerra é o fim
da própria partida, o botão **Desligar todos**, a queda de rede (quando
configurada para derrubar) e, sempre, a parada elétrica. Os tempos de cada
contator dentro de uma partida continuam limitados a 5 minutos.

## Queda de rede durante o ensaio

Quanto tempo as saídas continuam ligadas depois que o Wi-Fi ou o MQTT cai. O
padrão são **15 s**, que cobrem as quedas curtas do broker público sem deixar a
bancada ligada sozinha.

- No painel: **"Se a conexão cair, o ensaio segue por"**, no quadro de comando.
- Por MQTT: `{"v":1,"device_id":"esp32-01","seq":"1","action":"link_grace","seconds":60}`.
- `seconds`: **0** derruba as saídas assim que a rede cair; **1 a 3600** segue
  por esse tempo; **-1** segue sem limite de rede.
- Fica gravado na placa e aparece na telemetria como `link_grace_s` (-1 = sem
  limite).

Mesmo com **-1**, o ensaio continua limitado pelos **5 minutos** de
`LIMITE_BANCADA_MS`: "sem limite" quer dizer que a falta de rede não derruba,
não que o ensaio corre para sempre. E, enquanto a rede estiver fora, ninguém
consegue mandar parar pelo painel — a parada tem que ser elétrica.

## Modo instrumentação

Com o **acionamento desligado**, a placa não fecha contator nenhum: só lê o
PZEM, publica a telemetria e escreve no LCD (linha 1: "Somente medicao"). Serve
para instrumentar um motor acionado por comando elétrico convencional, sem o
ESP32 no meio do caminho.

- No painel, botão **Somente medição** (vira **Liberar acionamento** quando já
  está no modo). Ao entrar no modo, as saídas ligadas caem na hora.
- Por MQTT: `{"v":1,"device_id":"esp32-01","seq":"1","action":"actuation","on":false}`.
- O estado fica gravado na placa (NVS) e sobrevive a reinício e a queda de
  energia; a telemetria publica `actuation: false`.
- Nesse modo, `start` é recusado com "modo instrumentacao: acionamento
  desligado". O `stop` continua valendo sempre.

## Ligações

| Elemento | Ligação ESP32-01 |
| --- | --- |
| PZEM TX → ESP32 RX2 | GPIO16 |
| PZEM RX → ESP32 TX2 | GPIO17 |
| LCD I2C SDA / SCL | GPIO21 / GPIO22, endereço `0x27` |
| Relé K1 / K2 / K3 / K4 | GPIO19 / GPIO18 / GPIO23 / GPIO27 |

Os relés são acionados em nível **alto** (`RELE_ATIVO_EM_NIVEL_BAIXO = false`). Se o seu módulo for ativo em nível baixo, altere essa constante antes de gravar.

## Rede e tópicos

| Item | Valor |
| --- | --- |
| Wi-Fi | `IFMA_IOT`, sem senha |
| MQTT do ESP32 | `ws://test.mosquitto.org:8080` (MQTT sobre WebSocket; a rede IFMA_IOT bloqueia as portas 1883 e 8883) |
| MQTT do painel | `wss://test.mosquitto.org:8081` (WSS) |
| Telemetria (1 s) | `iotmotor/esp32-01/telemetry` |
| Status (retido) | `iotmotor/esp32-01/status` (`online` / `offline`) |
| Capacidades (retido) | `iotmotor/esp32-01/capabilities` |
| Comandos | `iotmotor/esp32-01/command` |
| Confirmação | `iotmotor/esp32-01/command_ack` |

A telemetria inclui `voltage`, `current`, `power`, `energy`, `frequency` e `pf` (omitidos se o PZEM não responder, sem valores falsos), `pzem_ok`, `relays` (4 booleanos), `relay_pins`, `lcd` (as 4 linhas do display), `start_phase` e `boot`.

## Comandos

Todo comando é um JSON com `v:1`, `device_id:"esp32-01"`, `seq` (inteiro em texto, sem zero à esquerda, até 18 dígitos) e `action`.

- **`stop`**: sempre aceito; desliga todos os relés e cancela a partida em andamento. Não exige `boot` nem `seq` crescente.
- **`start`**: exige `boot` igual ao publicado na telemetria atual (muda a cada reinício do ESP32), `seq` maior que o último aceito, todos os relés desligados e nenhuma partida em andamento. Campos `mode`, `mask`, `main`, `star`, `delta` e `seconds` são obrigatórios (inteiros):
  - `mode:"direct"`: `mask` de 1 a 15 (bit 0 = K1 … bit 3 = K4); `main`, `star`, `delta` e `seconds` = 0.
  - `mode:"sequence"` (estrela-triângulo de ensaio): `mask` = 0; `main`, `star` e `delta` são relés distintos de 1 a 4; `seconds` de 2 a 30 (tempo em estrela).

Exemplos:

```json
{"v":1,"device_id":"esp32-01","seq":"1726580000000123","action":"stop","boot":"","mode":"none","mask":0,"main":0,"star":0,"delta":0,"seconds":0}
{"v":1,"device_id":"esp32-01","seq":"1726580000000456","action":"start","boot":"<boot da telemetria>","mode":"direct","mask":3,"main":0,"star":0,"delta":0,"seconds":0}
```

A resposta em `command_ack` traz `accepted` e `reason`: `accepted`, `stopped`, `unknown_action`, `session_mismatch`, `duplicate`, `busy_or_offline`, `already_on` ou `invalid_profile`.

## Atualização pela internet (OTA)

A placa se regrava sozinha, sem cabo e de qualquer rede com saída HTTPS. Envie em `iotmotor/esp32-01/command`:

```json
{"v":1,"device_id":"esp32-01","seq":"1726580000000999","action":"update","boot":"","mode":"none","mask":0,"main":0,"star":0,"delta":0,"seconds":0}
```

O ESP32-S3 aceita o mesmo comando em `iotmotor/esp32-02/command`, com `device_id` `esp32-02`.

- O firmware baixado é sempre o do release **`firmware-latest`** do repositório, publicado a cada commit na `main` pelo workflow `publish-firmware.yml`. A URL é fixa no código (`ota_update.h`): o comando apenas dispara a atualização e **não** escolhe de onde baixar, já que o broker é público.
- A atualização é **recusada com as saídas ligadas**; pare antes.
- Ao terminar, a placa reinicia com o firmware novo. A resposta vai para `command_ack`; em caso de falha, traz o motivo.
- **Redes**: `wifi_local.h` aceita até quatro redes (`WIFI_SSID_2`, `_3`, `_4`). A placa usa a disponível de sinal mais forte, então trocar de Wi-Fi não exige cabo.

## Sequência de partida e desligamentos automáticos

1. Após aceitar `start`, aguarda 0,5 s com tudo desligado.
2. **Direta**: liga os relés da máscara. **Sequência**: liga principal + estrela; após `seconds`, desliga a estrela (tempo morto de 0,7 s) e liga principal + triângulo.
3. Todos os relés são desligados automaticamente:
   - **5 minutos** após o `start` (`LIMITE_BANCADA_MS`), em qualquer modo;
   - após **15 s** sem Wi-Fi ou MQTT (`TOLERANCIA_SEM_LINK_MS`); quedas mais curtas não desarmam o ensaio.

## Segurança

O broker é público e **não autentica comandos**: o valor `boot` é publicado na própria telemetria, então qualquer pessoa que assine o tópico consegue enviar `start`. Use este firmware **somente em bancada sem motor nem contatores conectados**. Os desligamentos automáticos são por software e não substituem intertravamento físico nem proteções independentes. Confirme isolamento e alimentação do PZEM conforme o fabricante e não faça ligações com o circuito energizado.
