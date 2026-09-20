const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');

// Carrega o modulo do painel com o que um navegador oferece.
function setup() {
  const guardado = new Map();
  const context = vm.createContext({
    window: {}, crypto: globalThis.crypto, TextEncoder, Uint8Array, JSON, Map, Boolean, String, Error,
    globalThis: {crypto: globalThis.crypto},
    btoa: texto => Buffer.from(texto, 'binary').toString('base64'),
    localStorage: {
      getItem: chave => (guardado.has(chave) ? guardado.get(chave) : null),
      setItem: (chave, valor) => guardado.set(chave, valor),
      removeItem: chave => guardado.delete(chave)
    }
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'command-seal.js'), 'utf8'), context);
  return {selo: context.window.iotmotorSelo, guardado};
}

// Mesma conta do firmware (comando_seguro.h): SHA-256(rotulo | senha | placa).
function chaveDaPlaca(senha, placa) {
  return crypto.createHash('sha256').update('iotmotor-cmd-v1' + senha + placa, 'utf8').digest();
}

// O que a placa faz ao receber: separa iv, texto e tag, e decifra com a AAD.
function abrirComoAPlaca(selado, senha, placa) {
  const pacote = JSON.parse(selado);
  const bruto = Buffer.from(pacote.sealed, 'base64');
  const iv = bruto.subarray(0, 12);
  const tag = bruto.subarray(bruto.length - 16);
  const cifrado = bruto.subarray(12, bruto.length - 16);
  const decifra = crypto.createDecipheriv('aes-256-gcm', chaveDaPlaca(senha, placa), iv);
  decifra.setAAD(Buffer.from(placa, 'utf8'));
  decifra.setAuthTag(tag);
  return JSON.parse(Buffer.concat([decifra.update(cifrado), decifra.final()]).toString('utf8'));
}

const AUTH = {device_id: 'esp32-01', secure: true, challenge: 'a'.repeat(32)};
const COMANDO = {v: 1, device_id: 'esp32-01', seq: '123', action: 'start', profile: 'estrela'};

test('placa sem senha continua recebendo comando aberto, sem promessa', async () => {
  const {selo} = setup();
  selo.registrarAuth('esp32-01', {device_id: 'esp32-01', secure: false});
  assert.equal(selo.exigeSelo('esp32-01'), false);
  assert.equal(selo.impedimento('esp32-01'), '');
  assert.deepEqual(JSON.parse(selo.empacotarAberto('esp32-01', COMANDO)), COMANDO);
});

test('a placa abre o comando cifrado pelo painel, com o desafio da vez', async () => {
  const {selo} = setup();
  selo.definirSenha('senha-de-bancada-bem-longa');
  selo.registrarAuth('esp32-01', AUTH);
  assert.equal(selo.empacotarAberto('esp32-01', COMANDO), null, 'com selo o envio nao e sincrono');
  const selado = await selo.empacotar('esp32-01', COMANDO);
  const pacote = JSON.parse(selado);
  assert.deepEqual(Object.keys(pacote).sort(), ['device_id', 'sealed', 'v']);
  assert.ok(!selado.includes('start'), 'o comando nao pode viajar legivel');
  assert.deepEqual(abrirComoAPlaca(selado, 'senha-de-bancada-bem-longa', 'esp32-01'),
    {...COMANDO, ch: AUTH.challenge});
});

test('cada envio usa um iv novo: dois comandos iguais saem diferentes', async () => {
  const {selo} = setup();
  selo.definirSenha('senha-de-bancada-bem-longa');
  selo.registrarAuth('esp32-01', AUTH);
  const um = await selo.empacotar('esp32-01', COMANDO);
  const outro = await selo.empacotar('esp32-01', COMANDO);
  assert.notEqual(um, outro);
});

test('senha diferente nao abre, e o selo de uma placa nao vale na outra', async () => {
  const {selo} = setup();
  selo.definirSenha('senha-certa');
  selo.registrarAuth('esp32-01', AUTH);
  const selado = await selo.empacotar('esp32-01', COMANDO);
  assert.throws(() => abrirComoAPlaca(selado, 'senha-errada', 'esp32-01'));
  // O identificador da placa entra como dado autenticado (AAD).
  assert.throws(() => abrirComoAPlaca(selado, 'senha-certa', 'esp32-02'));
});

test('um byte trocado no caminho derruba o selo', async () => {
  const {selo} = setup();
  selo.definirSenha('senha-certa');
  selo.registrarAuth('esp32-01', AUTH);
  const pacote = JSON.parse(await selo.empacotar('esp32-01', COMANDO));
  const bruto = Buffer.from(pacote.sealed, 'base64');
  bruto[20] = bruto[20] ^ 0x01;
  const mexido = JSON.stringify({...pacote, sealed: bruto.toString('base64')});
  assert.throws(() => abrirComoAPlaca(mexido, 'senha-certa', 'esp32-01'));
});

test('sem senha ou sem desafio o painel avisa em vez de publicar', async () => {
  const {selo} = setup();
  selo.registrarAuth('esp32-01', AUTH);
  assert.match(selo.impedimento('esp32-01'), /senha de comando/);
  await assert.rejects(() => selo.empacotar('esp32-01', COMANDO), /senha de comando/);
  selo.definirSenha('senha-certa');
  selo.registrarAuth('esp32-01', {device_id: 'esp32-01', secure: true, challenge: ''});
  assert.match(selo.impedimento('esp32-01'), /desafio/);
  await assert.rejects(() => selo.empacotar('esp32-01', COMANDO), /desafio/);
});

test('a senha fica neste navegador e some quando apagada', () => {
  const {selo, guardado} = setup();
  selo.definirSenha('senha-certa');
  assert.equal(guardado.get('iotmotor_cmd_senha'), 'senha-certa');
  assert.equal(selo.senhaAtual(), 'senha-certa');
  selo.definirSenha('');
  assert.equal(guardado.has('iotmotor_cmd_senha'), false);
  assert.equal(selo.temSenha(), false);
});

test('auth de outra placa e ignorado; esquecer derruba o desafio', () => {
  const {selo} = setup();
  selo.definirSenha('senha-certa');
  selo.registrarAuth('esp32-01', {device_id: 'esp32-02', secure: true, challenge: 'b'.repeat(32)});
  assert.equal(selo.exigeSelo('esp32-01'), false);
  selo.registrarAuth('esp32-01', AUTH);
  assert.equal(selo.exigeSelo('esp32-01'), true);
  selo.esquecer('esp32-01');
  assert.equal(selo.exigeSelo('esp32-01'), false);
});
