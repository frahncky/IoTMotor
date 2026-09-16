import mqtt from "mqtt";

/** Modulo 1: aciona o motor e mede as grandezas eletricas. */
export const DEVICE_ACIONAMENTO = "esp32-01";
/** Modulo 2: coleta vibracao e temperatura. */
export const DEVICE_SENSORES = "esp32-02";

export const DEFAULT_MQTT_CONFIG = {
  // Os ESP32 continuam publicando em mqtt://test.mosquitto.org:1883.
  // O dashboard assina os mesmos topicos pelo listener WebSocket seguro, que e
  // obrigatorio: uma pagina servida em HTTPS nao pode abrir ws:// (mixed content).
  url: "wss://test.mosquitto.org:8081",
  topicPrefix: "iotmotor",
  username: "",
  password: "",
};

export const RECONNECT_BASE_MS = 2_000;
export const RECONNECT_MAX_MS = 30_000;

/** Monta o mapa de topicos a partir do prefixo configurado. */
export function buildTopics(prefix) {
  const base = String(prefix ?? "").trim().replace(/\/+$/, "");
  if (!base) throw new Error("Informe o prefixo de topicos (ex.: iotmotor).");

  return {
    prefix: base,
    telemetryWildcard: `${base}/+/telemetry`,
    statusWildcard: `${base}/+/status`,
    commandRequest: `${base}/request/command`,
    telemetryRequest: `${base}/request/telemetry`,
    commandFor: (deviceId) => `${base}/${String(deviceId).trim()}/command`,
  };
}

/**
 * Extrai o device_id de um topico `<prefixo>/<device>/<telemetry|status>`.
 * Devolve null quando o topico nao pertence ao prefixo esperado.
 */
export function deviceIdFromTopic(topic, prefix) {
  const segments = String(topic ?? "").split("/").filter(Boolean);
  const prefixSegments = String(prefix ?? "").split("/").filter(Boolean);

  if (segments.length < prefixSegments.length + 2) return null;

  const leaf = segments[segments.length - 1];
  if (leaf !== "telemetry" && leaf !== "status") return null;

  for (let i = 0; i < prefixSegments.length; i++) {
    if (segments[i] !== prefixSegments[i]) return null;
  }

  const deviceId = segments[segments.length - 2].trim();
  return deviceId || null;
}

function firstNumber(source, keys) {
  for (const key of keys) {
    const value = source[key];
    if (value == null) continue;
    if (typeof value === "number") {
      if (Number.isFinite(value)) return value;
      continue;
    }
    if (typeof value === "string") {
      const parsed = Number(value.replace(",", "."));
      if (Number.isFinite(parsed)) return parsed;
    }
  }
  return null;
}

function firstBoolean(source, keys) {
  for (const key of keys) {
    const value = source[key];
    if (value == null) continue;
    if (typeof value === "boolean") return value;
    if (typeof value === "number") return value !== 0;
    if (typeof value === "string") {
      const text = value.trim().toLowerCase();
      if (["true", "1", "on"].includes(text)) return true;
      if (["false", "0", "off"].includes(text)) return false;
    }
  }
  return null;
}

function firstText(source, keys) {
  for (const key of keys) {
    const value = source[key];
    if (value == null) continue;
    const text = String(value).trim();
    if (text) return text;
  }
  return null;
}

const NUMERIC_FIELDS = {
  voltage: ["voltage", "tensao", "v"],
  current: ["current", "corrente", "i"],
  power: ["power", "potencia", "w"],
  pf: ["pf", "power_factor", "fator_potencia", "fp"],
  frequency: ["frequency", "frequencia", "hz"],
  energy: ["energy", "energy_kwh", "energia", "kwh"],
  vibration: ["vibration", "vibracao", "vib"],
  vibrationPeak: ["vibration_peak", "vibracao_pico"],
  temperature: ["temperature", "temperatura", "temp"],
  magnitude: ["magnitude"],
  sequence: ["seq", "sequence"],
  sdSamples: ["sd_samples"],
  retentionDays: ["retention_days"],
};

const BOOLEAN_FIELDS = {
  motorOn: ["motor_on", "motorOn", "ligado", "is_on"],
  protectionLock: ["protection_lock"],
  critical: ["critical", "critico"],
  pzemOk: ["pzem_ok"],
  mpuOk: ["mpu_ok"],
  sdOk: ["sd_ok"],
};

const TEXT_FIELDS = {
  mode: ["mode", "modo"],
  state: ["state", "estado"],
  stopReason: ["stop_reason"],
  requestId: ["request_id"],
};

/**
 * Converte o payload JSON de telemetria em um objeto normalizado.
 *
 * Diferente do EMetrics, que le um unico dispositivo com todos os campos
 * obrigatorios, aqui a leitura e parcial por natureza: o Modulo 1 publica
 * grandezas eletricas e o Modulo 2 publica vibracao e temperatura. Basta um
 * campo reconhecido para a amostra valer.
 */
export function parseTelemetry(payload) {
  const decoded = JSON.parse(payload.toString());
  if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
    throw new Error("Payload MQTT nao e um objeto JSON.");
  }

  // O app Flutter tambem aceita as grandezas aninhadas em `data`.
  const source =
    decoded.data && typeof decoded.data === "object" && !Array.isArray(decoded.data)
      ? decoded.data
      : decoded;

  const sample = { receivedAt: new Date() };
  let recognized = 0;

  for (const [field, keys] of Object.entries(NUMERIC_FIELDS)) {
    const value = firstNumber(source, keys);
    sample[field] = value;
    if (value != null) recognized++;
  }

  for (const [field, keys] of Object.entries(BOOLEAN_FIELDS)) {
    const value = firstBoolean(source, keys);
    sample[field] = value;
    if (value != null) recognized++;
  }

  for (const [field, keys] of Object.entries(TEXT_FIELDS)) {
    const value = firstText(source, keys);
    sample[field] = value;
    if (value != null) recognized++;
  }

  sample.deviceId = firstText(decoded, ["device_id", "deviceId"]);

  if (recognized === 0) {
    throw new Error("Payload MQTT sem nenhuma grandeza reconhecida.");
  }

  // Potencia aparente so faz sentido com tensao e corrente juntas.
  sample.apparentPower =
    sample.voltage != null && sample.current != null
      ? sample.voltage * sample.current
      : null;

  return sample;
}

/** Textos de status que o firmware publica, traduzidos para a interface. */
export const STATUS_LABELS = {
  online: "Modulo online",
  offline: "Modulo offline",
  motor_started: "Partida comandada",
  motor_running: "Motor em regime",
  motor_stopped: "Motor parado",
  unknown_command: "Comando desconhecido",
  invalid_command_json: "JSON de comando invalido",
  blocked_by_protection: "Partida bloqueada pela protecao",
  protection_overcurrent: "Protecao: sobrecorrente",
  protection_overvoltage: "Protecao: sobretensao",
  protection_undervoltage: "Protecao: subtensao",
  protection_vibration: "Protecao: vibracao critica",
  protection_temperature: "Protecao: temperatura critica",
  storage_config_applied: "Retencao do SD aplicada",
  storage_config_invalid: "Retencao do SD invalida",
};

export function statusLabel(status) {
  const key = String(status ?? "").trim().toLowerCase();
  return STATUS_LABELS[key] ?? key ?? "";
}

export function isProtectionStatus(status) {
  return String(status ?? "").trim().toLowerCase().startsWith("protection_");
}

/**
 * Conecta ao broker por WebSocket e assina a telemetria e o status de todos os
 * modulos do prefixo. O roteamento por dispositivo e feito aqui.
 */
export function connectMqtt(config, handlers) {
  const url = String(config.url ?? "").trim();
  if (!/^wss?:\/\//i.test(url)) {
    throw new Error("Use uma URL MQTT WebSocket iniciada por ws:// ou wss://.");
  }

  const topics = buildTopics(config.topicPrefix);
  const clientSuffix =
    globalThis.crypto?.randomUUID?.() ?? Math.random().toString(16).slice(2);

  let reconnectAttempts = 0;

  const client = mqtt.connect(url, {
    clientId: `iotmotor-dashboard-${clientSuffix}`,
    username: String(config.username ?? "").trim() || undefined,
    password: config.password || undefined,
    reconnectPeriod: RECONNECT_BASE_MS,
    connectTimeout: 8000,
    clean: true,
  });

  client.on("connect", () => {
    reconnectAttempts = 0;
    client.options.reconnectPeriod = RECONNECT_BASE_MS;
    client.subscribe(
      [topics.telemetryWildcard, topics.statusWildcard],
      { qos: 0 },
      (error) => {
        if (error) handlers.onError?.(error);
        else handlers.onConnected?.(topics);
      },
    );
  });

  client.on("reconnect", () => {
    reconnectAttempts++;
    client.options.reconnectPeriod = Math.min(
      RECONNECT_BASE_MS * 2 ** (reconnectAttempts - 1),
      RECONNECT_MAX_MS,
    );
    handlers.onReconnecting?.();
  });

  client.on("message", (messageTopic, payload) => {
    const deviceId = deviceIdFromTopic(messageTopic, topics.prefix);
    if (!deviceId) return;

    // O status e publicado como texto puro e retido; a telemetria, como JSON.
    if (messageTopic.endsWith("/status")) {
      handlers.onStatus?.(deviceId, payload.toString().trim());
      return;
    }

    try {
      handlers.onTelemetry?.(deviceId, parseTelemetry(payload));
    } catch (error) {
      handlers.onPayloadError?.(error);
    }
  });

  client.on("offline", () => handlers.onOffline?.());
  client.on("close", () => handlers.onClosed?.());
  client.on("error", (error) => handlers.onError?.(error));

  return client;
}

function nowIso() {
  return new Date().toISOString();
}

function newRequestId(prefix) {
  return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
}

/** Publica um objeto como JSON. QoS 1, igual ao que o app Flutter usa. */
export function publishJson(client, topic, payload) {
  if (!client) throw new Error("Nao conectado ao MQTT.");
  const target = String(topic ?? "").trim();
  if (!target) throw new Error("Topico de destino nao configurado.");
  client.publish(target, JSON.stringify(payload), { qos: 1 });
  return payload;
}

/**
 * Comando direcionado a um modulo, no formato de MqttMotorService.sendCommand.
 * Sem o campo `type`: o firmware ignora mensagens tipadas que nao sejam
 * command_request.
 */
export function buildDeviceCommand({ deviceId, command, mode }) {
  return {
    device_id: deviceId,
    command,
    mode,
    origin: "web_dashboard",
    timestamp: nowIso(),
  };
}

/** Comando em broadcast, no formato de MqttMotorService.requestCommand. */
export function buildCommandRequest({ command, mode, reason = "web_dashboard" }) {
  return {
    type: "command_request",
    request_id: newRequestId("cmd"),
    command,
    mode,
    reason,
    origin: "web_dashboard",
    timestamp: nowIso(),
  };
}

/** Pedido de leitura sob demanda, no formato de requestTelemetry. */
export function buildTelemetryRequest({ fields = [], reason = "manual_refresh" } = {}) {
  const normalized = [
    ...new Set(fields.map((field) => String(field).trim().toLowerCase()).filter(Boolean)),
  ];
  return {
    type: "telemetry_request",
    request_id: newRequestId("req"),
    fields: normalized,
    reason,
    origin: "web_dashboard",
    timestamp: nowIso(),
  };
}

/** Configuracao de retencao do SD, no formato de configureRemoteStorageRetention. */
export function buildStorageConfig({ retentionDays, deviceId, reason = "web_dashboard" }) {
  const days = Math.min(3650, Math.max(1, Math.round(Number(retentionDays))));
  if (!Number.isFinite(days)) throw new Error("Retencao invalida.");

  const target = String(deviceId ?? "").trim();
  return {
    type: "storage_config",
    request_id: newRequestId("storage"),
    ...(target ? { device_id: target } : {}),
    storage: { medium: "sdcard", retention_days: days },
    remote_retention_days: days,
    retention_days: days,
    reason,
    origin: "web_dashboard",
    timestamp: nowIso(),
  };
}
