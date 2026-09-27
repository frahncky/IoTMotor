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
- O quadro de comando **recusa** atualizar com saídas ligadas: pare o motor antes.
- Se falhar, o motivo volta no `command_ack` e a placa continua na versão antiga.

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

1. Na energização, a placa faz uma varredura e tenta as redes gravadas **na ordem da lista** (a ordem é editável na aba **Dispositivos**). Uma rede que não apareceu na varredura continua sendo tentada, com espera menor.
2. Se nenhuma responder, ela tenta a rede que o próprio ESP32 guardou pelo portal. Funcionando, essa rede vai para o topo da lista.
3. Só depois de tudo isso a placa abre a **rede própria** (`IoTMotor-esp32-01` ou `IoTMotor-esp32-02`) por 180 s, para cadastrar um Wi-Fi pelo celular.

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
| `alarm_list.h` | sensores | Lista de alarmes e registro de disparos |
| `historico.h` | sensores | Histórico por hora dos últimos 7 dias |
| `wifi_store.h`, `wifi_portal.h` | as duas | Redes Wi-Fi e rede própria da placa |
| `comando_seguro.h` | as duas | Comandos cifrados |
| `ota_update.h` | as duas | Atualização pela internet |
| `relogio.h` | as duas | Hora por NTP |
| `mqtt_websocket_client.h` | as duas | MQTT sobre WebSocket (porta 8080) |

Os arquivos marcados "as duas" são **idênticos** nas duas pastas (o CI confere
todos, menos o `relogio.h`). Mude nas duas ao mesmo tempo.
