import assert from "node:assert/strict";
import test from "node:test";

import {
  computeStats,
  fmt,
  formatDuration,
  historyToCsv,
  motorStateLabel,
  normalizePowerFactor,
  startModeLabel,
} from "./utils.js";

test("fmt devolve travessao quando nao ha numero", () => {
  assert.equal(fmt(null), "—");
  assert.equal(fmt(undefined), "—");
  assert.equal(fmt(Number.NaN), "—");
  assert.equal(fmt(220.456, 1), "220.5");
});

test("normalizePowerFactor aceita decimal e percentual", () => {
  assert.equal(normalizePowerFactor(0.92), 0.92);
  assert.equal(normalizePowerFactor(92), 0.92);
  assert.equal(normalizePowerFactor("0,87"), null); // virgula nao e numero valido aqui
  assert.equal(normalizePowerFactor(null), null);
});

test("computeStats ignora valores nao finitos", () => {
  const stats = computeStats([1, 2, 3, Number.NaN, null]);
  assert.equal(stats.count, 3);
  assert.equal(stats.mean, 2);
  assert.equal(stats.max, 3);
});

test("computeStats devolve nulos para serie vazia", () => {
  const stats = computeStats([]);
  assert.equal(stats.count, 0);
  assert.equal(stats.mean, null);
});

test("formatDuration cobre segundos, minutos e horas", () => {
  assert.equal(formatDuration(5_000), "5s");
  assert.equal(formatDuration(125_000), "2min 05s");
  assert.equal(formatDuration(3_725_000), "1h 02min");
});

test("motorStateLabel traduz os estados do firmware", () => {
  assert.equal(motorStateLabel("rodando"), "RODANDO");
  assert.equal(motorStateLabel("estrela"), "PARTINDO (ESTRELA)");
  assert.equal(motorStateLabel("tempo_morto"), "COMUTANDO");
  assert.equal(motorStateLabel("parado"), "PARADO");
  assert.equal(motorStateLabel(null), "—");
});

test("startModeLabel cobre os modos de partida", () => {
  assert.equal(startModeLabel("direct"), "Partida direta");
  assert.equal(startModeLabel("star_delta"), "Estrela-triangulo");
  assert.equal(startModeLabel("manual_stop"), "Parada manual");
});

test("historyToCsv monta cabecalho e linhas", () => {
  const csv = historyToCsv([
    { time: "10:00:00", voltage: 220.1, current: 5.2, motorOn: true },
  ]);
  const [header, row] = csv.split("\n");

  assert.ok(header.startsWith("horario,tensao_v,corrente_a"));
  assert.ok(row.startsWith("10:00:00,220.1,5.2"));
  assert.ok(row.endsWith(",1"));
});

test("historyToCsv escapa virgulas e aspas", () => {
  const csv = historyToCsv([{ time: 'as "dez", em ponto' }]);
  const row = csv.split("\n")[1];

  assert.equal(row.split(",").length > 1, true, "campo escapado mantem a virgula");
  assert.ok(row.startsWith('"as ""dez"", em ponto"'));
});
