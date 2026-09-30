# Firmware das placas

| Placa | Pasta | ID MQTT | Arquivo de OTA |
| --- | --- | --- | --- |
| Quadro de comando (ESP32 DevKit V1) | [`iotmotor_esp32_comandos`](../esp32/iotmotor_esp32/iotmotor_esp32_comandos) | `esp32-01` | `esp32-01.bin` |
| Sensores do motor (ESP32-S3) | [`iotmotor_esp32_s3_sensores`](../esp32/iotmotor_esp32/iotmotor_esp32_s3_sensores) | `esp32-02` | `esp32-02.bin` |

Nenhuma das placas hospeda página: as duas falam só MQTT.

## Primeira gravação (por cabo)

Só é preciso na primeira vez, ou para trocar o esquema de partições. Depois, as
atualizações chegam [pela internet](#atualização-pela-internet-ota).

1. **Arduino IDE** com o core **ESP32 3.2.1** (Espressif).
2. **Bibliotecas:** `PZEM004Tv30` 1.2.1, `LiquidCrystal I2C`, `PubSubClient`, `ArduinoJson` **6.21.5**, `OneWire`, `DallasTemperature` e `WiFiManager` 2.0.17.
3. **Wi-Fi:** em cada pasta, copie `wifi_local.exemplo.h` como `wifi_local.h` e ponha as redes. Esse arquivo não vai para o Git. Cabem até 4 redes (`WIFI_SSID_LOCAL`, `WIFI_SSID_2`…`_4`).
4. **Partições:** em *Ferramentas → Partition Scheme*, escolha **Minimal SPIFFS (1.9MB APP with OTA)**. Veja [por quê](#esquema-de-partições).
5. **Placa:** *ESP32 Dev Module* para o quadro, *ESP32S3 Dev Module* para os sensores.
6. **Gravar** e abrir o Monitor Serial a **115200 baud** para acompanhar Wi-Fi, MQTT e sensores.

Pela linha de comando:

```sh
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs   esp32/iotmotor_esp32/iotmotor_esp32_comandos
arduino-cli compile --fqbn esp32:esp32:esp32s3:PartitionScheme=min_spiffs esp32/iotmotor_esp32/iotmotor_esp32_s3_sensores
```

## Atualização pela internet (OTA)

Cada push na `main` que mexe em `esp32/` compila as duas placas e publica os
binários no release [`firmware-latest`](https://github.com/frahncky/IoTMotor/releases/tag/firmware-latest),
pelo workflow `publish-firmware.yml`.

Para atualizar, use o painel (aba **Dispositivos**, botão **Atualizar firmware
desta placa**) ou o app (**Configurações › Atualizar firmware**). O comando
[`update`](mqtt.md#comandos-das-duas-placas) faz a placa:

1. baixar `esp32-01.bin` ou `esp32-02.bin` do `firmware-latest`, por HTTPS;
2. regravar a si mesma;
3. reiniciar com a versão nova, em cerca de 1 minuto.

- A URL é **fixa no firmware** ([`ota_update.h`](../esp32/iotmotor_esp32/iotmotor_esp32_comandos/ota_update.h)). O comando só dispara a atualização e não escolhe de onde baixar, porque o broker é público.
- A placa **confere o certificado** do GitHub com os certificados raiz da Mozilla que já vêm no core ESP32. Numa rede com DNS ou Wi-Fi falso, o download é recusado em vez de gravar outro programa. A data dos certificados não é conferida, então a placa atualiza mesmo sem hora do NTP.
- O quadro de comando **recusa** atualizar com saídas ligadas: pare o motor antes.
- Se falhar, o motivo volta no `command_ack` e a placa continua na versão antiga.
- **Volta automática** (`v27` do quadro e `s3-sensors-1.21` em diante): a versão nova só se confirma quando a placa conecta no broker e assina os comandos, ou seja, quando já consegue receber a próxima atualização. Se ela travar, reiniciar em laço ou não chegar ao MQTT, o próximo boot volta sozinho para a versão anterior, sem cabo. O painel avisa: *"voltou para … a versão nova não se confirmou"*. Uma queda de energia antes da confirmação também volta para a anterior, que continua funcionando; basta atualizar de novo.
- O CI só publica depois dos [testes nativos do firmware](desenvolvimento.md#testes) e dos testes do painel.

## Versões

Cada placa informa a sua versão no tópico retido `capabilities`
(`firmware_version`). O painel e o app comparam com a versão publicada:

- painel: `FIRMWARE_PUBLICADO` em [`wifi-manager.js`](../dashboard-cloudflare/wifi-manager.js);
- app: `firmwarePublicado` em [`motor_info.dart`](../lib/features/iot_motor/models/motor_info.dart).

Quando a placa está diferente, a aba **Dispositivos** mostra um ponto âmbar.

> [!IMPORTANT]
> Ao mudar um firmware, troque o `firmware_version` no `.ino` **e** as duas
> constantes acima. O CI falha se elas não baterem.

## Esquema de partições

Os dois firmwares usam **Minimal SPIFFS** (`min_spiffs`): 1,9 MB para o
programa, ainda com OTA. No esquema de fábrica cabia só 1,31 MB, e os firmwares
já passavam de 90% disso.

A tabela de partições fica fora da área que o OTA regrava. Por isso, trocar o
esquema **exige uma gravação por cabo** em cada placa. Até lá, o OTA continua
funcionando, mas só enquanto o binário couber em 1,31 MB.

## Como a placa entra na rede

1. Primeiro, a **última rede que funcionou**, por cerca de 2,5 s, sem varredura: no mesmo lugar, a placa entra quase na hora.
2. Não deu: uma varredura, e as redes gravadas **que apareceram** nela, por 3 a 4 s cada. A ordem é a da lista (editável na aba **Dispositivos**), mas uma rede com sinal bem mais forte passa à frente de uma quase inacessível: cada posição da lista vale 8 dB.
3. Depois, as redes gravadas que **não apareceram** na varredura (podem estar ocultas), por 3 s cada.
4. Por fim, a rede que o próprio ESP32 guardou pelo portal. Funcionando, ela entra na lista.
5. Só então, e só no quadro de comando durante a energização, abre a **rede própria** (`IoTMotor-esp32-01`) por 180 s, para cadastrar um Wi-Fi pelo celular. A placa de sensores abre a dela (`IoTMotor-esp32-02`) apenas pelo botão **Abrir rede da placa agora**.

Com a rede no ar, a placa republica o diagnóstico (sinal, reconexões, motivo da
última queda) a cada 30 s: aparece na aba **Dispositivos**.

As senhas de Wi-Fi ficam na memória da placa (NVS). Pelo painel, elas viajam
cifradas para a chave da placa ([detalhes](mqtt.md#comandos-das-duas-placas)).

## Senha de comando

Sem senha, as placas aceitam comando aberto de qualquer um no broker público. Com
senha, só aceitam comando cifrado com AES-256-GCM ([formato](mqtt.md#comandos-cifrados)).

- **Firmware publicado pelo CI:** a senha vem do segredo **`IOTMOTOR_CMD_SENHA`** do repositório (*Settings → Secrets and variables → Actions*). Hoje esse segredo **não existe**, então o firmware publicado aceita comando aberto, e o build avisa isso.
- **Gravação por cabo:** copie `comando_local.exemplo.h` como `comando_local.h` nas **duas** pastas, com a mesma senha. Esse arquivo não vai para o Git.
- Use uma senha de **12 caracteres ou mais** (o firmware não compila com menos), **sem aspas duplas nem barra invertida**. A chave sai de um SHA-256 só: senha curta pode ser descoberta fora da placa por quem gravar um comando no broker.
- **Desligar** é aceito mesmo sem selo ou com desafio vencido: parar é sempre o lado seguro.
- O painel e o app mostram o campo **Senha de comando** sozinhos assim que uma placa passa a exigir. A telemetria traz `secure: true`.
- Se a senha se perder, a saída é regravar as placas por cabo.

## Aquisição e sincronização dos dados

A configuração de aquisição é centralizada no **ESP32-01**. Ela fica gravada em
NVS, no namespace `iot-acq`, e é publicada de forma retida em
`iotmotor/system/acquisition`. Painel web, app e ESP32-S3 usam essa mensagem
como configuração oficial.

Os parâmetros ajustáveis são:

| Campo | Faixa | Função |
| --- | --- | --- |
| `pzem_read_ms` | 1 a 10 s | Intervalo de leitura elétrica do PZEM no ESP32-01 |
| `publish_ms` | 1 a 60 s | Intervalo de publicação MQTT das duas placas |
| `chart_ms` | de `publish_ms` até 60 s | Janela temporal usada pelos gráficos |
| `record_ms` | de `publish_ms` até 10 min | Cadência lógica de registro no painel/app |

Regras: `pzem_read_ms <= publish_ms <= chart_ms` e
`publish_ms <= record_ms`.

A vibração não acompanha esses intervalos de aquisição elétrica: o MPU6050
continua sendo lido a **1000 Hz**, com janela RMS fixa de **1 s**. O cálculo
inclui dois passa-altas Butterworth de 2ª ordem a 8 Hz e integração de Al-Alaoui;
veja a [metodologia completa de vibração](vibracao.md). Também são fixos o
histórico consolidado em janelas de 1 h e a retenção de 7 dias.

Quando `publish_ms` muda, o ESP32-S3 recebe o tópico retido e passa a publicar
sua telemetria na mesma cadência. `chart_ms` e `record_ms` são preservados
pelo ESP32-01 para que web e app usem a mesma política.

A configuração pode ser consultada e alterada pelos comandos
`acquisition_config_get` e `acquisition_config_set`, descritos em
[Referência MQTT](mqtt.md#comandos-do-quadro-de-comando).

## Hora das medições

As duas placas acertam o relógio por NTP assim que entram na rede (`relogio.h`),
e conferem de hora em hora. Cada telemetria sai com `ts` (segundos UTC).
Enquanto o NTP não responde, o campo não aparece: nenhuma placa publica hora
inventada.

Dependem da hora:
- as "partidas hoje" (horário de Brasília);
- a data da última manutenção;
- o histórico da placa de sensores, que não registra nada sem hora.

## Segurança do ensaio (quadro de comando)

| Proteção | Padrão | Ajuste |
| --- | --- | --- |
| Duração máxima do ensaio | 5 min | Painel › Configurações, ou [`run_limit`](mqtt.md#comandos-do-quadro-de-comando): 10 s a 2 h, ou sem limite |
| Queda de rede | Saídas caem após 15 s sem Wi-Fi/MQTT | Painel › Configurações, ou [`link_grace`](mqtt.md#comandos-do-quadro-de-comando): 0 a 3600 s, ou sem limite |
| Modo instrumentação | Desligado | Botão **Somente medição**, ou [`actuation`](mqtt.md#comandos-do-quadro-de-comando) |

- Os ajustes ficam gravados na placa e sobrevivem a reinício e queda de energia.
- Mesmo sem limite de rede, enquanto a rede estiver fora ninguém consegue mandar parar pelo painel: a parada tem de ser elétrica.
- Os tempos de cada contator dentro de uma partida continuam limitados a 5 minutos.

## Arquivos de cada firmware

| Arquivo | Placa | O que faz |
| --- | --- | --- |
| `iotmotor_esp32_comandos.ino` | quadro | Laço principal, PZEM, LCD, relés, telemetria |
| `iotmotor_mqtt_control.h` | quadro | Comandos MQTT e respostas |
| `iotmotor_profiles.h` | quadro | Partidas gravadas e motor de tempos |
| `iotmotor_motor_info.h` | quadro | Dados do motor, horímetro, partidas e manutenção |
| `iotmotor_esp32_s3_sensores.ino` | sensores | Sensores, LED, buzzer, telemetria e comandos |
| `vibracao.h` | sensores | FIFO do MPU6050, filtros, integração e cálculo de velocidade RMS em mm/s |
| `alarm_list.h` | sensores | Lista de alarmes e registro de disparos |
| `historico.h` | sensores | Histórico por hora dos últimos 7 dias |
| `wifi_store.h`, `wifi_portal.h` | as duas | Redes Wi-Fi e rede própria da placa |
| `comando_seguro.h` | as duas | Comandos cifrados |
| `ota_update.h` | as duas | Atualização pela internet |
| `relogio.h` | as duas | Hora por NTP |
| `mqtt_websocket_client.h` | as duas | MQTT sobre WebSocket (porta 8080) |
| `watchdog.h` | as duas | Vigia do `loop()`: travou, a placa reinicia |

Os arquivos marcados "as duas" são **idênticos** nas duas pastas: o CI falha se
qualquer arquivo com o mesmo nome nas duas pastas for diferente. Mude nas duas
ao mesmo tempo.

## Vigia do loop (watchdog)

Se o `loop()` ficar mais de 60 s sem voltar, a placa reinicia sozinha. Travado,
o quadro também deixaria de rodar a proteção que desliga as saídas quando o
MQTT/Wi-Fi cai; reiniciando, as saídas voltam para o repouso logo no boot.

- As tentativas de Wi-Fi alimentam o vigia enquanto esperam.
- O download do OTA e a rede própria da placa (que levam minutos e só rodam com
  as saídas paradas) pausam o vigia.
- O motivo do último reinício aparece no Serial (`[BOOT] motivo do ultimo
  reinicio: watchdog de tarefa`).
