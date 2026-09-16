# IoTMotor

Aplicativo Flutter para controle e monitoramento de motores via MQTT.

## Arquitetura de dois modulos

O sistema e composto por dois modulos ESP32 que dividem os papeis e conversam
pelo mesmo broker MQTT que o aplicativo.

Os modulos **nao servem pagina web**. Existem duas interfaces, e as duas falam
com o broker, nunca com o ESP32:

- **Aplicativo** — o projeto Flutter deste repositorio (Android, iOS e desktop);
- **Dashboard web** — `dashboard_iotmotor/`, em React + Vite, publicado no
  Cloudflare Pages.

O que existe no modulo e apenas sinalizacao para quem esta junto da bancada:
LCD 20x4 no Modulo 1, LED RGB e buzzer no Modulo 2.

| | Modulo 1 | Modulo 2 |
| --- | --- | --- |
| Placa | ESP32 DevKit V1 | ESP32-S3 DevKitC N8R2 |
| `device_id` | `esp32-01` | `esp32-02` |
| Papel | aciona o motor e mede as grandezas eletricas | coleta os dados do motor usados no controle |
| Sensores | PZEM-004T v3 | MPU6050 + DS18B20 |
| Grandezas | `voltage`, `current`, `power`, `pf`, `frequency`, `energy` | `vibration`, `temperature` |
| Atuadores | 4 reles (K1..K4) | — |
| Armazenamento | — | cartao SD, um arquivo por dia |
| Sinalizacao local | LCD I2C 20x4 | LED RGB + buzzer |
| Sketch | `esp32/iotmotor_modulo1_acionamento/` | `esp32/iotmotor_modulo2_sensores/` |

Os sketches em `esp32/iotmotor_esp32/` sao **simuladores**: publicam telemetria
gerada por software e servem para testar o aplicativo sem a bancada montada. Os
dois sketches acima sao os de hardware real.

### Fluxo

```
   app Flutter        ──┐  TCP 1883
                        ├─►  broker MQTT  ─┬─►  Modulo 1 (esp32-01) ─► contatores ─► MOTOR
   dashboard web (SPA)──┘  WSS 8081        │         ▲                                │
                                           │         │ vibracao / temperatura         │
                                           └─►  Modulo 2 (esp32-02) ◄──── sensores ───┘
```

O firmware publica em TCP puro; o navegador nao abre socket TCP, entao o
dashboard assina os mesmos topicos pelo listener WebSocket seguro do broker.

O Modulo 1 assina `iotmotor/esp32-02/telemetry` e usa vibracao e temperatura como
**protecao cruzada**: acima dos limites configurados ele abre os contatores e
publica o motivo em `iotmotor/esp32-01/status`. A protecao fica travada ate que um
comando explicito de parada rearme o acionamento.

### Partida estrela-triangulo

O Modulo 1 usa quatro reles e uma maquina de estados nao bloqueante:

| Rele | GPIO | Funcao |
| --- | --- | --- |
| K1 | 19 | contator de linha |
| K2 | 18 | contator de estrela |
| K3 | 23 | contator de triangulo |
| K4 | 27 | auxiliar / sinalizacao |

- `mode: "direct"` — fecha K1 e K3 (motor em triangulo, tensao plena).
- `mode: "star_delta"` — fecha K2, depois K1; apos `TEMPO_ESTRELA_MS` abre K2,
  aguarda `TEMPO_MORTO_MS` e fecha K3.
- `command: "stop"` — abre todos os contatores.

K2 e K3 nunca sao fechados ao mesmo tempo: o intertravamento e aplicado dentro de
`aplicarContatores()` e tambem na rota `/rele`, que so aceita comandos avulsos com
o motor parado.

## Interfaces

### Aplicativo Flutter

Android, iOS e desktop. Conecta por MQTT sobre TCP (`MqttServerClient`), guarda
historico local, exporta CSV/PDF e emite alertas. E o cliente completo.

### Dashboard web

`dashboard_iotmotor/` — React + Vite, publicado no **Cloudflare Pages**. Conecta
por MQTT sobre WebSocket seguro (`wss://`), que e obrigatorio numa pagina servida
em HTTPS. Tres abas: Monitoramento, Acionamento e Configuracoes.

Nao e o app Flutter compilado para web: `MqttServerClient` depende de `dart:io`
e nao roda no navegador. O dashboard e um cliente separado que fala o mesmo
protocolo. Detalhes de deploy em [`dashboard_iotmotor/README.md`](dashboard_iotmotor/README.md).

## Mapa de topicos MQTT

Com `topic_prefix` igual a `iotmotor` (padrao do aplicativo):

| Topico | Sentido | Quem usa |
| --- | --- | --- |
| `iotmotor/<device_id>/telemetry` | modulo → app | ambos publicam |
| `iotmotor/<device_id>/status` | modulo → app | ambos publicam (retido, com LWT `offline`) |
| `iotmotor/<device_id>/capabilities` | modulo → app | ambos publicam (retido) |
| `iotmotor/<device_id>/command` | app → modulo | comando direcionado |
| `iotmotor/request/command` | app → modulos | comando em broadcast e `storage_config` |
| `iotmotor/request/telemetry` | app → modulos | pedido de leitura sob demanda |

Um payload em `request/...` sem `device_id` vale para todos os modulos; com
`device_id`, apenas para o modulo indicado.

Valores publicados em `status`: `online`, `offline`, `motor_started`,
`motor_running`, `motor_stopped`, `unknown_command`, `invalid_command_json`,
`blocked_by_protection`, `protection_overcurrent`, `protection_overvoltage`,
`protection_undervoltage`, `protection_vibration`, `protection_temperature`,
`storage_config_applied`, `storage_config_invalid`.

## Comportamento sem rede

Como o comando so chega pelo broker, vale saber o que cada modulo faz sozinho:

- **Modulo 1** mantem o estado atual dos contatores (uma queda de rede nao derruba
  o motor) e segue avaliando as protecoes eletricas, que sao locais e independem
  do broker. A protecao cruzada e suspensa quando a telemetria do Modulo 2
  envelhece mais que `VALIDADE_TELEMETRIA_SENSORES_MS`, para nao parar a maquina
  por falha de comunicacao. O LCD continua mostrando estado, medicao e se o MQTT
  esta conectado.
- **Modulo 2** continua medindo, sinalizando estado critico no LED e no buzzer e
  gravando no cartao SD. Quando a rede volta, as leituras do periodo ficam no SD;
  o modulo nao republica o historico.

Enquanto o broker estiver fora, nao ha como partir ou parar o motor remotamente:
o acionamento depende do comando MQTT.

## Antes de gravar

Ajuste no topo de cada sketch: `WIFI_SSID`, `WIFI_PASSWORD`, `MQTT_HOST`,
`MQTT_PORT`, credenciais do broker e `TOPIC_PREFIX`. Em `iotmotor_modulo1_acionamento`
confira ainda `RELE_ATIVO_EM_NIVEL_BAIXO` (muitos modulos de rele prontos acionam
em nivel baixo) e os limites das protecoes.

O broker padrao dos tres clientes e `test.mosquitto.org` — publico, sem
autenticacao. Ele foi escolhido por ter listener WebSocket seguro documentado na
porta 8081, sem o qual o dashboard em HTTPS nao conecta. Para trocar de broker,
mude nos tres lugares: `MQTT_HOST` nos dois sketches, o broker padrao do app
Flutter e a URL no painel web.

> **Atencao:** num broker publico qualquer pessoa que descubra o prefixo de
> topicos pode publicar em `iotmotor/esp32-01/command` e partir o motor. Para uso
> alem da bancada, use um broker com usuario, senha e TLS.

Bibliotecas necessarias: PubSubClient, ArduinoJson 6.x, PZEM004Tv30, LiquidCrystal
I2C, OneWire e DallasTemperature.

## Telemetria MQTT

O app aceita payloads JSON com uma ou mais grandezas no topico de telemetria.

Exemplo completo:

```json
{
  "voltage": 220.4,
  "current": 3.9,
  "power": 858,
  "pf": 0.98,
  "frequency": 60,
  "energy": 1.234,
  "vibration": 0.12,
  "temperature": 37.8
}
```

Tambem podem ser enviados payloads parciais:

```json
{"voltage": 220.4}
{"current": 3.9}
{"power": 858, "pf": 0.98, "frequency": 60, "energy": 1.234}
{"vibration": 0.12}
{"temperature": 37.8}
```

Quando os valores vierem dentro de `data`, o app tambem faz a leitura:

```json
{
  "data": {
    "voltage": "220.4",
    "current": "3.9",
    "power": "858",
    "pf": "0.98",
    "frequency": "60",
    "energy": "1.234",
    "vibration": "0.12",
    "temperature": "37.8"
  }
}
```

## Armazenamento remoto no ESP32

A aba Configuracoes > Armazenamento permite definir a retencao local do app e
a retencao remota que o ESP32 deve aplicar aos arquivos salvos no SD card.

Ao aplicar a retencao remota, o app publica no topico
`<topic_prefix>/request/command` um payload como este:

```json
{
  "type": "storage_config",
  "request_id": "storage_...",
  "storage": {
    "medium": "sdcard",
    "retention_days": 30
  },
  "remote_retention_days": 30,
  "retention_days": 30,
  "reason": "settings_storage_tab",
  "origin": "flutter_app",
  "timestamp": "2026-05-08T12:00:00.000"
}
```

O Modulo 2 (`esp32-02`) implementa esse payload: grava um arquivo por dia em
`/logs/AAAAMMDD.csv`, persiste a retencao em NVS e apaga os arquivos mais antigos
que o limite, tanto ao receber a configuracao quanto periodicamente. Sem hora
sincronizada por NTP ele nao apaga nada, para nao remover registros por engano.

Na interface, o operador pode digitar a retencao em dias, meses ou anos. O app
converte o valor para dias antes de persistir localmente ou enviar ao ESP32.
