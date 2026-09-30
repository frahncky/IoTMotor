# Referência MQTT

Tudo o que o painel e o app trocam com as placas passa pelo broker. Este documento
lista os tópicos, os campos e os comandos, para quem quer integrar outro sistema
ou entender uma mensagem que viu no broker.

> [!NOTE]
> Os nomes abaixo usam o prefixo padrão `iotmotor` e as placas `esp32-01`
> (quadro de comando) e `esp32-02` (sensores do motor). O prefixo e os IDs podem
> ser trocados no painel, em **Configurações › Conexão MQTT**.

## Sumário

- [Broker e endereços](#broker-e-endereços)
- [Tópicos](#tópicos)
- [Telemetria do quadro de comando](#telemetria-do-quadro-de-comando)
- [Telemetria dos sensores do motor](#telemetria-dos-sensores-do-motor)
- [Mensagens retidas](#mensagens-retidas)
- [Como enviar um comando](#como-enviar-um-comando)
- [Comandos do quadro de comando](#comandos-do-quadro-de-comando)
- [Comandos dos sensores do motor](#comandos-dos-sensores-do-motor)
- [Comandos das duas placas](#comandos-das-duas-placas)
- [Comandos cifrados](#comandos-cifrados)
- [Motivos de recusa](#motivos-de-recusa)

## Broker e endereços

O broker é o público `test.mosquitto.org`. Cada parte usa o caminho que a rede
deixa passar:

| Quem | Endereço | Observação |
| --- | --- | --- |
| Placas ESP32 | `ws://test.mosquitto.org:8080` | MQTT sobre WebSocket; a rede do IFMA bloqueia 1883 e 8883 |
| Painel (padrão) | `wss://iotmotor.pages.dev/mqtt` | Ponte na porta 443, servida pela Cloudflare ([`functions/mqtt.js`](../functions/mqtt.js)) |
| Painel (direto) | `wss://test.mosquitto.org:8081` | Quando a porta 8081 não é bloqueada |
| App | `ws://test.mosquitto.org` porta 8080, ou `test.mosquitto.org` porta 1883 | O app testa os caminhos em **Configurações › Testar caminhos de conexão** |

A ponte repassa os bytes sem interpretar nada. Do lado do broker ela usa MQTT
sobre TCP (porta 1883), como as placas. Abrindo `…/mqtt?debug=1`, ela narra o
caminho dos bytes.

> [!WARNING]
> O broker público aceita publicação de qualquer pessoa. Sem a
> [senha de comando](#comandos-cifrados), qualquer um que conheça os tópicos
> consegue mandar comandos para as placas.

## Tópicos

| Tópico | Quem publica | Retido | Conteúdo |
| --- | --- | :---: | --- |
| `iotmotor/<placa>/telemetry` | placa, conforme `publish_ms` (padrão 1 s) | | Medições e estado ([quadro](#telemetria-do-quadro-de-comando), [sensores](#telemetria-dos-sensores-do-motor)) |
| `iotmotor/<placa>/status` | placa | ✔ | `online` / `offline` (texto puro; `offline` é a última vontade da conexão) |
| `iotmotor/<placa>/capabilities` | placa | ✔ | Versão do firmware e grandezas publicadas |
| `iotmotor/<placa>/command` | painel, app | | [Comandos](#como-enviar-um-comando) |
| `iotmotor/<placa>/command_ack` | placa | | Resposta a cada comando |
| `iotmotor/<placa>/auth` | placa | ✔ | Desafio para [comandos cifrados](#comandos-cifrados) |
| `iotmotor/<placa>/wifi` | placa | ✔ | Redes Wi-Fi gravadas (sem senhas) |
| `iotmotor/esp32-01/profiles` | quadro | ✔ | Partidas gravadas |
| `iotmotor/esp32-01/motor_info` | quadro | ✔ | Dados da placa do motor e manutenção |
| `iotmotor/system/acquisition` | quadro | ✔ | Configuração única de aquisição, publicação, gráficos e registro |
| `iotmotor/esp32-02/alarms` | sensores | ✔ | Lista de alarmes |
| `iotmotor/esp32-02/alarm_log` | sensores | ✔ | Últimos 10 disparos |
| `iotmotor/esp32-02/history/<0..6>` | sensores | ✔ | Histórico por hora, um tópico por dia |

A placa de sensores também **assina** `iotmotor/esp32-01/telemetry`: é assim que
os alarmes de corrente, tensão e partidas tocam no LED e no buzzer dela.

## Telemetria do quadro de comando

`iotmotor/esp32-01/telemetry`, conforme `publish_ms` da configuração de aquisição
(padrão 1 s). Campos sem leitura válida são omitidos, nunca inventados. O PZEM
é lido separadamente conforme `pzem_read_ms`.

| Campo | Tipo | Significado |
| --- | --- | --- |
| `device_id` | texto | `esp32-01` |
| `seq` | número | Contador de mensagens |
| `boot` | texto | Sessão da placa (16 hexadecimais); muda a cada reinício. Exigido pelo `start` |
| `ts` | número | Hora da medição em segundos UTC. Ausente enquanto o NTP não responde |
| `voltage`, `current`, `power`, `energy`, `frequency`, `pf` | número | V, A, W, kWh, Hz e fator de potência do PZEM-004T. Omitidos se o PZEM não responder |
| `pzem_ok` | booleano | PZEM respondendo |
| `relays` | 4 booleanos | Estado **comandado** de CNT 1 a CNT 4 (não é leitura física) |
| `relay_pins` | 4 números | GPIO de cada saída |
| `lcd` | 4 textos | As linhas mostradas no LCD 20×4 |
| `mode` | texto | `profile_bench` durante uma partida, senão `manual_relays` |
| `profile`, `profile_ms` | texto, número | Partida em andamento e tempo decorrido |
| `start_phase` | texto | Etapa da partida, como aparece no LCD |
| `actuation` | booleano | `false` = [modo instrumentação](guia-de-uso.md#somente-medição-modo-instrumentação) |
| `run_limit_s` | número | Duração máxima do ensaio; `-1` = sem limite |
| `link_grace_s` | número | Quanto o ensaio segue sem rede; `-1` = sem limite |
| `secure` | booleano | A placa exige comando cifrado |
| `run_s_total` | número | Horímetro, em segundos |
| `starts_total`, `starts_today`, `starts_hour` | número | Partidas no total, hoje (horário de Brasília) e na última hora |
| `session_s` | número | Há quanto tempo o motor está girando (só enquanto gira) |
| `motor_running` | booleano | Motor girando: algum relé ligado ou, no modo instrumentação, corrente acima de 0,3 A. O painel, o app e a placa de sensores usam para mostrar e alarmar o motor ligado |
| `trip_alarm`, `trip_field` | texto | Desarme automático: id e grandeza do alarme que desligou o motor. Só aparecem até a próxima partida (`v16` em diante) |
| `reset_reason`, `wifi_ip` | texto | Diagnóstico |

## Telemetria dos sensores do motor

`iotmotor/esp32-02/telemetry`, conforme o mesmo `publish_ms` publicado pelo
ESP32-01 (padrão 1 s). A aquisição física da vibração continua fixa em 1000 Hz,
com janela RMS de 1 s.

| Campo | Tipo | Significado |
| --- | --- | --- |
| `device_id`, `seq`, `ts`, `secure` | | Como no quadro |
| `vibration_mms` | número | Velocidade de vibração RMS em mm/s, faixa útil aproximada de 10 a 180 Hz, maior valor entre X/Y/Z (`s3-sensors-1.10` em diante); veja [metodologia](vibracao.md) |
| `vibration_axis` | texto | Eixo do MPU6050 com a maior velocidade: `x`, `y` ou `z` |
| `temperature` | número | °C do DS18B20 |
| `mpu_ok`, `temperature_ok` | booleano | Cada sensor respondendo |
| `sample_count` | número | Amostras úteis usadas na janela RMS mais recente; janelas com menos de 500 não são aceitas como válidas |
| `alarm_enabled` | booleano | Interruptor geral dos alarmes |
| `alarm_active` | booleano | Algum alarme disparado ou sensor faltando |
| `alarms_firing` | lista | IDs dos alarmes disparados agora |
| `event_sounds`, `buzzer_hz` | | Bipes de evento ligados e tom do buzzer |
| `motor_on` | booleano | Motor ligado, pelo que o quadro publicou |
| `command_telemetry_fresh` | booleano | A telemetria do quadro chegou há menos de 6 s |

## Mensagens retidas

O broker guarda a última mensagem de cada um destes tópicos e entrega assim que
alguém assina. É por isso que o painel e o app abrem já preenchidos.

**`system/acquisition`**: configuração única do sistema, publicada pelo
ESP32-01 e retida no broker. O ESP32-01 também grava os quatro intervalos
ajustáveis em NVS.

```json
{"v":1,"source":"esp32-01","revision":7,
 "pzem_read_ms":1000,"publish_ms":2000,"chart_ms":5000,"record_ms":5000,
 "vibration_hz":1000,"vibration_window_ms":1000,
 "history_bucket_s":3600,"history_retention_days":7}
```

| Campo | Significado |
| --- | --- |
| `revision` | Revisão crescente da configuração gravada |
| `pzem_read_ms` | Intervalo de leitura elétrica do PZEM, 1000–10000 ms |
| `publish_ms` | Intervalo de publicação MQTT das duas placas, 1000–60000 ms |
| `chart_ms` | Janela temporal dos pontos dos gráficos, de `publish_ms` até 60000 ms |
| `record_ms` | Cadência lógica de registro local, de `publish_ms` até 600000 ms |
| `vibration_hz` | Frequência física fixa da aquisição de vibração: 1000 Hz |
| `vibration_window_ms` | Janela RMS fixa da vibração: 1000 ms |
| `history_bucket_s` | Consolidação fixa do histórico da placa: 3600 s |
| `history_retention_days` | Retenção fixa do histórico da placa: 7 dias |

As relações válidas são `pzem_read_ms <= publish_ms <= chart_ms` e
`publish_ms <= record_ms`. Painel e app carregam a mensagem retida ao conectar
e também podem pedir explicitamente que o ESP32-01 a republique.

**`capabilities`**

```json
{"device_id":"esp32-01","role":"actuator_mqtt","firmware_version":"v17-ota-seguro","fields":["voltage","current","power","energy","frequency","pf"]}
```

**`motor_info`**: dados da placa do motor. Todos são opcionais; campo ausente é
dado não cadastrado.

```json
{"device_id":"esp32-01","power_cv":5,"voltage_v":220,"voltage_y_v":380,"current_a":12.6,"current_y_a":7.3,
 "phases":3,"connection":"delta","rpm":1730,"service_factor":1.15,"frequency_hz":60,
 "power_factor":0.82,"efficiency_pct":91.7,"efficiency_class":"IE3","duty":"S1",
 "insulation_class":"F","ambient_temp_c":40,"temperature_rise_k":80,"ip_rating":"IP55",
 "manufacturer":"WEG","model":"W22","serial_number":"ABC123",
 "maint_interval_h":2000,"maint_done_run_s":1485000,"maint_done_utc":1790000000}
```

- `voltage_v`/`current_a` são os da ligação **triângulo** (menor tensão). `voltage_y_v`/`current_y_a` são os da **estrela**. Só existem em motor trifásico de dupla tensão.
- `connection`: ligação em que o motor trabalha, `delta` ou `star`.
- `frequency_hz`, `power_factor` e `efficiency_pct`: valores nominais da placa, não as leituras instantâneas do PZEM.
- `efficiency_class`: `IE1` a `IE5`; `duty`: `S1` a `S10`; `insulation_class`: `A`, `E`, `B`, `F`, `H`, `N` ou `R`.
- `ambient_temp_c` e `temperature_rise_k`: ambiente máximo e elevação de temperatura informados pelo fabricante.
- `ip_rating`, `manufacturer`, `model` e `serial_number`: proteção e identificação/rastreabilidade do motor.
- `maint_done_run_s`: horímetro (s) quando a última manutenção foi registrada; `maint_done_utc`: a data dela.

**`profiles`**: partidas gravadas no quadro (até 6).

```json
{"device_id":"esp32-01","max":6,"limit_ms":300000,"run_limit_s":300,
 "profiles":[{"id":"estrela_triangulo","name":"Estrela-triângulo",
   "cnt":[{"use":true,"on":500,"off":0},{"use":true,"on":500,"off":5500},{"use":true,"on":6200,"off":0},{"use":false,"on":0,"off":0}]}]}
```

Cada `cnt` é um contator: `on` e `off` em ms desde o início da partida (`off: 0` = fica ligado até parar).

**`alarms`**: lista de alarmes da placa de sensores (até 8).

```json
{"device_id":"esp32-02","max":8,"buzzer_hz":2000,
 "alarms":[{"id":"temp","field":"temperature","board":"sensors","above":true,"limit":60,"on":true,"trip":false,"firing":false}]}
```

| `board` | Grandezas (`field`) |
| --- | --- |
| `sensors` | `vibration_mms`, `temperature` |
| `command` | `voltage`, `current`, `power`, `energy`, `frequency`, `pf`, `starts_hour` |

Uma leitura com mais de 15 s não dispara nem silencia um alarme. Na primeira vez,
a placa cria dois alarmes: vibração acima de 4,5 mm/s (`vibration_mms`) e temperatura acima de 60 °C.
Na atualização, alarmes antigos de aceleração em g (`vibration_peak`, `vibration`) viram `vibration_mms` com limite de 4,5 mm/s.

**`alarm_log`**: os 10 últimos disparos, com `value` no início, `start`/`end` em
UTC (quando há hora) e `seconds` de duração. É zerado quando a placa reinicia.

**`history/<0..6>`**: um dia do histórico por hora. O número do tópico é `dia % 7`.

```json
{"device_id":"esp32-02","day":20722,"v":1,"vib":"mm/s","hours":[[14,912,1034,2201,452,480,231,455,60]]}
```

- `day`: dias desde 1970, em UTC.
- Cada linha tem: `[hora UTC, corrente média, corrente máx, tensão média, temperatura média, temperatura máx, vibração média, vibração máx, minutos ligado]`.
- Escalas: corrente em centésimos de A, tensão e temperatura em décimos, vibração em centésimos de mm/s. `null` = sem leitura.
- `vib`: unidade da vibração do dia. Sem ele (dias gravados por firmware antigo), a vibração está em milésimos de g e o painel e o app a deixam de fora.
- Corrente e vibração só são contadas com o motor girando.

**`wifi`**: `networks` (`ssid`, `open`), `connected`, `max` (8), `ap` (rede
própria da placa: `name`, `open`) e `pubkey`, a chave pública P-256 usada para
cifrar senhas novas. Nenhuma senha é publicada.

`diagnostics` traz a saúde da placa: `rssi` (dBm, `0` sem Wi-Fi),
`connected_ms` (tempo na rede atual), `last_network`, `reconnections`,
`disconnect_reason` (código do ESP-IDF), `uptime_ms`, `heap_bytes`,
`min_heap_bytes` e `reset_reason` (código de `esp_reset_reason()`). A placa
republica o tópico ao conectar no broker e a cada 30 s enquanto conectada
(`v26` do quadro e `s3-sensors-1.20` em diante).

**`auth`**: `{"v":1,"device_id":"esp32-01","secure":true,"challenge":"…"}`.

## Como enviar um comando

Publique em `iotmotor/<placa>/command` um JSON com estes campos:

| Campo | Obrigatório | Regra |
| --- | :---: | --- |
| `v` | ✔ | Sempre `1` |
| `device_id` | ✔ | A placa de destino; comando para outro ID é ignorado |
| `seq` | ✔ | Número em texto, sem zero à esquerda, até 18 dígitos. Use algo crescente, como `Date.now()*1000` |
| `action` | ✔ | O comando |
| `boot` | só no `start` | O `boot` da telemetria atual |

A placa responde em `iotmotor/<placa>/command_ack`:

```json
{"device_id":"esp32-01","seq":"1790000000000001","accepted":true,"action":"stop","reason":"stopped","phase":"Parado / comando manual"}
```

Exemplo com o `mosquitto_pub`:

```sh
mosquitto_pub -h test.mosquitto.org -t iotmotor/esp32-01/command \
  -m '{"v":1,"device_id":"esp32-01","seq":"1790000000000001","action":"stop"}'
```

## Comandos do quadro de comando

`device_id: "esp32-01"`.

| `action` | Campos | O que faz |
| --- | --- | --- |
| `stop` | `reason`, `alarm`, `field` (opcionais) | Desliga todas as saídas e cancela a partida. **Sempre aceito**, sem `boot` nem ordem de `seq`. Com `reason: "alarm"` (enviado pela placa de sensores no desarme), o quadro guarda `alarm` e `field` e os publica em `trip_alarm`/`trip_field` |
| `start` | `boot`, `profile` | Dá a partida gravada com esse `id`. Veja as condições abaixo |
| `profile_list` | — | Republica a lista de partidas |
| `profile_save` | `profile` | Cria ou edita uma partida (formato de `profiles`); nome até 24 bytes |
| `profile_remove` | `id` | Remove uma partida |
| `run_limit` | `seconds` | Duração máxima do ensaio: 10 a 7200 s, ou `-1` sem limite |
| `link_grace` | `seconds` | Quanto o ensaio segue sem rede: `0` cai na hora, até 3600 s, ou `-1` sem limite |
| `actuation` | `on` | `false` entra no modo instrumentação (a placa não aciona nada); `true` libera |
| `motor_info_set` | `motor` | Grava os dados do motor (formato de `motor_info`, sem os campos `maint_done_*`) |
| `maintenance_done` | — | Registra a manutenção agora: o lembrete volta a contar do horímetro atual |
| `motor_counters_reset` | — | Zera horímetro, partidas e a contagem da manutenção. Só com o motor parado |
| `acquisition_config_get` | — | Republica `iotmotor/system/acquisition` com a configuração oficial gravada no ESP32-01 |
| `acquisition_config_set` | `config` | Valida, grava em NVS, incrementa `revision` e republica a configuração de aquisição |

**Condições do `start`.** A placa recusa se:

- estiver no modo instrumentação;
- o `boot` não for o da sessão atual;
- o `seq` não for maior que o do último `start` aceito;
- já houver partida em andamento ou o Wi-Fi estiver fora;
- alguma saída estiver ligada.

Depois de aceitar, a placa começa com tudo desligado e segue os tempos da
partida, contados a partir do comando. Todas as saídas caem sozinhas quando:

- passa a duração máxima do ensaio (padrão 5 min);
- a rede fica fora por mais que `link_grace` (padrão 15 s).

**Validação do `acquisition_config_set`:**

- `pzem_read_ms`: 1000 a 10000 ms;
- `publish_ms`: 1000 a 60000 ms;
- `pzem_read_ms <= publish_ms`;
- `chart_ms`: de `publish_ms` até 60000 ms;
- `record_ms`: de `publish_ms` até 600000 ms.

Os campos fixos de vibração e histórico não são alterados por esse comando.

**Validação do `motor_info_set`:**

- potência de 0 a 3000 cv;
- tensão de 0 a 1000 V e corrente de 0 a 2000 A;
- rotação de 0 a 10000 rpm;
- fator de serviço vazio ou de 1 a 3;
- frequência de 0 a 1000 Hz, fator de potência de 0 a 1 e rendimento de 0 a 100%;
- classe de rendimento `IE1`–`IE5`, regime `S1`–`S10` e classe de isolação `A`, `E`, `B`, `F`, `H`, `N` ou `R`;
- temperatura ambiente de 0 a 100 °C e elevação térmica de 0 a 250 K;
- grau de proteção no formato `IP55`, fabricante/modelo com até 40 bytes e número de série com até 32 bytes;
- `phases` 1 ou 3;
- manutenção de 0 a 100000 h.

Os valores da estrela só são aceitos em motor trifásico, com tensão maior e
corrente menor que as do triângulo.

> O formato antigo do `start` (`mode: "direct"` com `mask`, ou `mode: "sequence"`
> com `main`, `star`, `delta` e `seconds`) ainda é aceito e convertido numa
> partida temporária.

## Comandos dos sensores do motor

`device_id: "esp32-02"`. Ação desconhecida é ignorada, sem resposta.

| `action` | Campos | O que faz |
| --- | --- | --- |
| `alarm_set` | `enabled`, `sounds`, `buzzer_hz` | Interruptor geral, bipes de evento e tom do buzzer (500 a 5000 Hz) |
| `alarm_list` | — | Republica a lista e o registro de disparos |
| `alarm_save` | `alarm` | Cria ou edita um alarme pelo `id` (até 12 letras) |
| `alarm_remove` | `id` | Remove um alarme |
| `alarm_test` | `freq` | LED e buzzer por 1,5 s |
| `led_test` | — | Azul, verde e vermelho, sem buzzer |
| `buzzer_beep` | `count` (1–5), `ms` (20–2000), `freq` | Bipe curto |
| `buzzer_probe` | `ms` (200–2000) | Procura o buzzer tocando cada pino livre, primeiro como passivo e depois como ativo |

```json
{"v":1,"device_id":"esp32-02","seq":"1790000000000002","action":"alarm_save",
 "alarm":{"id":"current","field":"current","board":"command","above":true,"limit":14.49,"on":true,"trip":false}}
```

`trip: true` liga o **desarme** daquele alarme (`s3-sensors-1.8` em diante):
com o quadro acionando o motor, disparar faz a placa de sensores mandar ao
quadro `{"action":"stop","reason":"alarm","alarm":"<id>","field":"<grandeza>"}`,
repetido a cada 3 s enquanto o alarme seguir disparado. No `alarm_log`, o
episódio que desligou o motor sai com `"trip":true`.

## Comandos das duas placas

| `action` | Campos | O que faz |
| --- | --- | --- |
| `update` | — | Baixa o firmware do release `firmware-latest` e reinicia. No quadro, só com as saídas desligadas |
| `restart` | — | Reinicia a placa. No quadro, só com as saídas desligadas |
| `wifi_portal` | — | Abre a rede própria da placa por 180 s para cadastrar Wi-Fi pelo celular |
| `wifi_list` | — | Republica as redes |
| `wifi_add` | `ssid`, `open`, `position`, `epk`, `iv`, `ct` | Grava uma rede. A senha vai cifrada para a chave `pubkey` da placa |
| `wifi_remove` | `ssid` | Remove uma rede |
| `wifi_order` | `order` (lista de SSIDs) | Define a ordem de tentativa |
| `wifi_ap` | `name`, `open`, `epk`, `iv`, `ct` | Nome e senha da rede própria da placa |

A URL do `update` é fixa no firmware ([`ota_update.h`](../esp32/iotmotor_esp32/iotmotor_esp32_comandos/ota_update.h)):
o comando só dispara a atualização e não escolhe de onde baixar.

A senha do Wi-Fi é cifrada assim:

1. ECDH P-256 com uma chave efêmera contra a `pubkey` da placa;
2. a chave AES sai de `SHA-256("iotmotor-wifi-v1" ‖ segredo)`;
3. a senha vai em AES-GCM, com o SSID como dado autenticado.

O código de referência está em [`wifi-manager.js`](../dashboard-cloudflare/wifi-manager.js).

## Comandos cifrados

Com a senha de comando gravada ([como ligar](firmware.md#senha-de-comando)), a
placa só aceita comando assim:

```json
{"v":1,"device_id":"esp32-01","sealed":"<base64 de iv(12) + texto cifrado + tag(16)>"}
```

- **Chave:** `SHA-256("iotmotor-cmd-v1" ‖ senha ‖ device_id)`. Por isso, um comando selado para uma placa não vale para a outra.
- **Cifra:** AES-256-GCM, com o `device_id` como dado autenticado.
- **Conteúdo:** o comando normal (`v`, `device_id`, `seq`, `action`, …) mais `ch`, o desafio publicado em `auth`.
- **Repetição:** a placa sorteia outro desafio a cada comando aceito e a cada reinício, então um comando copiado do ar não vale de novo.
- **Exceção:** `stop` vale sem selo e com desafio vencido (firmware `v15` em diante). Parar é o lado seguro, e dois clientes mandando ao mesmo tempo não podem impedir a parada.

Implementações de referência: [`command-seal.js`](../dashboard-cloudflare/command-seal.js)
(painel) e [`command_seal.dart`](../lib/features/iot_motor/services/command_seal.dart) (app).

## Motivos de recusa

`reason` vem em texto. Os mais comuns:

| `reason` | Causa |
| --- | --- |
| `unknown_action` | Firmware antigo, que não conhece esse comando. O painel mostra "atualize a placa" |
| `session_mismatch` | `boot` diferente: a placa reiniciou depois da última telemetria |
| `duplicate` | `seq` repetido ou menor que o último `start` |
| `busy_or_offline` | Partida em andamento ou Wi-Fi fora |
| `already_on` | Alguma saída já ligada |
| `invalid_profile` / `partida nao encontrada na placa` | Partida inválida ou inexistente |
| `saidas ligadas: pare antes de …` | Atualizar, reiniciar, abrir portal ou zerar com saídas ligadas |
| `modo instrumentacao: acionamento desligado` | `start` com o acionamento desligado |
| `comando sem selo: configure a senha de comando` | A placa exige comando cifrado |
| `desafio vencido: envie de novo` | O comando usou um desafio antigo |
