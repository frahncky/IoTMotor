const test = require('node:test');
const assert = require('node:assert/strict');
const {webcrypto: cripto} = require('node:crypto');
const {cifrarSenha, ROTULO_KDF} = require('./wifi-manager.js');

// Faz o papel da placa: mesmo esquema de wifi_store.h (ECDH P-256,
// SHA-256(rotulo || segredo), AES-GCM com o SSID como dado autenticado).
async function decifrarComoAPlaca(chavePrivada, ssid, {epk, iv, ct}) {
  const sutil = cripto.subtle;
  const b64 = t => Uint8Array.from(Buffer.from(t, 'base64'));
  const efemera = await sutil.importKey('raw', b64(epk), {name: 'ECDH', namedCurve: 'P-256'}, false, []);
  const segredo = new Uint8Array(await sutil.deriveBits({name: 'ECDH', public: efemera}, chavePrivada, 256));
  const material = Buffer.concat([Buffer.from(ROTULO_KDF), Buffer.from(segredo)]);
  const chave = await sutil.importKey('raw', await sutil.digest('SHA-256', material), 'AES-GCM', false, ['decrypt']);
  const claro = await sutil.decrypt({name: 'AES-GCM', iv: b64(iv), additionalData: Buffer.from(ssid)}, chave, b64(ct));
  return Buffer.from(claro).toString('utf8');
}

async function parDaPlaca() {
  const par = await cripto.subtle.generateKey({name: 'ECDH', namedCurve: 'P-256'}, true, ['deriveBits']);
  const publica = Buffer.from(await cripto.subtle.exportKey('raw', par.publicKey)).toString('base64');
  return {privada: par.privateKey, publica};
}

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {EventEmitter} = require('node:events');

// Sobe a aba Wi-Fi com um DOM de mentira, so para conferir o que ela escreve.
function abaWifi() {
  const nos = new Map();
  const criar = () => ({
    value: '', checked: false, disabled: false, textContent: '', className: '', title: '',
    hidden: false, tabIndex: 0, dataset: {}, handlers: {}, children: [], atributos: {},
    addEventListener(nome, fn) { this.handlers[nome] = fn; },
    fire(nome) { this.handlers[nome]?.({preventDefault() {}}); },
    replaceChildren() { this.children = []; },
    append(...filhos) { this.children.push(...filhos); },
    setAttribute(nome, valor) { this.atributos[nome] = valor; },
    focus() {}
  });
  const no = id => { if (!nos.has(id)) nos.set(id, criar()); return nos.get(id); };
  no('broker').value = 'wss://test.mosquitto.org:8081';
  no('prefix').value = 'iotmotor';
  no('commandDevice').value = 'esp32-01';
  no('sensorDevice').value = 'esp32-02';
  const clientes = [];
  const contexto = vm.createContext({
    document: {getElementById: no, createElement: criar, querySelectorAll: () => []},
    window: {mqtt: {connect() {
      const c = new EventEmitter();
      c.connected = true;
      c.publicados = [];
      c.subscribe = (topicos, opcoes, cb) => cb?.(null, []);
      c.publish = (topico, dados) => c.publicados.push({topico, dados});
      c.end = () => {};
      clientes.push(c);
      return c;
    }}},
    URL, Date, Math, JSON, Number, Set, Map, Array, String, Boolean, Object,
    setTimeout() { return 0; }, clearTimeout() {}, setInterval() { return 0; },
    localStorage: {getItem: () => null, setItem() {}, removeItem() {}},
    crypto: globalThis.crypto, TextEncoder, Uint8Array, btoa: () => ''
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'wifi-manager.js'), 'utf8'), contexto);
  contexto.window.iotmotorWifi.connect();
  const cliente = clientes.at(-1);
  cliente.emit('connect');
  const enviar = (topico, texto) => cliente.emit('message', topico, Buffer.from(texto), {retain: true});
  const redes = placa => enviar(`iotmotor/${placa}/wifi`, JSON.stringify({
    device_id: placa, connected: 'IFMA_IOT', max: 8,
    networks: [{ssid: 'IFMA_IOT', open: true}]
  }));
  return {no, cliente, enviar, redes};
}

test('placa offline nao aparece como conectada: a lista retida fica no broker', () => {
  const h = abaWifi();
  h.redes('esp32-01');
  // So com a lista retida, a aba dizia "conectada em IFMA_IOT" de uma placa
  // desligada: o status e quem conta se ela esta no ar agora.
  h.enviar('iotmotor/esp32-01/status', 'offline');
  assert.match(h.no('wifiStatus').textContent, /desligada ou fora da rede agora/);
  assert.match(h.no('wifiStatus').textContent, /última informação recebida/);
  assert.equal(h.no('wifiUpdateFw').disabled, true, 'sem placa no ar, nao ha o que comandar');
  assert.equal(h.no('wifiAddBtn').disabled, true);
  assert.equal(h.no('wifiList').children[0].className, '', 'nao marca a rede como a atual');

  h.enviar('iotmotor/esp32-01/status', 'online');
  assert.match(h.no('wifiStatus').textContent, /conectada em "IFMA_IOT"/);
  assert.equal(h.no('wifiUpdateFw').disabled, false);
  assert.equal(h.no('wifiList').children[0].className, 'atual');
});

test('a placa recupera a senha cifrada pelo painel', async () => {
  const placa = await parDaPlaca();
  const pacote = await cifrarSenha(placa.publica, 'Francisco S20 fe', 'senha secreta çã', cripto);
  assert.equal(Buffer.from(pacote.epk, 'base64').length, 65, 'chave efemera P-256 nao comprimida');
  assert.equal(Buffer.from(pacote.iv, 'base64').length, 12);
  assert.equal(await decifrarComoAPlaca(placa.privada, 'Francisco S20 fe', pacote), 'senha secreta çã');
});

test('o texto cifrado nao contem a senha e muda a cada envio', async () => {
  const placa = await parDaPlaca();
  const a = await cifrarSenha(placa.publica, 'Casa', 'minhasenha123', cripto);
  const b = await cifrarSenha(placa.publica, 'Casa', 'minhasenha123', cripto);
  assert.ok(!JSON.stringify(a).includes('minhasenha123'));
  assert.notEqual(a.ct, b.ct);
});

test('trocar o SSID invalida o pacote (SSID e dado autenticado)', async () => {
  const placa = await parDaPlaca();
  const pacote = await cifrarSenha(placa.publica, 'Casa', 'minhasenha123', cripto);
  await assert.rejects(decifrarComoAPlaca(placa.privada, 'Outra rede', pacote));
});

test('outra placa nao consegue decifrar', async () => {
  const placa = await parDaPlaca();
  const intrusa = await parDaPlaca();
  const pacote = await cifrarSenha(placa.publica, 'Casa', 'minhasenha123', cripto);
  await assert.rejects(decifrarComoAPlaca(intrusa.privada, 'Casa', pacote));
});
