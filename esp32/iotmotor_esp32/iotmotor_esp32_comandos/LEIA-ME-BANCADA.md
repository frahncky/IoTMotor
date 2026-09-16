# IoTMotor — ESP32 de comandos + PZEM-004T v3

Este diretório contém o sketch `iotmotor_esp32_comandos.ino`, versão `bench-pzem-2.1`, para **ESP32-01**. O módulo lê dados elétricos do **PZEM-004T v3** e testa somente a saída GPIO2. **Vibração e temperatura pertencem ao ESP32-S3 (`esp32-02`) e NÃO são simuladas nem medidas por este sketch.** Consulte `../iotmotor_esp32_s3_sensores/`.

A alteração no GitHub **não regrava** a placa. Instale Arduino core ESP32, bibliotecas PubSubClient, ArduinoJson 6.x e PZEM004Tv30; compile o sketch e grave no ESP32. Abra o Monitor Serial a **115200 baud** para ler Wi-Fi/IP, MQTT e resultado do PZEM. Ainda não foi confirmada uma compilação e leitura física com a sua placa.

## Conexões e broker

| Elemento | Configuração |
| --- | --- |
| Rede Wi-Fi | `IFMA_IOT`, sem senha; pode exigir acesso à Internet sem portal cativo |
| MQTT ESP32 | `test.mosquitto.org:1883` (TCP) |
| MQTT dashboard | `wss://test.mosquitto.org:8081` (WSS) |
| Tópico de telemetria elétrica | `iotmotor/esp32-01/telemetry` |
| Tópico de comando dirigido | `iotmotor/esp32-01/command` |
| PZEM TX → ESP32 RX2 | GPIO16 |
| PZEM RX → ESP32 TX2 | GPIO17 |
| Jumper físico de habilitação | GPIO32 → GND (`INPUT_PULLUP`, não aplicar tensão externa) |
| Saída de teste | GPIO2; **sem motor nem contator conectado** |

Confirme isolamento, alimentação e segurança do PZEM segundo o fabricante e procedimentos de laboratório; não faça ligações de circuito energizado. O broker MQTT é público e não autentica comandos: **não utilize esta configuração para acionar motor real**. O jumper local é apenas uma restrição para ensaio, não um dispositivo de segurança funcional certificado.

## Leituras reais

`DEMO_MODE=0` é o padrão: `voltage`, `current`, `power`, `pf`, `frequency` e `energy` vêm do PZEM, se válidos. O JSON também contém `sensor_ok`, `bench_armed`, `demo:false`, `data_source:pzem004t`, `seq` e o estado solicitado de GPIO2 em `motor_on`. Se o PZEM não responder, as grandezas inválidas são omitidas, sem dados falsos. O painel calcula potência aparente e reativa apenas quando há entradas suficientes.

`DEMO_MODE=1` só para conferir os gráficos com **valores explicitamente simulados**; não é medição física. O S3 usa MPU6050 e DS18B20 em seu próprio firmware.

## Comandos de teste

- `start` com `mode:direct`, `device_id:esp32-01`: exige jumper local e leitura válida do PZEM; somente testa GPIO2 com hardware de potência desconectado.
- `stop` com `mode:manual_stop`: desliga GPIO2 mesmo sem jumper. Retirar o jumper ou perder rede/MQTT também causa desligamento por software.
- `start` com `mode:star_delta`: **recusado**. Um relé não possui a topologia de partida estrela-triângulo nem intertravamento físico.
- O firmware aceita apenas o tópico dirigido a `esp32-01`, não o broadcast `/request/command`. Status MQTT retido não prova que o dispositivo esteja conectado neste instante.

Exemplo de mensagem dirigida: `{"device_id":"esp32-01","command":"stop","mode":"manual_stop","origin":"web_bench"}`. O ESP32-S3 não deve receber este comando.
