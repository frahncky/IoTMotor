# IoTMotor — ESP32-S3, módulo de vibração e temperatura

Firmware: `iotmotor_esp32_s3_sensores.ino` para **ESP32-S3**, identidade MQTT `esp32-02`. Não há GPIO de relé nem lógica de partida. O tópico de comando permite configurar/testar o alarme local, gerenciar Wi-Fi e atualizar o firmware. Os valores vêm **somente dos sensores físicos**; quando ausentes ou inválidos, o JSON omite o campo e o dashboard exibe `—`.

A pinagem abaixo foi extraída da proposta de dois módulos do projeto, **não foi confirmada na sua montagem**. Confira o modelo exato do S3 e os módulos de sensor antes de ligar.

| Elemento | Ligação ESP32-S3 |
| --- | --- |
| MPU6050 SDA | GPIO5 |
| MPU6050 SCL | GPIO9 |
| MPU6050 VCC/GND | Alimentação compatível com 3,3 V / GND |
| DS18B20 DQ | GPIO4, com resistor pull-up 4,7 kΩ para 3,3 V |
| DS18B20 VCC/GND | 3,3 V / GND |
| Buzzer passivo | GPIO42, sinal de 2 kHz |
| LED RGB azul / verde / vermelho | GPIO16 / GPIO17 / GPIO18, catodo comum |

## Alarme local

A pinagem do LED e do buzzer foi recuperada do firmware original do módulo 2.
Esses quatro pinos ficam excluídos da busca automática do DS18B20.

**Buzzer sem som (setembro de 2026):** em ensaio na bancada, o firmware
aciona o GPIO42 e responde `bipe acionado`, mas nada é ouvido — a causa é
elétrica (ligação/alimentação do buzzer), não de software. Depois de refazer
a ligação, o comando `buzzer_probe` percorre os pinos livres tocando cada um
por 0,7 s, primeiro como buzzer **passivo** (`tone`, 2 kHz) e depois como
**ativo** (nível alto), anunciando cada passo em `command_ack`:

```json
{"v":1,"device_id":"esp32-02","seq":"1726580000000999","action":"buzzer_probe","ms":700}
```

Ouvindo em qual passo sai som, ajuste `BUZZER_PIN` no sketch e, se o buzzer
for do tipo ativo, troque `tone()`/`noTone()` por `digitalWrite()`.

O LED fica verde quando há sensor válido e nenhum alarme disparado; vermelho
e buzzer intermitente quando o alarme geral está habilitado e algum alarme da
lista disparou; azul quando ambos os sensores estão sem leitura válida.
Desabilitar o alarme silencia o buzzer e remove a indicação vermelha.

### Lista de alarmes

Quem decide é a lista gravada na placa (`alarm_list.h`, até **8 alarmes** em
NVS). Cada item tem `id`, `field` (grandeza), `board`, `above` (acima ou
abaixo) e `limit`:

| `board` | Grandezas |
| --- | --- |
| `sensors` | `vibration_peak`, `vibration`, `temperature` — medidas aqui |
| `command` | `voltage`, `current`, `power`, `energy`, `frequency`, `pf` |

As grandezas elétricas chegam porque o S3 assina `iotmotor/esp32-01/telemetry`.
Leitura mais velha que 15 s não dispara nem silencia um alarme.

Na primeira vez, a placa semeia dois alarmes com os padrões antigos: pico de
vibração acima de **0,50 g** e temperatura acima de **60 °C**. A lista fica
retida em `iotmotor/esp32-02/alarms`, e a telemetria traz `alarms_firing`
com os ids disparados agora.

### Registro dos disparos

Cada episódio de alarme (começou, com que valor, quando acabou) fica gravado na
memória volátil da placa — os **10 últimos** — e é publicado retido em
`iotmotor/esp32-02/alarm_log`, com a hora em UTC quando o NTP já respondeu e a
duração em segundos, que vale mesmo sem hora. Reiniciar a placa zera o registro:
ele conta o que aconteceu no ensaio, não serve de histórico permanente.

O painel **não mostra** esse registro (a seção foi retirada por não ficar boa na
tela). Para ler, assine o tópico direto:

```sh
mosquitto_sub -h test.mosquitto.org -t iotmotor/esp32-02/alarm_log -v
```

Comandos: `alarm_list` (republica a lista e o registro), `alarm_save` (`{"alarm": {...}}`
cria ou edita pelo `id`) e `alarm_remove` (`{"id": "..."}`). O `alarm_set`
cuida apenas do interruptor geral (`enabled`) e dos bipes de evento
(`sounds`) — os limites são da lista. A confirmação só é enviada depois da
gravação.

Sensores e sinalização usam uma tarefa independente da rede. Continuam
funcionando durante perda de Wi-Fi/MQTT e abertura do portal, sem depender
de um navegador aberto. A janela de vibração é renovada a cada segundo,
inclusive offline. Reinicialização e gravação de firmware interrompem a execução.

Comandos em `iotmotor/esp32-02/command`:
- `{"v":1,"device_id":"esp32-02","seq":"123","action":"alarm_set","enabled":true,"sounds":true}`
- `{"v":1,"device_id":"esp32-02","seq":"124","action":"alarm_test"}`
- `{"v":1,"device_id":"esp32-02","seq":"125","action":"alarm_save","alarm":{"id":"current","field":"current","board":"command","above":true,"limit":12.5,"on":true}}`
- `{"v":1,"device_id":"esp32-02","seq":"126","action":"alarm_remove","id":"current"}`

Respostas em `command_ack` contêm `seq`, `action`, `accepted` e `reason`.
A telemetria inclui `alarm_enabled`, `alarm_active` e `alarms_firing`; os
limites vêm da lista retida em `alarms`, não da telemetria. O painel só habilita os controles com telemetria
compatível recebida há menos de 10 s e ignora telemetria/ACK retidos.

Instale no Arduino IDE o core ESP32 e as bibliotecas `PubSubClient`, `ArduinoJson` **6.x**, `OneWire` e `DallasTemperature`. Selecione a placa ESP32-S3 correta e compile/grave este arquivo na **S3**; mudanças no GitHub ou no Cloudflare não atualizam o firmware. Monitor Serial: **115200 baud**. Não foi feita validação física na sua placa.

A placa usa Wi-Fi aberto `IFMA_IOT` e publica via MQTT sobre WebSocket em `ws://test.mosquitto.org:8080` (a rede bloqueia as portas MQTT 1883 e 8883); o navegador usa `wss://test.mosquitto.org:8081`. Tópicos: `iotmotor/esp32-02/telemetry` e `iotmotor/esp32-02/status`. O painel agrega esses dados aos elétricos de `iotmotor/esp32-01/telemetry`, e os comandos de contatores são destinados **somente** ao `esp32-01`; o alarme usa o `esp32-02`.

O MPU6050 é amostrado aproximadamente a 50 Hz e o JSON publica `vibration` (RMS estimado da aceleração dinâmica em **g**) e `vibration_peak`; esse índice precisa de calibração e validação antes de interpretação como condição de máquina. A temperatura do DS18B20 é solicitada sem bloquear a comunicação, aproximadamente a cada 2 s. Erros de sensores são indicados em `mpu_ok` e `temperature_ok`; não há simulação neste firmware.

O broker público não autentica publicadores: dados podem ser falsificados e o serviço pode ficar indisponível. Não utilize estas mensagens como única proteção de um motor nem publique dados confidenciais.
