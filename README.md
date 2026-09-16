# IoTMotor

Aplicativo Flutter para controle e monitoramento de motores via MQTT.

## Arquitetura de dois modulos

O sistema e composto por dois modulos ESP32 que dividem os papeis e conversam
pelo mesmo broker MQTT que o aplicativo.

Os modulos **nao servem pagina web**. O que eles expoem na rede local e uma API
JSON de diagnostico e atualizacao de firmware (ver "Acesso local e atualizacao"),
nao uma interface. As duas interfaces de operacao falam com o broker:

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

### Identidade visual

As duas interfaces compartilham a mesma paleta — fundo `#0F172A`, superficie
`#1B2336`, azul de destaque `#5EA8FC` — e os mesmos acentos por grandeza, para
que quem olha o painel e o app reconheca as mesmas cores nas mesmas medidas.

- No app, isso e a variante `AppVisualVariant.blueprint` em
  `lib/app/theme/app_theme.dart`. As variantes `modern` e `industrial` continuam
  no arquivo: trocar `activeVariant` volta ao visual anterior, e nada mais
  depende dessa linha.
- No dashboard, os tokens estao em `dashboard_iotmotor/src/theme.js` e
  `src/style.css`.

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

Payloads aceitos em `request/command` e `<device>/command`, pelo campo `type`:
`command_request` (partida/parada, so o Modulo 1), `storage_config` (retencao do
SD, so o Modulo 2) e `ota` (atualizacao remota, os dois).

Valores publicados em `status`: `online`, `offline`, `motor_started`,
`motor_running`, `motor_stopped`, `unknown_command`, `invalid_command_json`,
`blocked_by_protection`, `protection_overcurrent`, `protection_overvoltage`,
`protection_undervoltage`, `protection_vibration`, `protection_temperature`,
`storage_config_applied`, `storage_config_invalid`, e os da atualizacao:
`ota_local_started`, `ota_local_applied`, `ota_local_failed`, `ota_push_started`,
`ota_push_applied`, `ota_push_failed`, `ota_remote_started`, `ota_remote_applied`,
`ota_remote_failed`, `ota_refused`, `ota_refused_url`, `ota_refused_version`,
`ota_invalid_request`.

## Acesso local e atualizacao

Alem do MQTT, cada modulo sobe um servico na rede local — mesmo desenho do
firmware do E-Metrics IoT. Nao e um painel: sao rotas JSON para diagnostico e
para gravar firmware.

| Rota | Metodo | Para que serve |
|---|---|---|
| `/health` | GET | Estado completo: versao, heap, RSSI, IP e o estado do modulo |
| `/wifi-networks` | GET | Varredura de redes Wi-Fi ao alcance |
| `/provision` | GET | Configuracao em uso, sem as senhas |
| `/provision` | POST | Grava Wi-Fi, broker e prefixo de topicos; reinicia |
| `/provision/reset` | POST | Apaga o provisionamento e volta aos padroes compilados |
| `/firmware/update` | POST | Upload de firmware (multipart) |

Todas as rotas de escrita — e a leitura do provisionamento — exigem o cabecalho
`X-IoTMotor-OTA-Key`. Só `/health` e `/wifi-networks` sao abertas.

Os modulos respondem em `http://esp32-01.local/` e `http://esp32-02.local/` via
mDNS, ou pelo IP. O botao "testar comunicacao local" da aba Configuracoes do app
chama `/wifi-networks` — ate agora ele apontava para um endpoint que nenhum
firmware implementava.

### Provisionamento

Os valores de Wi-Fi e broker no topo de cada sketch sao **padrao de fabrica**:
valem enquanto nao houver nada gravado. Depois de um `POST /provision`, a NVS
vence e a placa muda de rede ou de broker sem recompilar.

| Campo | Obrigatorio | Observacao |
|---|---|---|
| `ssid` | sim | Rede Wi-Fi |
| `wifiPassword` | nao | Vazio para rede aberta |
| `mqttHost` | sim | |
| `mqttPort` | nao | Padrao 1883 |
| `mqttUser`, `mqttPassword` | nao | |
| `topicPrefix` | sim | Ex.: `iotmotor` |
| `useTls` | nao | `1` liga MQTT sobre TLS |
| `otaKey` | nao | Troca a chave; minimo 8 caracteres |

```bash
curl -X POST http://esp32-01.local/provision \
  -H "X-IoTMotor-OTA-Key: SUA-CHAVE" \
  -d ssid="RedeDaPlanta" -d wifiPassword="senha" \
  -d mqttHost="broker.exemplo.com" -d mqttPort=8883 -d useTls=1 \
  -d mqttUser="iotmotor" -d mqttPassword="segredo" \
  -d topicPrefix="iotmotor-ifma-7f3a"
```

Esse comando e o caminho pratico para sair do broker publico: liga TLS e
autenticacao e troca o prefixo por um dificil de adivinhar, sem recompilar nada.
O `device_id` continua sendo de compilacao — e a identidade do modulo, e deixar
que um pedido de rede a mude orfanaria o dispositivo no painel.

No app, a aba Configuracoes tem o botao **Provisionar modulo**, ao lado de
"Testar comunicacao local". Ele pede a chave, le `/health` e `/provision` para
mostrar qual modulo respondeu e o que esta valendo, varre as redes pelo proprio
ESP32 (`/wifi-networks`) e grava. Restaurar padroes de fabrica esta na mesma
tela.

**Divergencia deliberada do E-Metrics:** la o `/provision` e aberto. Aqui exige a
chave. Num modulo que aciona motor, um endpoint aberto na rede local deixaria
qualquer um apontar o dispositivo para outro broker — e quem controla o broker
controla o motor.

### Tres caminhos de atualizacao

| Caminho | Como | Quando usar |
|---|---|---|
| **ArduinoOTA** | Push pela IDE, pela rede local | Desenvolvimento na bancada |
| **Upload HTTP** | `POST /firmware/update` com a chave | Gravar sem a IDE, pelo app ou por `curl` |
| **Remota** | Payload `{"type":"ota","url":...}` no topico de comando; o modulo baixa por HTTPS | Atualizar a planta a partir de um release |

Exemplo de upload local:

```bash
curl -X POST http://esp32-01.local/firmware/update \
  -H "X-IoTMotor-OTA-Key: SUA-CHAVE" \
  -F "firmware=@iotmotor_modulo1_acionamento.ino.bin"
```

Exemplo de atualizacao remota, publicada no topico de comando do modulo:

```json
{
  "type": "ota",
  "device_id": "esp32-01",
  "url": "https://github.com/<owner>/<repo>/releases/download/v1.2.0/modulo1.bin",
  "version": "1.2.0"
}
```

### O que protege isso

O broker e publico, entao o disparo da atualizacao remota nao e confiavel por
si. As defesas estao no modulo:

- **Prefixo de URL fixado em tempo de compilacao** (`OTA_URL_PREFIX`). Uma URL
  que nao comece exatamente com ele e recusada antes de qualquer download. Quem
  disparar de fora so consegue apontar para o *seu* endereco de releases — nao
  vira execucao de codigo arbitrario.
- **Recusa de versao igual ou anterior**, o que fecha o downgrade para uma
  versao antiga com falha conhecida.
- **HTTPS obrigatorio**, com o pacote de certificados raiz do proprio core.
- **Chave de 8+ caracteres** (`OTA_KEY`) para o upload local, o ArduinoOTA e o
  provisionamento, comparada em tempo constante. Com menos que isso, o upload
  local e o ArduinoOTA ficam desligados.
- **Modulo 1 recusa atualizar com o motor acionado.** A gravacao termina em
  reboot e no reset os reles caem: o motor pararia sozinho no meio da operacao.

Duas ressalvas honestas:

1. **Nao ha rollback automatico.** O bootloader que o Arduino distribui nao vem
   com `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE`. A protecao que existe e o
   `Update.end()` validando a imagem antes de trocar a particao ativa — uma
   imagem que grave inteira mas trave no boot exige acesso fisico.
2. **Nada disso substitui broker autenticado.** O prefixo fixado reduz a
   gravidade, nao elimina. Para uso alem da bancada, use broker com usuario e
   senha, e considere assinatura de imagem.

### Tabelas de particao

OTA exige dois slots de aplicacao: o firmware roda em um enquanto o outro
recebe a imagem. Cada sketch traz o seu `partitions.csv`; na IDE, selecione
Ferramentas > Esquema de Particao > **Custom**.

Tamanhos medidos na compilacao do CI (core esp32 3.3.11), nao estimados:

| | Flash | Slot de OTA | Binario atual | Ocupacao |
|---|---|---|---|---|
| Modulo 1 | 4 MB | 1,94 MB cada | 1.235.952 B | 60,8% |
| Modulo 2 | 8 MB | 3,94 MB cada | 1.286.160 B | 31,2% |

O Modulo 2 usa menos de um terco do slot: o runtime do TFLite Micro e o modelo
previstos para ele cabem com folga para mais que dobrar. O workflow refaz essa
conta a cada compilacao e reprova se o binario nao couber, avisando acima de
85%.

Nenhum dos dois usa sistema de arquivos na flash interna — o Modulo 2 grava no
SD e usa NVS para a retencao — entao o espaco que os esquemas padrao dariam ao
SPIFFS foi para os slots de aplicacao.

### Biblioteca compartilhada

O servico de rede dos dois modulos vive em `esp32/libraries/IoTMotorNet/`, para
nao duplicar codigo. Para compilar pela IDE, copie essa pasta para
`~/Arduino/libraries/`. O workflow de CI usa `--libraries esp32/libraries` e nao
precisa de instalacao.

### Compilacao automatica

`.github/workflows/firmware.yml` compila os dois sketches com `arduino-cli` a
cada push em `esp32/`, confere o tamanho de cada binario contra o slot de OTA
(falha se nao couber, avisa acima de 85%) e publica os `.bin` como artefato.
Numa tag `v*`, anexa os binarios ao release.

> **Repositorio privado:** um release de repo privado exige token para baixar, e
> gravar token no firmware e ruim — quem tiver a placa extrai. As saidas sao
> tornar o repositorio publico, publicar os binarios num repo publico separado,
> ou hospedar no Cloudflare. `OTA_URL_PREFIX` acompanha a escolha.

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

Se o Wi-Fi da planta nao voltar, cada modulo levanta um ponto de acesso de
emergencia (`IoTMotor-M1-Setup` / `IoTMotor-M2-Setup`) apos 90 s, para que de
para alcancar `/health` e gravar firmware sem abrir o painel eletrico.

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

Troque tambem `OTA_KEY` nos dois sketches: o valor versionado e um marcador, e
com ele qualquer um na rede local grava firmware ou reaponta o broker do modulo.

Os valores de Wi-Fi e broker sao apenas o padrao de fabrica — depois de
provisionar pela rede, a NVS manda. `POST /provision/reset` volta aos
compilados.

Bibliotecas necessarias, com o nome do indice do Library Manager:
`PubSubClient`, `ArduinoJson` (6.x — a 7 removeu `StaticJsonDocument` e
`containsKey`, usados aqui), `PZEM004Tv30`, `LiquidCrystal_I2C`, `OneWire`,
`DallasTemperature`, mais a `IoTMotorNet` deste repositorio.

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
