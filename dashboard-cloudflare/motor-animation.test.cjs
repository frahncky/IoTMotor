const test = require('node:test');
const assert = require('node:assert/strict');

const {
  visualDpsForRpm,
  startupDurationForKind,
  startupSpeed,
  coastDuration,
  coastSpeed,
  motionAppearance,
} = require('./motor-animation.js');

test('RPM de placa escala a velocidade visual sem virar rotação literal', () => {
  const lenta = visualDpsForRpm(900);
  const media = visualDpsForRpm(1750);
  const rapida = visualDpsForRpm(3500);
  assert.ok(lenta < media);
  assert.ok(media < rapida);
  assert.ok(lenta >= 540);
  assert.ok(rapida <= 1260);
  assert.equal(visualDpsForRpm(null), visualDpsForRpm(1750));
});

test('partida direta é contínua e estrela-triângulo tem transiente de comutação', () => {
  assert.equal(startupDurationForKind('direct'), 1.5);
  assert.equal(startupDurationForKind('sequenced'), 2.2);
  assert.equal(startupDurationForKind('star-delta'), 2.8);
  assert.equal(startupSpeed(0, 'direct'), 0);
  assert.equal(startupSpeed(1, 'direct'), 1);
  assert.ok(startupSpeed(0.61, 'star-delta') < startupSpeed(0.61, 'direct'));
  assert.ok(startupSpeed(0.64, 'sequenced') < startupSpeed(0.64, 'direct'));
});


test('pás ficam menos definidas apenas em alta velocidade', () => {
  const parada = motionAppearance(0);
  const regime = motionAppearance(1);
  assert.equal(parada.blurPx, 0);
  assert.equal(parada.bladeOpacity, 1);
  assert.ok(regime.blurPx > 0);
  assert.ok(regime.bladeOpacity < 1);
  assert.ok(regime.markerOpacity < regime.bladeOpacity);
});

test('parada por inércia é suave, chega a zero e dura mais em regime', () => {
  assert.equal(coastDuration(1), 3.6);
  assert.ok(coastDuration(0.2) < coastDuration(1));
  assert.ok(coastDuration(0) > 0);
  const total = coastDuration(1);
  assert.equal(coastSpeed(1, 0, total), 1);
  const meio = coastSpeed(1, total / 2, total);
  assert.ok(meio > 0 && meio < 0.5);
  assert.equal(coastSpeed(1, total, total), 0);
});

test('efeitos do desenho: tudo ligado por padrão e JSON estranho não quebra', () => {
  const {lerPreferenciasAnimacao, ANIMACAO_PADRAO} = require('./motor-animation.js');
  assert.deepEqual(lerPreferenciasAnimacao(null), {...ANIMACAO_PADRAO});
  assert.deepEqual(lerPreferenciasAnimacao('{quebrado'), {...ANIMACAO_PADRAO});
  assert.deepEqual(lerPreferenciasAnimacao('{"tremor":false,"giro":"sim","extra":1}'),
    {giro: true, tremor: false, calor: true, alarme: true});
});

test('efeitos desligados viram data-anim-*="off"; ligados não marcam nada', () => {
  const {atributosAnimacao} = require('./motor-animation.js');
  assert.deepEqual(atributosAnimacao({giro: false, tremor: true, calor: false, alarme: true}),
    {animGiro: 'off', animTremor: null, animCalor: 'off', animAlarme: null});
});
