const test = require('node:test');
const assert = require('node:assert/strict');
const {lerDia, serieDoHistorico, resumoDoHistorico, GRANDEZAS_HISTORICO} = require('./board-history.js');

const HORA = 3600000;
const g = id => GRANDEZAS_HISTORICO.find(x => x.id === id);
// Dia 20000 (desde 1970) com duas horas: 10 h ligado 45 min e 11 h parado.
const dia = lerDia({device_id: 'esp32-02', day: 20000, v: 1, hours: [
  [10, 912, 1034, 2201, 452, 480, 31, 55, 45],
  [11, null, null, 2210, 401, 410, null, null, 0],
  [30, 1, 1, 1, 1, 1, 1, 1, 1]  // Hora inválida: descartada.
]});
const agora = (20000 * 24 + 12) * HORA;

test('lê o dia publicado pela placa e descarta linhas inválidas', () => {
  assert.equal(dia.horas.length, 2);
  assert.equal(lerDia({day: 0, hours: []}), null);
  assert.equal(lerDia({day: 5}), null);
});

test('série por grandeza nas escalas da placa, só com leitura', () => {
  assert.deepEqual(serieDoHistorico([dia], g('corrente'), agora),
    [{t: (20000 * 24 + 10) * HORA, media: 9.12, maximo: 10.34}]);
  const temp = serieDoHistorico([dia], g('temperatura'), agora);
  assert.deepEqual(temp.map(p => [p.media, p.maximo]), [[45.2, 48], [40.1, 41]]);
  assert.equal(serieDoHistorico([dia], g('tensao'), agora)[1].maximo, null);
  // Mais de 7 dias atrás: fora.
  assert.equal(serieDoHistorico([dia], g('corrente'), agora + 8 * 24 * HORA).length, 0);
});

test('resumo: tempo ligado e máximos dos 7 dias', () => {
  assert.equal(resumoDoHistorico([dia], agora),
    'Motor ligado 0 h 45 min em 7 dias · Corrente máxima 10,34 A · Temperatura máxima 48,0 °C');
  assert.equal(resumoDoHistorico([null], agora), '');
});

test('vibração em mm/s; dias antigos em g ficam fora do gráfico', () => {
  const novo = lerDia({day: 20000, v: 1, vib: 'mm/s', hours: [[10, 912, 1034, 2201, 452, 480, 231, 455, 45]]});
  assert.equal(g('vibracao').unidade, 'mm/s');
  assert.deepEqual(serieDoHistorico([novo], g('vibracao'), agora).map(p => [p.media, p.maximo]), [[2.31, 4.55]]);
  // O dia do exemplo acima veio do firmware antigo (sem "vib"): vibração em g.
  assert.equal(serieDoHistorico([dia], g('vibracao'), agora).length, 0);
  assert.equal(serieDoHistorico([dia], g('corrente'), agora).length, 1, 'o resto do dia antigo continua');
});
