# Sensores do motor (ESP32-S3)

Sketch `iotmotor_esp32_s3_sensores.ino` para **ESP32-S3**, ID MQTT `esp32-02`.
Mede vibração (MPU6050) e temperatura (DS18B20), cuida dos alarmes com LED e
buzzer e guarda o histórico de 7 dias. Não aciona nenhuma saída.

- Ligações, LED e buzzer: [docs/hardware.md](../../../docs/hardware.md#sensores-do-motor-esp32-s3)
- Gravar e atualizar: [docs/firmware.md](../../../docs/firmware.md)
- Alarmes, histórico e comandos: [docs/mqtt.md](../../../docs/mqtt.md#comandos-dos-sensores-do-motor)
- Usar os alarmes pelo painel: [docs/guia-de-uso.md](../../../docs/guia-de-uso.md#alarmes)

Para ler o registro dos últimos disparos de alarme, que o painel não mostra:

```sh
mosquitto_sub -h test.mosquitto.org -t iotmotor/esp32-02/alarm_log -v
```
