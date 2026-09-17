# IoTMotor — ESP32-S3, módulo de vibração e temperatura

Firmware: `iotmotor_esp32_s3_sensores.ino` para **ESP32-S3**, identidade MQTT `esp32-02`. Não há GPIO de relé, lógica de partida nem inscrição em tópico de comando. Os valores vêm **somente dos sensores físicos**; quando ausentes ou inválidos, o JSON omite o campo e o dashboard exibe `—`.

A pinagem abaixo foi extraída da proposta de dois módulos do projeto, **não foi confirmada na sua montagem**. Confira o modelo exato do S3 e os módulos de sensor antes de ligar.

| Elemento | Ligação ESP32-S3 |
| --- | --- |
| MPU6050 SDA | GPIO5 |
| MPU6050 SCL | GPIO9 |
| MPU6050 VCC/GND | Alimentação compatível com 3,3 V / GND |
| DS18B20 DQ | GPIO4, com resistor pull-up 4,7 kΩ para 3,3 V |
| DS18B20 VCC/GND | 3,3 V / GND |

Instale no Arduino IDE o core ESP32 e as bibliotecas `PubSubClient`, `ArduinoJson` **6.x**, `OneWire` e `DallasTemperature`. Selecione a placa ESP32-S3 correta e compile/grave este arquivo na **S3**; mudanças no GitHub ou no Cloudflare não atualizam o firmware. Monitor Serial: **115200 baud**. Não foi feita validação física na sua placa.

A placa usa Wi-Fi aberto `IFMA_IOT` e publica via MQTT sobre WebSocket em `ws://test.mosquitto.org:8080` (a rede bloqueia as portas MQTT 1883 e 8883); o navegador usa `wss://test.mosquitto.org:8081`. Tópicos: `iotmotor/esp32-02/telemetry` e `iotmotor/esp32-02/status`. O painel agrega esses dados aos elétricos de `iotmotor/esp32-01/telemetry`, mas comandos são destinados **somente** ao `esp32-01`.

O MPU6050 é amostrado aproximadamente a 50 Hz e o JSON publica `vibration` (RMS estimado da aceleração dinâmica em **g**) e `vibration_peak`; esse índice precisa de calibração e validação antes de interpretação como condição de máquina. A temperatura do DS18B20 é solicitada sem bloquear a comunicação, aproximadamente a cada 2 s. Erros de sensores são indicados em `mpu_ok` e `temperature_ok`; não há simulação neste firmware.

O broker público não autentica publicadores: dados podem ser falsificados e o serviço pode ficar indisponível. Não utilize estas mensagens como única proteção de um motor nem publique dados confidenciais.
