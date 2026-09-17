# Firmware IoTMotor

- **ESP32-01** (`iotmotor_esp32/iotmotor_esp32_comandos/`): PZEM-004T, LCD 20x4 e quatro relés (K1–K4) controlados por MQTT pelo painel Cloudflare. Detalhes em `LEIA-ME-BANCADA.md`.
- **ESP32-S3** (`iotmotor_esp32/iotmotor_esp32_s3_sensores/`, `esp32-02`): mede vibração (MPU6050) e temperatura (DS18B20); não aciona saídas.

Os comandos MQTT no broker público não têm autenticação. Não conecte motores ou contatores sem autenticação, intertravamento e proteções independentes.
