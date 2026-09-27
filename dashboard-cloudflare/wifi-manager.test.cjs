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
    confirm: () => true,
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

test('reiniciar vale para as duas placas e envia o comando restart para a selecionada', () => {
  const h = abaWifi();
  h.redes('esp32-01'); h.redes('esp32-02');
  h.enviar('iotmotor/esp32-01/status', 'online');
  h.enviar('iotmotor/esp32-02/status', 'online');
  for (const [indice, placa] of [[0, 'esp32-01'], [1, 'esp32-02']]) {
    h.no('wifiDev' + indice).fire('click');
    assert.equal(h.no('wifiRestart').disabled, false, placa);
    h.no('wifiRestart').fire('click');
    const envio = h.cliente.publicados.at(-1);
    assert.equal(envio.topico, `iotmotor/${placa}/command`);
    const comando = JSON.parse(envio.dados);
    assert.equal(comando.action, 'restart');
    assert.equal(comando.device_id, placa);
    // Aguardando a resposta, o botão fica travado.
    assert.equal(h.no('wifiRestart').disabled, true);
    h.enviar(`iotmotor/${placa}/command_ack`, JSON.stringify({device_id: placa, seq: comando.seq,
      action: 'restart', accepted: true, reason: 'reiniciando'}));
  }
  // Placa fora do ar: nada a reiniciar.
  h.enviar('iotmotor/esp32-02/status', 'offline');
  assert.equal(h.no('wifiRestart').disabled, true);
});

test('versão do firmware: em dia, desatualizada ou não informada', () => {
  const {FIRMWARE_PUBLICADO, situacaoFirmware} = require('./wifi-manager.js');
  const h = abaWifi();
  h.redes('esp32-01'); h.redes('esp32-02');
  assert.match(h.no('wifiFirmware').textContent, /aguardando/);
  h.enviar('iotmotor/esp32-01/capabilities', JSON.stringify({device_id: 'esp32-01', firmware_version: FIRMWARE_PUBLICADO[0]}));
  h.enviar('iotmotor/esp32-02/capabilities', JSON.stringify({device_id: 'esp32-02', firmware_version: 's3-velho'}));
  assert.match(h.no('wifiFirmware').textContent, /em dia/);
  assert.equal(h.no('wifiDev0').dataset.update, 'false');
  assert.equal(h.no('wifiDev1').dataset.update, 'true');
  assert.equal(h.no('tabBtn-wifi').dataset.update, 'true', 'a aba Wi-Fi mostra que há atualização');
  h.no('wifiDev1').fire('click');
  assert.match(h.no('wifiFirmware').textContent, new RegExp(`s3-velho · nova versão publicada: ${FIRMWARE_PUBLICADO[1]}`));
  assert.equal(h.no('wifiUpdateFw').className, 'btn', 'o botão de atualizar fica em destaque');
  assert.equal(situacaoFirmware('', 'x').atualizar, true);
});

test('atualização só termina quando a placa volta com a versão nova e falha tardia não é ignorada', () => {
  const {FIRMWARE_PUBLICADO} = require('./wifi-manager.js');
  const h = abaWifi();
  h.redes('esp32-01');
  h.enviar('iotmotor/esp32-01/status', 'online');
  h.enviar('iotmotor/esp32-01/capabilities', JSON.stringify({
    device_id: 'esp32-01', firmware_version: 'v13-antigo'
  }));

  h.no('wifiUpdateFw').fire('click');
  const envio = h.cliente.publicados.at(-1);
  const comando = JSON.parse(envio.dados);
  assert.equal(comando.action, 'update');

  h.enviar('iotmotor/esp32-01/command_ack', JSON.stringify({
    device_id: 'esp32-01', seq: comando.seq, action: 'update',
    accepted: true, reason: 'baixando firmware'
  }));
  assert.match(h.no('wifiFeedback').textContent, /Aguardando reinício|download confirmado/);
  assert.equal(h.no('wifiUpdateFw').disabled, true);

  h.enviar('iotmotor/esp32-01/command_ack', JSON.stringify({
    device_id: 'esp32-01', seq: comando.seq, action: 'update',
    accepted: false, reason: 'falha -1: erro de download'
  }));
  assert.match(h.no('wifiFeedback').textContent, /falha -1/i);

  h.no('wifiUpdateFw').fire('click');
  const comando2 = JSON.parse(h.cliente.publicados.at(-1).dados);
  h.enviar('iotmotor/esp32-01/command_ack', JSON.stringify({
    device_id: 'esp32-01', seq: comando2.seq, action: 'update',
    accepted: true, reason: 'baixando firmware'
  }));
  assert.match(h.no('wifiFirmware').textContent, /Atualizando firmware/);
  h.enviar('iotmotor/esp32-01/status', 'offline');
  assert.match(h.no('wifiStatus').textContent, /Atualizando firmware.*reiniciando e reconectando/);
  assert.doesNotMatch(h.no('wifiStatus').textContent, /desligada ou fora da rede/);
  h.enviar('iotmotor/esp32-01/status', 'online');
  assert.match(h.no('wifiStatus').textContent, /confirmando a nova versão/);
  h.enviar('iotmotor/esp32-01/capabilities', JSON.stringify({
    device_id: 'esp32-01', firmware_version: FIRMWARE_PUBLICADO[0]
  }));
  assert.match(h.no('wifiFeedback').textContent, /Atualização .*concluída/);
  assert.match(h.no('wifiFirmware').textContent, /Atualizado · Conectado/);
  assert.match(h.no('wifiStatus').textContent, /Atualizado · Conectado/);
});

test('OTA de uma placa não bloqueia o envio de atualização para a outra', () => {
  const h = abaWifi();
  h.redes('esp32-01'); h.redes('esp32-02');
  h.enviar('iotmotor/esp32-01/status', 'online');
  h.enviar('iotmotor/esp32-02/status', 'online');
  h.enviar('iotmotor/esp32-01/capabilities', JSON.stringify({
    device_id: 'esp32-01', firmware_version: 'v13-antigo'
  }));
  h.enviar('iotmotor/esp32-02/capabilities', JSON.stringify({
    device_id: 'esp32-02', firmware_version: 's3-antigo'
  }));

  h.no('wifiDev0').fire('click');
  h.no('wifiUpdateFw').fire('click');
  const cmd1 = JSON.parse(h.cliente.publicados.at(-1).dados);
  h.enviar('iotmotor/esp32-01/command_ack', JSON.stringify({
    device_id: 'esp32-01', seq: cmd1.seq, action: 'update',
    accepted: true, reason: 'baixando firmware'
  }));
  assert.equal(h.no('wifiUpdateFw').disabled, true, 'a placa 1 fica ocupada');

  h.no('wifiDev1').fire('click');
  assert.equal(h.no('wifiUpdateFw').disabled, false, 'a placa 2 continua disponível');
  h.no('wifiUpdateFw').fire('click');
  const envio2 = h.cliente.publicados.at(-1);
  const cmd2 = JSON.parse(envio2.dados);
  assert.equal(envio2.topico, 'iotmotor/esp32-02/command');
  assert.equal(cmd2.action, 'update');
  assert.equal(cmd2.device_id, 'esp32-02');
});
