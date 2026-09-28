const test = require('node:test');
const assert = require('node:assert/strict');
const {
  linkLossMode,
  normalizeLinkLossWait,
} = require('./remote-controls.js');

test('perda de conexao separa manter ligado de desligar', () => {
  assert.equal(linkLossMode(-1), 'keep');
  assert.equal(linkLossMode(0), 'stop');
  assert.equal(linkLossMode(30), 'stop');
});

test('tempo para desligar aceita somente 0 a 3600 segundos', () => {
  assert.equal(normalizeLinkLossWait('0'), 0);
  assert.equal(normalizeLinkLossWait('10'), 10);
  assert.equal(normalizeLinkLossWait('3600'), 3600);
  assert.equal(normalizeLinkLossWait('-1'), 10);
  assert.equal(normalizeLinkLossWait('3601'), 10);
  assert.equal(normalizeLinkLossWait('texto'), 10);
});
