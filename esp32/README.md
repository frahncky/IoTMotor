# Firmware IoTMotor

- **ESP32-01** (`iotmotor_esp32/iotmotor_esp32_comandos/`): PZEM-004T, LCD 20x4 e quatro relés (K1–K4) controlados por MQTT pelo painel Cloudflare. Detalhes em `LEIA-ME-BANCADA.md`.
- **ESP32-S3** (`iotmotor_esp32/iotmotor_esp32_s3_sensores/`, `esp32-02`): mede vibração (MPU6050) e temperatura (DS18B20); não aciona saídas.

Os comandos MQTT no broker público não têm autenticação. Não conecte motores ou contatores sem autenticação, intertravamento e proteções independentes.

## Esquema de partições

Os dois firmwares são compilados com **`min_spiffs`** (1,9 MB para a aplicação,
ainda com OTA). No padrão de fábrica cabia 1,31 MB e eles já ocupavam 92% e 91%;
com este esquema, caem para cerca de 61%.

```sh
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs   iotmotor_esp32/iotmotor_esp32_comandos
arduino-cli compile --fqbn esp32:esp32:esp32s3:PartitionScheme=min_spiffs iotmotor_esp32/iotmotor_esp32_s3_sensores
```

No Arduino IDE: *Ferramentas → Partition Scheme → Minimal SPIFFS (1.9MB APP with OTA)*.

A tabela de partições fica fora da área que o OTA regrava, então **a troca só vale
depois de uma gravação por cabo em cada placa**. Enquanto isso não for feito, o OTA
continua funcionando normalmente — mas só enquanto o binário couber em 1,31 MB.
