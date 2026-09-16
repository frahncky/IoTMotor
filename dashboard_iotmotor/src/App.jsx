import { useEffect, useMemo, useRef, useState } from "react";
import {
  AreaChart, Area, LineChart, Line,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
  ReferenceLine, Brush,
} from "recharts";
import {
  DEFAULT_MQTT_CONFIG,
  DEVICE_ACIONAMENTO,
  DEVICE_SENSORES,
  buildCommandRequest,
  buildDeviceCommand,
  buildStorageConfig,
  buildTelemetryRequest,
  buildTopics,
  connectMqtt,
  isProtectionStatus,
  publishJson,
  statusLabel,
} from "./services/mqttService";
import { fmt, historyToCsv, motorStateLabel, startModeLabel } from "./utils";
import { C } from "./theme";


const MQTT_SETTINGS_KEY = "iotmotor.mqtt-settings";
const ALERT_SETTINGS_KEY = "iotmotor.alert-settings";
const DEVICE_TIMEOUT_MS = 15_000;
const HISTORY_LIMIT = 300;
const STATUS_LOG_LIMIT = 40;

// Espelham os limites padrao de MotorAppSettings.initial() no app Flutter.
const DEFAULT_ALERT_SETTINGS = {
  voltageMin: 190,
  voltageMax: 240,
  currentMax: 10,
  vibrationMax: 1.5,
  temperatureMax: 70,
};

const DEVICE_LABELS = {
  [DEVICE_ACIONAMENTO]: "Modulo 1 — acionamento e medicao eletrica",
  [DEVICE_SENSORES]: "Modulo 2 — vibracao e temperatura",
};

function loadSettings(key, fallback) {
  try {
    const saved = window.localStorage.getItem(key);
    if (!saved) return fallback;
    const merged = { ...fallback, ...JSON.parse(saved) };
    // Repara a configuracao vazia deixada por versoes anteriores do painel.
    if (fallback.url && !String(merged.url ?? "").trim()) merged.url = fallback.url;
    if (fallback.topicPrefix && !String(merged.topicPrefix ?? "").trim()) {
      merged.topicPrefix = fallback.topicPrefix;
    }
    return merged;
  } catch (_) {
    return fallback;
  }
}

// ─── Motivos visuais da referencia ───────────────────────────────────────────

/** Selo de icone com circunferencia tracejada, como os icones da peca. */
function BlueprintBadge({ children, title }) {
  return (
    <span className="bp-badge" role="img" aria-label={title}>
      <svg viewBox="0 0 34 34" aria-hidden="true">
        <circle
          cx="17" cy="17" r="15.5"
          fill="none" stroke="currentColor" strokeWidth="1.2"
          strokeDasharray="2.5 3.5" strokeLinecap="round"
        />
      </svg>
      <span className="bp-badge-glyph" aria-hidden="true">{children}</span>
    </span>
  );
}

/** Cabecalho de secao: selo tracejado + rotulo + regua. */
function BlueprintSection({ badge, badgeTitle, children }) {
  return (
    <div className="bp-section">
      <BlueprintBadge title={badgeTitle}>{badge}</BlueprintBadge>
      <span className="bp-section-label">{children}</span>
      <span className="bp-section-rule" aria-hidden="true" />
    </div>
  );
}

/**
 * Malha tecnica do canto do cabecalho. E decoracao: fica atras do texto, com
 * opacidade baixa, e some em telas estreitas.
 */
function BlueprintArt() {
  return (
    <svg className="bp-header-art" viewBox="0 0 320 120" aria-hidden="true" focusable="false">
      <g stroke={C.borderStrong} strokeWidth="1" fill="none">
        <path d="M8 60h54M62 26v68M62 26h48M62 60h30M62 94h48" />
        <path d="M212 60h44M256 26v68M256 26h-40M256 94h-40" strokeDasharray="3 4" />
        <rect x="110" y="10" width="46" height="30" rx="2" fill={C.surface} />
        <rect x="110" y="46" width="46" height="30" rx="2" fill={C.surface} />
        <rect x="110" y="82" width="46" height="30" rx="2" fill={C.surface} />
      </g>
      <rect x="166" y="46" width="40" height="28" rx="2" fill={C.accentFill} />
      <circle cx="286" cy="60" r="11" fill="none" stroke={C.accent} strokeWidth="1.2" strokeDasharray="2.5 3.5" />
      <circle cx="286" cy="60" r="3.5" fill={C.accent} />
    </svg>
  );
}

// ─── Componentes de UI ───────────────────────────────────────────────────────
function Card({ title, children, accent, action }) {
  return (
    <div style={{
      background: C.surface, border: `1px solid ${accent || C.border}`,
      borderRadius: 10, padding: "18px 22px", marginBottom: 20, position: "relative",
    }}>
      {title && (
        <div style={{
          color: C.muted, fontSize: 11, fontWeight: 700, letterSpacing: "0.12em",
          textTransform: "uppercase", marginBottom: 14, paddingRight: action ? 140 : 0,
        }}>{title}</div>
      )}
      {action && <div style={{ position: "absolute", right: 18, top: 12 }}>{action}</div>}
      {children}
    </div>
  );
}

function MetricCard({ label, value, unit, tone, alert = false, sub }) {
  return (
    <div style={{
      background: C.surface,
      border: `1px solid ${alert ? `${C.bad}66` : C.border}`,
      borderRadius: 10, padding: 16,
    }}>
      <div style={{ alignItems: "center", display: "flex", gap: 8 }}>
        {tone && (
          <span
            aria-hidden="true"
            style={{ background: tone, borderRadius: 2, flex: "none", height: 8, width: 8 }}
          />
        )}
        <span style={{ color: C.muted, fontSize: 11, fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase" }}>
          {label}
        </span>
      </div>
      <div style={{
        color: alert ? C.bad : C.text,
        fontFamily: "monospace", fontSize: 23, fontWeight: 750, marginTop: 8,
      }}>
        {value}<span style={{ color: C.muted, fontSize: 13, marginLeft: 5 }}>{unit}</span>
      </div>
      {sub && <div style={{ color: C.muted, fontSize: 11, marginTop: 4 }}>{sub}</div>}
    </div>
  );
}

function StatusBadge({ label, tone }) {
  const colors = { good: C.good, warning: C.warn, bad: C.bad, muted: C.muted };
  const color = colors[tone] || C.muted;
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 7, color, fontSize: 12, fontWeight: 700 }}>
      <span style={{ width: 7, height: 7, borderRadius: "50%", background: color }} />
      {label}
    </span>
  );
}

function SettingsField({ label, type = "text", value, onChange, placeholder, help, min, max, step, disabled }) {
  return (
    <label style={{ display: "block", color: C.muted, fontSize: 11, fontWeight: 700, letterSpacing: "0.06em", textTransform: "uppercase" }}>
      {label}
      <input
        type={type} value={value} onChange={onChange} placeholder={placeholder}
        min={min} max={max} step={step} disabled={disabled}
        style={{
          width: "100%", marginTop: 6, background: C.bg, border: `1px solid ${C.border}`,
          borderRadius: 6, color: C.text, padding: "9px 10px", outline: "none",
        }}
      />
      {help && (
        <span style={{ display: "block", color: C.muted, fontSize: 10, fontWeight: 400, letterSpacing: 0, marginTop: 4, textTransform: "none" }}>
          {help}
        </span>
      )}
    </label>
  );
}

function ChartPlaceholder({ label }) {
  return (
    <div style={{ color: C.muted, display: "grid", minHeight: 240, placeItems: "center", fontSize: 13, textAlign: "center" }}>
      {label}
    </div>
  );
}

const TT = ({ active, payload, label }) => {
  if (!active || !payload?.length) return null;
  return (
    <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 6, padding: "8px 10px", fontSize: 12 }}>
      <div style={{ color: C.muted, marginBottom: 4 }}>{label}</div>
      {payload.map((entry) => (
        <div key={entry.dataKey} style={{ color: entry.color }}>
          {entry.name}: {typeof entry.value === "number" ? entry.value.toFixed(3) : entry.value}
        </div>
      ))}
    </div>
  );
};

const brushProps = { height: 20, stroke: C.border, travellerWidth: 8, fill: C.bg };

// ─── Aba: monitoramento ──────────────────────────────────────────────────────
function MonitorTab({
  acionamento, sensores, history, connection, onlineAcionamento, onlineSensores,
  config, alertSettings, alerts, onConfigChange, onConnect, onDisconnect,
  onRequestNotifications, onClearHistory, onExportCsv, lastUpdate,
}) {
  const mqttTone =
    connection.phase === "connected" ? "good"
    : connection.phase === "connecting" ? "warning"
    : connection.phase === "error" ? "bad" : "muted";

  const outOfRange = (value, min, max) =>
    value != null && (value < min || value > max);

  return (
    <>
      <Card title="Estado do monitoramento" accent={connection.phase === "error" ? `${C.bad}66` : undefined}>
        <div className="status-row">
          <StatusBadge label={connection.label} tone={mqttTone} />
          <StatusBadge
            label={`${DEVICE_ACIONAMENTO}: ${onlineAcionamento ? "online" : "sem telemetria"}`}
            tone={onlineAcionamento ? "good" : acionamento ? "bad" : "warning"}
          />
          <StatusBadge
            label={`${DEVICE_SENSORES}: ${onlineSensores ? "online" : "sem telemetria"}`}
            tone={onlineSensores ? "good" : sensores ? "bad" : "warning"}
          />
          <button className="secondary-button" onClick={onExportCsv} style={{ marginLeft: "auto" }}>
            Exportar CSV
          </button>
          <button className="secondary-button" onClick={onClearHistory}>Limpar historico</button>
        </div>
        <div style={{ color: C.muted, fontSize: 12, marginTop: 10 }}>Ultima leitura: {lastUpdate}</div>
        {connection.message && (
          <div style={{ color: connection.phase === "error" ? C.bad : C.muted, fontSize: 12, marginTop: 8 }}>
            {connection.message}
          </div>
        )}

        <div className="connection-row" style={{ borderTop: `1px solid ${C.border}`, marginTop: 14, paddingTop: 14 }}>
          <SettingsField
            label="URL MQTT WebSocket" value={config.url}
            onChange={(e) => onConfigChange({ ...config, url: e.target.value })}
            placeholder="wss://test.mosquitto.org:8081"
            help="Pagina em HTTPS exige wss://"
          />
          <SettingsField
            label="Prefixo de topicos" value={config.topicPrefix}
            onChange={(e) => onConfigChange({ ...config, topicPrefix: e.target.value })}
            placeholder="iotmotor"
          />
          <SettingsField
            label="Usuario" value={config.username}
            onChange={(e) => onConfigChange({ ...config, username: e.target.value })}
          />
          <SettingsField
            label="Senha" type="password" value={config.password}
            onChange={(e) => onConfigChange({ ...config, password: e.target.value })}
          />
          <div className="connection-actions">
            <button className="primary-button" onClick={onConnect} disabled={connection.phase === "connecting"}>
              Conectar
            </button>
            <button className="secondary-button" onClick={onDisconnect}>Desconectar</button>
          </div>
        </div>
      </Card>

      <BlueprintSection badge="M1" badgeTitle="Modulo 1">
        {DEVICE_LABELS[DEVICE_ACIONAMENTO]}
      </BlueprintSection>
      <div className="metric-grid" style={{ marginBottom: 20 }}>
        <MetricCard
          label="Tensao" value={fmt(acionamento?.voltage, 1)} unit="V"
          tone={C.blue}
          alert={outOfRange(acionamento?.voltage, alertSettings.voltageMin, alertSettings.voltageMax)}
        />
        <MetricCard
          label="Corrente" value={fmt(acionamento?.current, 2)} unit="A"
          tone={C.orange}
          alert={acionamento?.current > alertSettings.currentMax}
        />
        <MetricCard label="Potencia ativa" value={fmt(acionamento?.power, 0)} unit="W" tone={C.yellow} />
        <MetricCard label="Fator de potencia" value={fmt(acionamento?.pf, 2)} unit="" tone={C.aqua} />
        <MetricCard label="Frequencia" value={fmt(acionamento?.frequency, 1)} unit="Hz" tone={C.accent} />
        <MetricCard label="Energia acumulada" value={fmt(acionamento?.energy, 3)} unit="kWh" tone={C.aqua} />
      </div>

      <BlueprintSection badge="M2" badgeTitle="Modulo 2">
        {DEVICE_LABELS[DEVICE_SENSORES]}
      </BlueprintSection>
      <div className="metric-grid" style={{ marginBottom: 20 }}>
        <MetricCard
          label="Vibracao (RMS)" value={fmt(sensores?.vibration, 3)} unit="g"
          tone={C.blue}
          alert={sensores?.vibration > alertSettings.vibrationMax}
        />
        <MetricCard label="Vibracao (pico)" value={fmt(sensores?.vibrationPeak, 3)} unit="g" tone={C.magenta} />
        <MetricCard
          label="Temperatura" value={fmt(sensores?.temperature, 1)} unit="°C"
          tone={C.orange}
          alert={sensores?.temperature > alertSettings.temperatureMax}
          sub={sensores?.sdOk === false ? "SD indisponivel" : sensores?.sdSamples != null ? `${sensores.sdSamples} amostras no SD` : undefined}
        />
      </div>

      <div className="live-chart-grid">
        <Card title="Tensao — tendencia ao vivo">
          {history.some((h) => h.voltage != null) ? (
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={history} margin={{ top: 8, right: 14, left: -8, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis tick={{ fill: C.muted, fontSize: 11 }} tickFormatter={(v) => `${v}V`} domain={["auto", "auto"]} />
                <Tooltip content={<TT />} />
                <ReferenceLine y={alertSettings.voltageMin} stroke={C.bad} strokeDasharray="4 4" />
                <ReferenceLine y={alertSettings.voltageMax} stroke={C.bad} strokeDasharray="4 4" />
                <Line type="monotone" dataKey="voltage" name="Tensao" stroke={C.blue} strokeWidth={2} dot={false} connectNulls />
                <Brush dataKey="time" {...brushProps} />
              </LineChart>
            </ResponsiveContainer>
          ) : <ChartPlaceholder label="Aguardando leituras de tensao." />}
        </Card>

        <Card title="Corrente — tendencia ao vivo">
          {history.some((h) => h.current != null) ? (
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={history} margin={{ top: 8, right: 14, left: -8, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis tick={{ fill: C.muted, fontSize: 11 }} tickFormatter={(v) => `${v}A`} />
                <Tooltip content={<TT />} />
                <ReferenceLine y={alertSettings.currentMax} stroke={C.bad} strokeDasharray="4 4" />
                <Line type="monotone" dataKey="current" name="Corrente" stroke={C.orange} strokeWidth={2} dot={false} connectNulls />
                <Brush dataKey="time" {...brushProps} />
              </LineChart>
            </ResponsiveContainer>
          ) : <ChartPlaceholder label="Aguardando leituras de corrente." />}
        </Card>

        <Card title="Potencias — ativa e aparente">
          {history.some((h) => h.power != null) ? (
            <ResponsiveContainer width="100%" height={240}>
              <AreaChart data={history} margin={{ top: 8, right: 16, left: -8, bottom: 0 }}>
                <defs>
                  <linearGradient id="powerFill" x1="0" x2="0" y1="0" y2="1">
                    <stop offset="5%" stopColor={C.yellow} stopOpacity={0.5} />
                    <stop offset="95%" stopColor={C.yellow} stopOpacity={0.02} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis tick={{ fill: C.muted, fontSize: 11 }} />
                <Tooltip content={<TT />} />
                <Legend wrapperStyle={{ fontSize: 12, color: C.muted }} />
                <Area type="monotone" dataKey="power" name="Ativa (W)" stroke={C.yellow} strokeWidth={2} dot={false} fill="url(#powerFill)" connectNulls />
                <Line type="monotone" dataKey="apparentPower" name="Aparente (VA)" stroke={C.aqua} strokeWidth={2} dot={false} connectNulls />
                <Brush dataKey="time" {...brushProps} />
              </AreaChart>
            </ResponsiveContainer>
          ) : <ChartPlaceholder label="Aguardando leituras de potencia." />}
        </Card>

        <Card title="Vibracao — RMS e pico">
          {history.some((h) => h.vibration != null) ? (
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={history} margin={{ top: 8, right: 14, left: -8, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis tick={{ fill: C.muted, fontSize: 11 }} tickFormatter={(v) => `${v}g`} />
                <Tooltip content={<TT />} />
                <Legend wrapperStyle={{ fontSize: 12, color: C.muted }} />
                <ReferenceLine y={alertSettings.vibrationMax} stroke={C.bad} strokeDasharray="4 4" />
                <Line type="monotone" dataKey="vibration" name="RMS (g)" stroke={C.blue} strokeWidth={2} dot={false} connectNulls />
                <Line type="monotone" dataKey="vibrationPeak" name="Pico (g)" stroke={C.magenta} strokeWidth={2} dot={false} connectNulls />
                <Brush dataKey="time" {...brushProps} />
              </LineChart>
            </ResponsiveContainer>
          ) : <ChartPlaceholder label="Aguardando leituras de vibracao." />}
        </Card>

        <Card title="Temperatura do motor">
          {history.some((h) => h.temperature != null) ? (
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={history} margin={{ top: 8, right: 14, left: -8, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis tick={{ fill: C.muted, fontSize: 11 }} tickFormatter={(v) => `${v}°C`} />
                <Tooltip content={<TT />} />
                <ReferenceLine y={alertSettings.temperatureMax} stroke={C.bad} strokeDasharray="4 4" />
                <Line type="monotone" dataKey="temperature" name="Temperatura" stroke={C.orange} strokeWidth={2} dot={false} connectNulls />
                <Brush dataKey="time" {...brushProps} />
              </LineChart>
            </ResponsiveContainer>
          ) : <ChartPlaceholder label="Aguardando leituras de temperatura." />}
        </Card>

        <Card title="Fator de potencia">
          {history.some((h) => h.pf != null) ? (
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={history} margin={{ top: 8, right: 14, left: -8, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis domain={[0, 1.1]} tick={{ fill: C.muted, fontSize: 11 }} />
                <Tooltip content={<TT />} />
                <ReferenceLine y={1} stroke={C.border} strokeDasharray="4 4" />
                <Line type="monotone" dataKey="pf" name="Fator de potencia" stroke={C.aqua} strokeWidth={2} dot={false} connectNulls />
                <Brush dataKey="time" {...brushProps} />
              </LineChart>
            </ResponsiveContainer>
          ) : <ChartPlaceholder label="Aguardando leituras de fator de potencia." />}
        </Card>
      </div>

      <Card
        title={`Alertas recentes${alerts.length ? ` (${alerts.length})` : ""}`}
        accent={alerts.some((a) => a.severity === "critical") ? `${C.bad}66` : undefined}
        action={<button className="secondary-button" onClick={onRequestNotifications}>Ativar notificacoes</button>}
      >
        {alerts.length ? (
          <div style={{ display: "grid", gap: 8 }}>
            {alerts.map((alert) => (
              <div key={alert.id} style={{
                background: C.bg, borderLeft: `3px solid ${alert.severity === "critical" ? C.bad : C.warn}`,
                borderRadius: 6, padding: "10px 12px",
              }}>
                <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
                  <span style={{ color: alert.severity === "critical" ? C.bad : C.warn, fontWeight: 700, fontSize: 12 }}>
                    {alert.title}
                  </span>
                  <span style={{ color: C.muted, fontSize: 11 }}>{alert.createdAt.toLocaleTimeString("pt-BR")}</span>
                </div>
                <div style={{ color: C.muted, fontSize: 12, marginTop: 4 }}>{alert.message}</div>
              </div>
            ))}
          </div>
        ) : <div style={{ color: C.muted, fontSize: 13 }}>Nenhum alerta desde que este painel foi aberto.</div>}
      </Card>
    </>
  );
}

// ─── Aba: acionamento ────────────────────────────────────────────────────────
function AcionamentoTab({
  acionamento, statusLog, connected, online, commandMode,
  onCommandModeChange, onCommand, lastStatus,
}) {
  const state = acionamento?.state;
  const motorOn = acionamento?.motorOn === true;
  const locked = acionamento?.protectionLock === true;
  const podeComandar = connected;

  const bannerColor = locked ? C.bad : motorOn ? C.good : C.muted;

  return (
    <>
      <Card title="Estado do acionamento">
        <div className="state-banner" style={{ background: C.bg, border: `1px solid ${bannerColor}55` }}>
          <div>
            <div style={{ color: C.muted, fontSize: 11, fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase" }}>
              Motor
            </div>
            <div className="state-value" style={{ color: bannerColor }}>{motorStateLabel(state)}</div>
            <div style={{ color: C.muted, fontSize: 12, marginTop: 6 }}>
              Modo: {startModeLabel(acionamento?.mode)}
              {acionamento?.stopReason ? ` · ${acionamento.stopReason}` : ""}
            </div>
          </div>
          <div style={{ display: "grid", gap: 8, justifyItems: "end" }}>
            <StatusBadge
              label={online ? "Modulo 1 online" : "Modulo 1 sem telemetria"}
              tone={online ? "good" : "bad"}
            />
            {lastStatus && (
              <StatusBadge
                label={statusLabel(lastStatus)}
                tone={isProtectionStatus(lastStatus) ? "bad" : lastStatus === "offline" ? "bad" : "muted"}
              />
            )}
          </div>
        </div>

        {locked && (
          <div style={{
            background: `${C.bad}18`, border: `1px solid ${C.bad}66`, borderRadius: 8,
            color: C.text, fontSize: 13, marginTop: 14, padding: "12px 14px",
          }}>
            <strong style={{ color: C.bad }}>Protecao atuada.</strong>{" "}
            O Modulo 1 abriu os contatores e nao aceita nova partida.
            {acionamento?.stopReason ? ` Motivo: ${acionamento.stopReason}.` : ""}{" "}
            Envie <strong>Parar</strong> para rearmar antes de partir de novo.
          </div>
        )}

        <div className="command-row">
          <button
            className="command-button command-start"
            disabled={!podeComandar}
            onClick={() => onCommand("start", "direct")}
          >
            Partida direta
          </button>
          <button
            className="command-button command-star"
            disabled={!podeComandar}
            onClick={() => onCommand("start", "star_delta")}
          >
            Estrela-triangulo
          </button>
          <button
            className="command-button command-stop"
            disabled={!podeComandar}
            onClick={() => onCommand("stop", "manual_stop")}
          >
            Parar
          </button>
        </div>

        {!connected && (
          <div style={{ color: C.warn, fontSize: 12, marginTop: 12 }}>
            Conecte ao broker na aba Monitoramento para habilitar os comandos.
          </div>
        )}

        <div style={{ borderTop: `1px solid ${C.border}`, marginTop: 16, paddingTop: 14 }}>
          <div style={{ color: C.muted, fontSize: 11, fontWeight: 700, letterSpacing: "0.06em", textTransform: "uppercase", marginBottom: 8 }}>
            Envio do comando
          </div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 18, fontSize: 12, color: C.text }}>
            <label style={{ display: "inline-flex", alignItems: "center", gap: 7, cursor: "pointer" }}>
              <input
                type="radio" name="commandMode" value="device"
                checked={commandMode === "device"}
                onChange={() => onCommandModeChange("device")}
                style={{ accentColor: C.accent }}
              />
              Direcionado a {DEVICE_ACIONAMENTO}
            </label>
            <label style={{ display: "inline-flex", alignItems: "center", gap: 7, cursor: "pointer" }}>
              <input
                type="radio" name="commandMode" value="broadcast"
                checked={commandMode === "broadcast"}
                onChange={() => onCommandModeChange("broadcast")}
                style={{ accentColor: C.accent }}
              />
              Broadcast em request/command
            </label>
          </div>
        </div>
      </Card>

      <Card title="Registro de status do acionamento">
        {statusLog.length ? (
          <div className="status-log">
            {statusLog.map((entry) => (
              <div key={entry.id} className="status-log-line">
                <span style={{ color: C.muted }}>{entry.at.toLocaleTimeString("pt-BR")}</span>
                <span style={{ color: C.muted }}>{entry.deviceId}</span>
                <span style={{ color: isProtectionStatus(entry.status) ? C.bad : C.good }}>
                  {statusLabel(entry.status)}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <div style={{ color: C.muted, fontSize: 13 }}>
            Nenhuma mensagem de status recebida ainda.
          </div>
        )}
      </Card>
    </>
  );
}

// ─── Aba: configuracoes ──────────────────────────────────────────────────────
function ConfiguracoesTab({
  connected, alertSettings, onAlertSettingsChange, onStorageConfig, onTelemetryRequest, sensores,
}) {
  const [retentionDays, setRetentionDays] = useState("30");

  return (
    <>
      <Card title="Retencao do cartao SD (Modulo 2)">
        <div className="settings-pair">
          <SettingsField
            label="Retencao (dias)" type="number" min={1} max={3650}
            value={retentionDays} onChange={(e) => setRetentionDays(e.target.value)}
            help={
              sensores?.retentionDays != null
                ? `Valor aplicado no modulo: ${sensores.retentionDays} dias`
                : "Aguardando a telemetria do Modulo 2 informar o valor atual."
            }
          />
          <div className="connection-actions">
            <button
              className="primary-button"
              disabled={!connected}
              onClick={() => onStorageConfig(Number(retentionDays))}
            >
              Aplicar retencao
            </button>
          </div>
        </div>
        <div style={{ color: C.muted, fontSize: 12, marginTop: 12 }}>
          Publica <code>storage_config</code> em <code>request/command</code>. O Modulo 2 apaga os
          arquivos diarios mais antigos que o limite e guarda a retencao em NVS.
        </div>
      </Card>

      <Card title="Leitura sob demanda">
        <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
          <button className="secondary-button" disabled={!connected} onClick={() => onTelemetryRequest([])}>
            Pedir todas as grandezas
          </button>
          <button
            className="secondary-button" disabled={!connected}
            onClick={() => onTelemetryRequest(["voltage", "current", "power", "pf", "frequency", "energy"])}
          >
            So as eletricas
          </button>
          <button
            className="secondary-button" disabled={!connected}
            onClick={() => onTelemetryRequest(["vibration", "temperature"])}
          >
            So vibracao e temperatura
          </button>
        </div>
        <div style={{ color: C.muted, fontSize: 12, marginTop: 12 }}>
          Publica <code>telemetry_request</code> em <code>request/telemetry</code>. Os modulos
          respondem fora da cadencia normal de 1 s.
        </div>
      </Card>

      <Card title="Limites de alerta do painel">
        <div className="alert-settings-row">
          <SettingsField
            label="Tensao minima (V)" type="number" value={alertSettings.voltageMin}
            onChange={(e) => onAlertSettingsChange({ ...alertSettings, voltageMin: Number(e.target.value) })}
          />
          <SettingsField
            label="Tensao maxima (V)" type="number" value={alertSettings.voltageMax}
            onChange={(e) => onAlertSettingsChange({ ...alertSettings, voltageMax: Number(e.target.value) })}
          />
          <SettingsField
            label="Corrente maxima (A)" type="number" step="0.1" value={alertSettings.currentMax}
            onChange={(e) => onAlertSettingsChange({ ...alertSettings, currentMax: Number(e.target.value) })}
          />
          <SettingsField
            label="Vibracao maxima (g)" type="number" step="0.1" value={alertSettings.vibrationMax}
            onChange={(e) => onAlertSettingsChange({ ...alertSettings, vibrationMax: Number(e.target.value) })}
          />
        </div>
        <div className="settings-pair" style={{ marginTop: 12 }}>
          <SettingsField
            label="Temperatura maxima (°C)" type="number" value={alertSettings.temperatureMax}
            onChange={(e) => onAlertSettingsChange({ ...alertSettings, temperatureMax: Number(e.target.value) })}
          />
        </div>
        <div style={{ color: C.muted, fontSize: 12, marginTop: 12 }}>
          Estes limites valem so para os avisos deste painel. As protecoes que realmente abrem os
          contatores sao as do firmware do Modulo 1 e nao mudam por aqui.
        </div>
      </Card>
    </>
  );
}

// ─── Aplicacao ───────────────────────────────────────────────────────────────
export default function App() {
  const [tab, setTab] = useState("monitor");
  const [mqttConfig, setMqttConfig] = useState(() => loadSettings(MQTT_SETTINGS_KEY, DEFAULT_MQTT_CONFIG));
  const [alertSettings, setAlertSettings] = useState(() => loadSettings(ALERT_SETTINGS_KEY, DEFAULT_ALERT_SETTINGS));
  const [commandMode, setCommandMode] = useState("device");
  const [connection, setConnection] = useState({
    phase: "disconnected",
    label: "MQTT desconectado",
    message: "Configure um endpoint WebSocket para iniciar.",
  });
  const [telemetryByDevice, setTelemetryByDevice] = useState({});
  const [statusByDevice, setStatusByDevice] = useState({});
  const [lastSeenByDevice, setLastSeenByDevice] = useState({});
  const [history, setHistory] = useState([]);
  const [statusLog, setStatusLog] = useState([]);
  const [alerts, setAlerts] = useState([]);
  const [clock, setClock] = useState(Date.now());

  const clientRef = useRef(null);
  const alertSettingsRef = useRef(alertSettings);
  const alertGateRef = useRef({});
  const latestRef = useRef({});

  useEffect(() => {
    alertSettingsRef.current = alertSettings;
    try { window.localStorage.setItem(ALERT_SETTINGS_KEY, JSON.stringify(alertSettings)); } catch (_) {}
  }, [alertSettings]);

  useEffect(() => {
    // A senha nunca vai para o localStorage.
    const { password, ...safeConfig } = mqttConfig;
    try { window.localStorage.setItem(MQTT_SETTINGS_KEY, JSON.stringify(safeConfig)); } catch (_) {}
  }, [mqttConfig]);

  useEffect(() => {
    const timer = window.setInterval(() => setClock(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => () => { clientRef.current?.end(true); }, []);

  const topics = useMemo(() => {
    try { return buildTopics(mqttConfig.topicPrefix); } catch (_) { return null; }
  }, [mqttConfig.topicPrefix]);

  const connected = connection.phase === "connected";
  const acionamento = telemetryByDevice[DEVICE_ACIONAMENTO] ?? null;
  const sensores = telemetryByDevice[DEVICE_SENSORES] ?? null;

  const isOnline = (deviceId) => {
    const seen = lastSeenByDevice[deviceId];
    return Boolean(connected && seen && clock - seen <= DEVICE_TIMEOUT_MS);
  };
  const onlineAcionamento = isOnline(DEVICE_ACIONAMENTO);
  const onlineSensores = isOnline(DEVICE_SENSORES);

  const lastUpdate = useMemo(() => {
    const stamps = Object.values(lastSeenByDevice);
    if (!stamps.length) return "Aguardando a primeira leitura";
    return new Date(Math.max(...stamps)).toLocaleTimeString("pt-BR");
  }, [lastSeenByDevice]);

  function appendAlert({ key, title, message, severity }) {
    if (alertGateRef.current[key]) return;
    alertGateRef.current[key] = true;

    const alert = { id: `${key}-${Date.now()}`, title, message, severity, createdAt: new Date() };
    setAlerts((current) => [alert, ...current].slice(0, 8));

    if ("Notification" in window && Notification.permission === "granted") {
      new Notification(title, { body: message });
    }
  }

  function clearAlertGate(key) {
    alertGateRef.current[key] = false;
  }

  function evaluateAlerts(sample) {
    const rules = alertSettingsRef.current;

    if (sample.voltage != null) {
      if (sample.voltage < rules.voltageMin || sample.voltage > rules.voltageMax) {
        appendAlert({
          key: "voltage",
          title: "Tensao fora da faixa",
          message: `Valor: ${sample.voltage.toFixed(1)} V · Faixa: ${rules.voltageMin}–${rules.voltageMax} V`,
          severity: "warning",
        });
      } else {
        clearAlertGate("voltage");
      }
    }

    if (sample.current != null) {
      if (sample.current > rules.currentMax) {
        appendAlert({
          key: "current",
          title: "Corrente acima do limite",
          message: `Valor: ${sample.current.toFixed(2)} A · Limite: ${rules.currentMax} A`,
          severity: "critical",
        });
      } else if (sample.current <= rules.currentMax * 0.95) {
        clearAlertGate("current");
      }
    }

    if (sample.vibration != null) {
      if (sample.vibration > rules.vibrationMax) {
        appendAlert({
          key: "vibration",
          title: "Vibracao acima do limite",
          message: `Valor: ${sample.vibration.toFixed(3)} g · Limite: ${rules.vibrationMax} g`,
          severity: "critical",
        });
      } else if (sample.vibration <= rules.vibrationMax * 0.95) {
        clearAlertGate("vibration");
      }
    }

    if (sample.temperature != null) {
      if (sample.temperature > rules.temperatureMax) {
        appendAlert({
          key: "temperature",
          title: "Temperatura acima do limite",
          message: `Valor: ${sample.temperature.toFixed(1)} °C · Limite: ${rules.temperatureMax} °C`,
          severity: "critical",
        });
      } else if (sample.temperature <= rules.temperatureMax * 0.95) {
        clearAlertGate("temperature");
      }
    }
  }

  function handleTelemetry(deviceId, sample) {
    const receivedAt = sample.receivedAt ?? new Date();

    setTelemetryByDevice((current) => ({ ...current, [deviceId]: sample }));
    setLastSeenByDevice((current) => ({ ...current, [deviceId]: receivedAt.getTime() }));
    clearAlertGate(`offline-${deviceId}`);

    // Mescla o ultimo valor conhecido de cada modulo numa unica linha temporal,
    // para que os graficos dos dois dispositivos compartilhem o eixo do tempo.
    const merged = { ...latestRef.current };
    for (const [key, value] of Object.entries(sample)) {
      if (key === "receivedAt" || key === "deviceId" || value == null) continue;
      merged[key] = value;
    }
    latestRef.current = merged;

    setHistory((current) => [
      ...current,
      { ...merged, time: receivedAt.toLocaleTimeString("pt-BR") },
    ].slice(-HISTORY_LIMIT));

    evaluateAlerts(sample);
  }

  function handleStatus(deviceId, status) {
    if (!status) return;

    setStatusByDevice((current) => ({ ...current, [deviceId]: status }));
    setStatusLog((current) => [
      { id: `${deviceId}-${status}-${Date.now()}`, deviceId, status, at: new Date() },
      ...current,
    ].slice(0, STATUS_LOG_LIMIT));

    if (isProtectionStatus(status)) {
      // Cada protecao tem porta propria, para nao suprimir uma causa diferente.
      appendAlert({
        key: `protection-${status}`,
        title: "Protecao atuou no Modulo 1",
        message: `${statusLabel(status)} · o motor foi desligado pelo firmware.`,
        severity: "critical",
      });
    }
  }

  function connect() {
    clientRef.current?.removeAllListeners();
    clientRef.current?.end(true);
    setConnection({ phase: "connecting", label: "MQTT conectando", message: "Conectando ao broker e assinando os topicos…" });

    try {
      clientRef.current = connectMqtt(mqttConfig, {
        onConnected: (activeTopics) => setConnection({
          phase: "connected",
          label: "MQTT conectado",
          message: `Assinando ${activeTopics.telemetryWildcard} e ${activeTopics.statusWildcard}`,
        }),
        onTelemetry: handleTelemetry,
        onStatus: handleStatus,
        onPayloadError: (error) => setConnection((current) => ({ ...current, message: `Payload ignorado: ${error.message}` })),
        onReconnecting: () => setConnection({ phase: "connecting", label: "MQTT reconectando", message: "Tentando restabelecer a conexao…" }),
        onOffline: () => setConnection({ phase: "error", label: "MQTT offline", message: "O broker nao esta acessivel no momento." }),
        onClosed: () => setConnection((current) => current.phase === "disconnected"
          ? current
          : { phase: "disconnected", label: "MQTT desconectado", message: "Conexao MQTT encerrada." }),
        onError: (error) => setConnection({ phase: "error", label: "Erro MQTT", message: error.message || "Nao foi possivel conectar ao broker." }),
      });
    } catch (error) {
      setConnection({ phase: "error", label: "Configuracao invalida", message: error.message });
    }
  }

  function disconnect() {
    clientRef.current?.removeAllListeners();
    clientRef.current?.end(true);
    clientRef.current = null;
    setConnection({ phase: "disconnected", label: "MQTT desconectado", message: "Monitoramento pausado." });
  }

  function clearHistory() {
    if (!window.confirm("Limpar historico? Os valores e graficos atuais serao apagados.")) return;
    setTelemetryByDevice({});
    setLastSeenByDevice({});
    setHistory([]);
    setAlerts([]);
    setStatusLog([]);
    latestRef.current = {};
    alertGateRef.current = {};
  }

  function exportCsv() {
    if (!history.length) {
      window.alert("Ainda nao ha leituras para exportar.");
      return;
    }

    const blob = new Blob([historyToCsv(history)], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `iotmotor_${new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-")}.csv`;
    anchor.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
  }

  function requestNotifications() {
    if (!("Notification" in window)) {
      setConnection((current) => ({ ...current, message: "Este navegador nao oferece notificacoes do sistema." }));
      return;
    }

    Notification.requestPermission().then((permission) => {
      setConnection((current) => ({
        ...current,
        message: permission === "granted"
          ? "Notificacoes do sistema ativadas."
          : "Permissao de notificacoes nao concedida.",
      }));
    });
  }

  function sendMotorCommand(command, mode) {
    if (!clientRef.current || !topics) return;

    // Partida aciona maquina real: confirma antes de publicar.
    if (command === "start") {
      const rotulo = startModeLabel(mode).toLowerCase();
      if (!window.confirm(`Confirmar ${rotulo}? O motor vai partir.`)) return;
    }

    try {
      if (commandMode === "broadcast") {
        publishJson(clientRef.current, topics.commandRequest, buildCommandRequest({ command, mode }));
      } else {
        publishJson(
          clientRef.current,
          topics.commandFor(DEVICE_ACIONAMENTO),
          buildDeviceCommand({ deviceId: DEVICE_ACIONAMENTO, command, mode }),
        );
      }
      setConnection((current) => ({
        ...current,
        message: `Comando publicado: ${command === "stop" ? "parada" : startModeLabel(mode).toLowerCase()}.`,
      }));
    } catch (error) {
      setConnection((current) => ({ ...current, message: `Falha ao publicar comando: ${error.message}` }));
    }
  }

  function sendStorageConfig(days) {
    if (!clientRef.current || !topics) return;
    try {
      publishJson(
        clientRef.current,
        topics.commandRequest,
        buildStorageConfig({ retentionDays: days, deviceId: DEVICE_SENSORES }),
      );
      setConnection((current) => ({ ...current, message: `Retencao de ${days} dias enviada ao ${DEVICE_SENSORES}.` }));
    } catch (error) {
      setConnection((current) => ({ ...current, message: `Falha ao enviar a retencao: ${error.message}` }));
    }
  }

  function sendTelemetryRequest(fields) {
    if (!clientRef.current || !topics) return;
    try {
      publishJson(clientRef.current, topics.telemetryRequest, buildTelemetryRequest({ fields }));
      setConnection((current) => ({ ...current, message: "Leitura sob demanda solicitada." }));
    } catch (error) {
      setConnection((current) => ({ ...current, message: `Falha ao pedir leitura: ${error.message}` }));
    }
  }

  // Avisa quando um modulo que ja falou para de responder.
  useEffect(() => {
    if (!connected) return;

    for (const deviceId of [DEVICE_ACIONAMENTO, DEVICE_SENSORES]) {
      const seen = lastSeenByDevice[deviceId];
      if (!seen) continue;
      if (clock - seen > DEVICE_TIMEOUT_MS) {
        appendAlert({
          key: `offline-${deviceId}`,
          title: `${deviceId} sem telemetria`,
          message: "Nenhuma leitura recebida nos ultimos 15 segundos.",
          severity: "critical",
        });
      }
    }
  }, [clock, connected, lastSeenByDevice]);

  const tabs = [
    { id: "monitor", label: "Monitoramento" },
    { id: "acionamento", label: "Acionamento" },
    { id: "config", label: "Configuracoes" },
  ];

  const subtitles = {
    monitor: "Telemetria MQTT ao vivo dos dois modulos · alertas operacionais",
    acionamento: "Partida direta · estrela-triangulo · parada · estado das protecoes",
    config: "Retencao do SD · leitura sob demanda · limites de alerta do painel",
  };

  return (
    <div style={{
      background: C.bg, minHeight: "100vh", color: C.text,
      fontFamily: "'Inter', 'Segoe UI', sans-serif",
      padding: "32px 24px", maxWidth: 1160, margin: "0 auto",
    }}>
      <header className="bp-header">
        <BlueprintArt />
        <div className="bp-eyebrow">ESP32 + ESP32-S3 · PZEM-004T · MPU6050</div>
        <h1 className="bp-title">
          <span className="bp-title-accent">IoTMotor</span> — Painel de Operacao
        </h1>
        <p style={{ color: C.muted, fontSize: 13, marginTop: 6, position: "relative" }}>
          {subtitles[tab]}
        </p>
      </header>

      <div style={{ display: "flex", gap: 4, marginBottom: 24, borderBottom: `1px solid ${C.border}` }}>
        {tabs.map((t) => (
          <button key={t.id} onClick={() => setTab(t.id)} style={{
            background: "none", border: "none",
            color: tab === t.id ? C.accent : C.muted,
            fontWeight: tab === t.id ? 700 : 400, fontSize: 14, cursor: "pointer",
            padding: "8px 18px",
            borderBottom: `2px solid ${tab === t.id ? C.accent : "transparent"}`,
            marginBottom: -1,
          }}>{t.label}</button>
        ))}
      </div>

      {tab === "monitor" && (
        <MonitorTab
          acionamento={acionamento}
          sensores={sensores}
          history={history}
          connection={connection}
          onlineAcionamento={onlineAcionamento}
          onlineSensores={onlineSensores}
          config={mqttConfig}
          alertSettings={alertSettings}
          alerts={alerts}
          lastUpdate={lastUpdate}
          onConfigChange={setMqttConfig}
          onConnect={connect}
          onDisconnect={disconnect}
          onRequestNotifications={requestNotifications}
          onClearHistory={clearHistory}
          onExportCsv={exportCsv}
        />
      )}

      {tab === "acionamento" && (
        <AcionamentoTab
          acionamento={acionamento}
          statusLog={statusLog}
          connected={connected}
          online={onlineAcionamento}
          commandMode={commandMode}
          onCommandModeChange={setCommandMode}
          onCommand={sendMotorCommand}
          lastStatus={statusByDevice[DEVICE_ACIONAMENTO]}
        />
      )}

      {tab === "config" && (
        <ConfiguracoesTab
          connected={connected}
          alertSettings={alertSettings}
          onAlertSettingsChange={setAlertSettings}
          onStorageConfig={sendStorageConfig}
          onTelemetryRequest={sendTelemetryRequest}
          sensores={sensores}
        />
      )}
    </div>
  );
}
