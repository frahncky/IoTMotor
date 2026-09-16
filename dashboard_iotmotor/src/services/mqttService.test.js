import assert from "node:assert/strict";
import test from "node:test";

import {
  buildCommandRequest,
  buildDeviceCommand,
  buildStorageConfig,
  buildTelemetryRequest,
  buildTopics,
  deviceIdFromTopic,
  isProtectionStatus,
  parseTelemetry,
  statusLabel,
} from "./mqttService.js";

test("buildTopics monta o mapa a partir do prefixo", () => {
  const topics = buildTopics("iotmotor");

  assert.equal(topics.telemetryWildcard, "iotmotor/+/telemetry");
  assert.equal(topics.statusWildcard, "iotmotor/+/status");
  assert.equal(topics.commandRequest, "iotmotor/request/command");
  assert.equal(topics.telemetryRequest, "iotmotor/request/telemetry");
  assert.equal(topics.commandFor("esp32-01"), "iotmotor/esp32-01/command");
});

test("buildTopics rejeita prefixo vazio e ignora barra final", () => {
  assert.throws(() => buildTopics("   "), /prefixo/i);
  assert.equal(buildTopics("iotmotor/").prefix, "iotmotor");
});

test("deviceIdFromTopic extrai o modulo de telemetria e status", () => {
  assert.equal(deviceIdFromTopic("iotmotor/esp32-01/telemetry", "iotmotor"), "esp32-01");
  assert.equal(deviceIdFromTopic("iotmotor/esp32-02/status", "iotmotor"), "esp32-02");
});

test("deviceIdFromTopic recusa topico de outro prefixo ou folha", () => {
  assert.equal(deviceIdFromTopic("outro/esp32-01/telemetry", "iotmotor"), null);
  assert.equal(deviceIdFromTopic("iotmotor/request/command", "iotmotor"), null);
  assert.equal(deviceIdFromTopic("iotmotor/telemetry", "iotmotor"), null);
});

test("deviceIdFromTopic aceita prefixo com varios segmentos", () => {
  assert.equal(deviceIdFromTopic("ifma/iotmotor/esp32-01/telemetry", "ifma/iotmotor"), "esp32-01");
  assert.equal(deviceIdFromTopic("ifma/outro/esp32-01/telemetry", "ifma/iotmotor"), null);
});

test("parseTelemetry le a telemetria eletrica do Modulo 1", () => {
  const sample = parseTelemetry(
    '{"device_id":"esp32-01","voltage":220.4,"current":3.9,"power":858,' +
    '"pf":0.98,"frequency":60,"energy":1.234,"motor_on":true,"mode":"star_delta",' +
    '"state":"rodando","protection_lock":false,"seq":42}',
  );

  assert.equal(sample.deviceId, "esp32-01");
  assert.equal(sample.voltage, 220.4);
  assert.equal(sample.power, 858);
  assert.equal(sample.motorOn, true);
  assert.equal(sample.mode, "star_delta");
  assert.equal(sample.state, "rodando");
  assert.equal(sample.protectionLock, false);
  assert.equal(sample.sequence, 42);
  assert.ok(Math.abs(sample.apparentPower - 220.4 * 3.9) < 1e-9);
});

test("parseTelemetry le a telemetria mecanica do Modulo 2", () => {
  const sample = parseTelemetry(
    '{"device_id":"esp32-02","vibration":0.12,"vibration_peak":0.31,' +
    '"temperature":37.8,"critical":false,"sd_ok":true,"sd_samples":1200}',
  );

  assert.equal(sample.vibration, 0.12);
  assert.equal(sample.vibrationPeak, 0.31);
  assert.equal(sample.temperature, 37.8);
  assert.equal(sample.critical, false);
  assert.equal(sample.sdSamples, 1200);
  assert.equal(sample.apparentPower, null, "sem tensao e corrente nao ha potencia aparente");
});

test("parseTelemetry aceita payload parcial", () => {
  const sample = parseTelemetry('{"voltage":220.4}');
  assert.equal(sample.voltage, 220.4);
  assert.equal(sample.current, null);
});

test("parseTelemetry aceita grandezas aninhadas em data e como texto", () => {
  const sample = parseTelemetry(
    '{"data":{"voltage":"220,4","current":"3.9","temperatura":"37,8"}}',
  );

  assert.equal(sample.voltage, 220.4);
  assert.equal(sample.current, 3.9);
  assert.equal(sample.temperature, 37.8);
});

test("parseTelemetry recusa payload sem grandeza reconhecida", () => {
  assert.throws(() => parseTelemetry('{"foo":1}'), /reconhecida/i);
  assert.throws(() => parseTelemetry("[1,2]"), /objeto JSON/i);
});

test("statusLabel traduz os status do firmware", () => {
  assert.equal(statusLabel("motor_started"), "Partida comandada");
  assert.equal(statusLabel("protection_vibration"), "Protecao: vibracao critica");
  assert.equal(statusLabel("qualquer_coisa"), "qualquer_coisa");
});

test("isProtectionStatus identifica apenas os status de protecao", () => {
  assert.equal(isProtectionStatus("protection_overcurrent"), true);
  assert.equal(isProtectionStatus("motor_stopped"), false);
  assert.equal(isProtectionStatus(null), false);
});

test("buildDeviceCommand nao envia type, para o firmware nao descartar", () => {
  const payload = buildDeviceCommand({
    deviceId: "esp32-01",
    command: "start",
    mode: "direct",
  });

  assert.equal(payload.type, undefined);
  assert.equal(payload.device_id, "esp32-01");
  assert.equal(payload.command, "start");
  assert.equal(payload.mode, "direct");
  assert.equal(payload.origin, "web_dashboard");
  assert.ok(Date.parse(payload.timestamp) > 0);
});

test("buildCommandRequest usa o tipo que o firmware aceita em broadcast", () => {
  const payload = buildCommandRequest({ command: "stop", mode: "manual_stop" });

  assert.equal(payload.type, "command_request");
  assert.ok(payload.request_id.startsWith("cmd_"));
  assert.equal(payload.command, "stop");
});

test("buildTelemetryRequest normaliza e deduplica os campos", () => {
  const payload = buildTelemetryRequest({ fields: [" Voltage ", "voltage", "", "CURRENT"] });

  assert.equal(payload.type, "telemetry_request");
  assert.deepEqual(payload.fields, ["voltage", "current"]);
});

test("buildStorageConfig limita a retencao e repete o valor nos tres campos", () => {
  const payload = buildStorageConfig({ retentionDays: 30, deviceId: "esp32-02" });

  assert.equal(payload.type, "storage_config");
  assert.equal(payload.device_id, "esp32-02");
  assert.equal(payload.storage.medium, "sdcard");
  assert.equal(payload.storage.retention_days, 30);
  assert.equal(payload.remote_retention_days, 30);
  assert.equal(payload.retention_days, 30);

  assert.equal(buildStorageConfig({ retentionDays: 0 }).retention_days, 1);
  assert.equal(buildStorageConfig({ retentionDays: 99_999 }).retention_days, 3650);
  assert.equal(buildStorageConfig({ retentionDays: 5 }).device_id, undefined);
});
