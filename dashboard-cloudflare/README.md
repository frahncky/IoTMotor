# IoTMotor — dashboard MQTT com dois ESP32

A interface web fica em `dashboard-cloudflare/index.html`. O **ESP32-01** le o PZEM-004T, comanda os contatores CNT 1–CNT 4 e atualiza o LCD 20x4. O **ESP32-S3 (esp32-02)** publica vibracao e temperatura. Nenhum ESP32 hospeda pagina web; ambos usam MQTT.

| Modulo | Firmware | Topico de telemetria |
| --- | --- | --- |
| ESP32-01: PZEM, LCD e CNT 1–CNT 4 | `esp32/iotmotor_esp32/iotmotor_esp32_comandos/iotmotor_esp32_comandos.ino` | `iotmotor/esp32-01/telemetry` |
| ESP32-S3: MPU6050 e DS18B20 | `esp32/iotmotor_esp32/iotmotor_esp32_s3_sensores/iotmotor_esp32_s3_sensores.ino` | `iotmotor/esp32-02/telemetry` |

## Conexao e comandos

- Broker de testes `test.mosquitto.org`, `ws://test.mosquitto.org:8080` (MQTT sobre WebSocket, pois a IFMA_IOT bloqueia 1883/8883) para os ESP32 e `wss://test.mosquitto.org:8081` para o navegador; prefixo `iotmotor`. Wi-Fi configurado no firmware: `IFMA_IOT`.
- A mesma tela permite selecionar **partida direta** e quais contatores (CNT 1–CNT 4) acionar, ou a **sequencia temporizada de bancada** (principal, estrela e triangulo em tres contatores diferentes). Botoes originais **Ligar** e **Desligar todos** usam `iotmotor/esp32-01/command`; o ESP32 confirma em `iotmotor/esp32-01/command_ack` e informa estados logicos em `iotmotor/esp32-01/telemetry`.
- **Nao existe chave de comando nem jumper GPIO32–GND.** O campo `boot` publicado pelo ESP32 identifica apenas a sessao e nao fornece autenticacao. A partida requer telemetria recente para obter a sessao atual; a parada MQTT nao depende de telemetria ou sessao.
- O ESP32-01 comeca com todos os relés desligados, desliga apos 15 s sem MQTT/Wi-Fi e tem limite de ensaio de **5 minutos**. A sequencia estrela-triangulo usa uma pausa de 700 ms entre os estados e nao substitui intertravamentos eletricos.

**Somente para bancada com motores e contatores desconectados dos relés.** O broker publico aceita publicacoes de terceiros. Nenhum indicador na pagina comprova energizacao real de um motor: `relays` e o estado logico comandado das saidas. Para acionamento de maquinas reais, sao necessarios circuito independente de parada de emergencia, protecoes eletricas, intertravamentos fisicos e canal de comandos com autenticacao.

## Publicar e testar

O repositório publica **codigo-fonte** no GitHub, nao grava automaticamente o ESP32 nem faz deploy automatico no Cloudflare. Grave no ESP32-01 o sketch `iotmotor_esp32_comandos.ino` com os dois headers da mesma pasta; grave o firmware da pasta `iotmotor_esp32_s3_sensores` no S3. Abra o Monitor Serial em 115200 para conferir conexao Wi-Fi, MQTT e sensores. No dashboard Cloudflare, use os mesmos broker, prefixo e IDs.

Para Cloudflare Pages com Git, use a branch `main`, build command `exit 0` e output `dashboard-cloudflare`. Se usar Worker, publique os arquivos dessa pasta como assets estaticos do Worker. Um commit no GitHub nao atualiza automaticamente um Worker configurado sem deploy. Verifique se `/remote-controls.js` e `/dual-dashboard.js` sao servidos na versao atual. A disponibilidade do broker publico nao e garantida.

## Histórico no navegador

As leituras ficam guardadas **neste navegador** (até 3000 amostras ou 24 horas,
o que vier primeiro) e continuam lá depois de fechar a aba. O seletor
**Período** escolhe o que vai para o CSV — tudo, a última hora ou as últimas
24 h — e **Limpar** apaga o que está guardado.

O histórico é por navegador e por computador: não sobe para o broker nem para a
Cloudflare. Para levar um ensaio para outro lugar, exporte o CSV.

## Alarme dos sensores

A seção **Alarme dos sensores** traz a lista de alarmes gravada no S3: cada
linha mostra a grandeza, o lado (acima/abaixo), o limite editável e um
interruptor; ✓ grava só aquela linha e ✕ remove. O formulário **Adicionar
alarme** oferece vibração e temperatura (medidas no S3) e tensão, corrente,
potência, frequência e fator de potência (medidas pelo quadro de comando, que
o S3 escuta por MQTT). Cabem 8 alarmes na placa. O botão **Salvar** cuida
apenas do interruptor geral e dos bipes de evento; **Testar LED e buzzer**
aciona tudo por 1,5 s.

**Recarregar lista da placa** pede a lista de novo (comando `alarm_list`),
caso a mensagem retida não tenha chegado.

A lista vive na placa, não no navegador: o alarme funciona sem o painel aberto
e durante perda de rede. Uma linha aparece destacada como "disparado" enquanto
a telemetria a listar em `alarms_firing`.

Publique também `alarm-controls.js` junto dos demais arquivos do dashboard.
O S3 precisa do firmware `s3-sensors-1.4-alarmes` ou posterior; com firmware
antigo o painel avisa que a lista não chegou. Os controles aguardam telemetria recente e a confirmação do dispositivo
ao salvar. O indicador mostra sensores ausentes e dados antigos explicitamente.

Validação do painel:
```sh
node --test dashboard-cloudflare/dual-dashboard.test.cjs dashboard-cloudflare/hardware-mirror.test.cjs dashboard-cloudflare/wifi-manager.test.cjs dashboard-cloudflare/alarm-controls.test.cjs
```