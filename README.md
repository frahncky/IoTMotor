# IoTMotor

Aplicativo Flutter para controle e monitoramento de motores via MQTT.

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

O firmware do ESP32 deve usar `retention_days` para remover do SD card os
registros de telemetria mais antigos que o limite configurado.

Na interface, o operador pode digitar a retencao em dias, meses ou anos. O app
converte o valor para dias antes de persistir localmente ou enviar ao ESP32.
