# Firmware IoTMotor

| Pasta | Placa | ID MQTT |
| --- | --- | --- |
| [`iotmotor_esp32/iotmotor_esp32_comandos`](iotmotor_esp32/iotmotor_esp32_comandos) | Quadro de comando (ESP32 DevKit V1): PZEM-004T, LCD 20×4, CNT 1 a 4 | `esp32-01` |
| [`iotmotor_esp32/iotmotor_esp32_s3_sensores`](iotmotor_esp32/iotmotor_esp32_s3_sensores) | Sensores do motor (ESP32-S3): MPU6050, DS18B20, LED, buzzer | `esp32-02` |

A documentação fica em [`docs/`](../docs):

- [Firmware](../docs/firmware.md): primeira gravação, OTA, versões, partições, Wi-Fi e senha de comando.
- [Hardware](../docs/hardware.md): lista de materiais e pinos.
- [Referência MQTT](../docs/mqtt.md): tópicos, telemetria e comandos.
