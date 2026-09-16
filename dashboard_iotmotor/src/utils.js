/** Formata numero com [d] casas decimais; devolve "—" quando nao houver valor. */
export const fmt = (v, d = 2) => (Number.isFinite(v) ? v.toFixed(d) : "—");

/**
 * Normaliza fator de potencia em escala decimal.
 * Aceita valores ja em decimal ou em percentual (ex.: 98 -> 0.98).
 */
export function normalizePowerFactor(value) {
  if (value == null) return null;
  const number = Number(value);
  if (!Number.isFinite(number)) return null;

  const magnitude = Math.abs(number);
  const normalized = magnitude > 1 && magnitude <= 100 ? magnitude / 100 : magnitude;
  return Math.min(1, normalized);
}

/** Media, desvio padrao e maximo absoluto de uma serie. */
export function computeStats(values) {
  const usable = values.filter((v) => Number.isFinite(v));
  if (usable.length === 0) return { mean: null, std: null, max: null, count: 0 };

  const mean = usable.reduce((a, b) => a + b, 0) / usable.length;
  const std = Math.sqrt(
    usable.map((v) => (v - mean) ** 2).reduce((a, b) => a + b, 0) / usable.length,
  );
  const max = Math.max(...usable.map(Math.abs));
  return { mean, std, max, count: usable.length };
}

/** Formata uma duracao em milissegundos (ex.: "2min 05s"). */
export function formatDuration(milliseconds) {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours) return `${hours}h ${String(minutes).padStart(2, "0")}min`;
  if (minutes) return `${minutes}min ${String(seconds).padStart(2, "0")}s`;
  return `${seconds}s`;
}

/** Rotulo do estado do acionamento publicado pelo Modulo 1. */
export function motorStateLabel(state) {
  switch (String(state ?? "").trim().toLowerCase()) {
    case "rodando":     return "RODANDO";
    case "estrela":     return "PARTINDO (ESTRELA)";
    case "tempo_morto": return "COMUTANDO";
    case "parado":      return "PARADO";
    default:            return "—";
  }
}

/** Rotulo do modo de partida usado no comando. */
export function startModeLabel(mode) {
  switch (String(mode ?? "").trim().toLowerCase()) {
    case "direct":      return "Partida direta";
    case "star_delta":  return "Estrela-triangulo";
    case "manual_stop": return "Parada manual";
    default:            return mode ? String(mode) : "—";
  }
}

const CSV_COLUMNS = [
  ["time", "horario"],
  ["voltage", "tensao_v"],
  ["current", "corrente_a"],
  ["power", "potencia_w"],
  ["apparentPower", "potencia_aparente_va"],
  ["pf", "fator_potencia"],
  ["frequency", "frequencia_hz"],
  ["energy", "energia_kwh"],
  ["vibration", "vibracao_rms_g"],
  ["vibrationPeak", "vibracao_pico_g"],
  ["temperature", "temperatura_c"],
  ["motorOn", "motor_ligado"],
];

/** Escapa um campo para CSV quando ele contiver separador, aspas ou quebra. */
function csvCell(value) {
  if (value == null) return "";
  const text = typeof value === "boolean" ? (value ? "1" : "0") : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

/** Converte o historico ao vivo em CSV, para analise fora do painel. */
export function historyToCsv(history) {
  const header = CSV_COLUMNS.map(([, label]) => label).join(",");
  const rows = history.map((row) =>
    CSV_COLUMNS.map(([key]) => csvCell(row[key])).join(","),
  );
  return [header, ...rows].join("\n");
}
