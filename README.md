# IoTMotor

Aplicativo Flutter para controle e monitoramento de motores via MQTT.

## Arquitetura de dois modulos

O sistema e composto por dois modulos ESP32 que dividem os papeis e conversam
pelo mesmo broker MQTT que o aplicativo. Cada modulo tambem serve uma pagina web
propria, de modo que a planta continua operavel mesmo sem o aplicativo.

| | Modulo 1 | Modulo 2 |
| --- | --- | --- |
| Placa | ESP32 DevKit V1 | ESP32-S3 DevKitC N8R2 |
| `device_id` | `esp32-01` | `esp32-02` |
| Papel | aciona o motor e mede as grandezas eletricas | coleta os dados do motor usados no controle |
| Sensores | PZEM-004T v3 | MPU6050 + DS18B20 |
| Grandezas | `voltage`, `current`, `power`, `pf`, `frequency`, `energy` | `vibration`, `temperature` |
| Atuadores | 4 reles (K1..K4) | LED RGB + buzzer |
| Armazenamento | — | cartao SD, um arquivo por dia |
| Interface local | LCD I2C 20x4 + `http://modulo1.local/` | `http://modulo2.local/` |
| Sketch | `esp32/iotmotor_modulo1_acionamento/` | `esp32/iotmotor_modulo2_sensores/` |

Os sketches em `esp32/iotmotor_esp32/` sao **simuladores**: publicam telemetria
gerada por software e servem para testar o aplicativo sem a bancada montada. Os
dois sketches acima sao os de hardware real.

### Fluxo

```
      aplicativo Flutter  ─┐
                           ├─►  broker MQTT  ─┬─►  Modulo 1 (esp32-01)  ──► contatores ──► MOTOR
      pagina web local  ───┘                  │         ▲                                    │
                                              │         │ vibracao / temperatura             │
                                              └─►  Modulo 2 (esp32-02)  ◄────── sensores ────┘
```

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

## Rotas HTTP locais

Modulo 1 (`http://modulo1.local/`):

| Rota | Efeito |
| --- | --- |
| `GET /` | painel de operacao |
| `GET /dados` | estado completo em JSON |
| `GET /comando?tipo=direct\|star_delta\|stop` | comanda o motor |
| `GET /rele?canal=1..4&estado=0\|1` | rele avulso (apenas com o motor parado) |

Modulo 2 (`http://modulo2.local/`):

| Rota | Efeito |
| --- | --- |
| `GET /` | painel de leituras |
| `GET /dados` | estado completo em JSON |
| `GET /retencao?dias=N` | ajusta a retencao do SD sem passar pelo broker |

## Antes de gravar

Ajuste no topo de cada sketch: `WIFI_SSID`, `WIFI_PASSWORD`, `MQTT_HOST`,
`MQTT_PORT`, credenciais do broker e `TOPIC_PREFIX`. Em `iotmotor_modulo1_acionamento`
confira ainda `RELE_ATIVO_EM_NIVEL_BAIXO` (muitos modulos de rele prontos acionam
em nivel baixo) e os limites das protecoes.

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
