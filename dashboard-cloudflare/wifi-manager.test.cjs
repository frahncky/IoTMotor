const test = require('node:test');
const assert = require('node:assert/strict');
const {webcrypto: cripto} = require('node:crypto');
const {cifrarSenha, ROTULO_KDF, avaliarSaudePlaca} = require('./wifi-manager.js');

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
function abaWifi(opcoes = {}) {
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
    crypto: globalThis.crypto, TextEncoder, Uint8Array, btoa: () => '',
    ...(opcoes.fetch ? {fetch: opcoes.fetch} : {})
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'wifi-manager.js'), 'utf8'), contexto);
  contexto.window.iotmotorWifi.connect();
  const cliente = clientes.at(-1);
  cliente.emit('connect');
  const enviar = (topico, texto) => cliente.emit('message', topico, Buffer.from(texto), {retain: true});
  const redes = (placa, diagnostics) => enviar(`iotmotor/${placa}/wifi`, JSON.stringify({
    device_id: placa, connected: 'IFMA_IOT', max: 8, diagnostics,
    networks: [{ssid: 'IFMA_IOT', open: true}]
  }));
  return {
    no, cliente, enviar, redes,
    firmwareStatus: dev => contexto.window.iotmotorFirmwareStatus?.(dev) || null
  };
}

test('saúde automática diferencia normal, aviso, crítico e offline', () => {
  const base = {
    rssi: -60, heap_bytes: 180000, min_heap_bytes: 140000,
    reset_reason: 1, reconnections: 0, uptime_ms: 3600000
  };
  assert.deepEqual(avaliarSaudePlaca(base), {kind: 'ok', texto: 'Saúde: normal.'});
  assert.equal(avaliarSaudePlaca({...base, rssi: -73}).kind, 'warn');
  const critica = avaliarSaudePlaca({...base, reset_reason: 9});
  assert.equal(critica.kind, 'error');
  assert.match(critica.texto, /brownout/);
  assert.equal(avaliarSaudePlaca(base, false).kind, 'offline');
});

test('diagnóstico mostra sinal, duração, última rede, reconexões e causa da queda', () => {
  const h = abaWifi();
  h.redes('esp32-01', {
    rssi: -61, connected_ms: 125000, last_network: 'IFMA_IOT',
    reconnections: 3, disconnect_reason: 202, uptime_ms: 3605000,
    heap_bytes: 180224, min_heap_bytes: 143360, reset_reason: 9
  });
  h.enviar('iotmotor/esp32-01/status', 'online');
  assert.match(h.no('wifiRssi').textContent, /-61 dBm.*bom/);
  assert.match(h.no('wifiConnectedTime').textContent, /2 min/);
  assert.equal(h.no('wifiLastNetwork').textContent, 'IFMA_IOT');
  assert.equal(h.no('wifiReconnects').textContent, '3');
  assert.match(h.no('wifiDisconnectReason').textContent, /falha de autenticação.*202/);
  assert.match(h.no('boardUptime').textContent, /1 h/);
  assert.equal(h.no('boardHeap').textContent, '176 / 140 KB');
  assert.match(h.no('boardResetReason').textContent, /queda de tensão.*brownout/);
  assert.equal(h.no('boardHealth').className, 'board-health error');
  assert.match(h.no('boardHealth').textContent, /atenção crítica.*brownout/);
});

test('placa offline nao aparece como conectada: a lista retida fica no broker', () => {
  const h = abaWifi();
  h.redes('esp32-01');
  // So com a lista retida, a aba dizia "conectada em IFMA_IOT" de uma placa
  // desligada: o status e quem conta se ela esta no ar agora.
  h.enviar('iotmotor/esp32-01/status', 'offline');
  assert.match(h.no('wifiStatus').textContent, /desligada ou fora da rede agora/);
  assert.match(h.no('wifiStatus').textContent, /última informação recebida/);
  assert.equal(h.no('wifiUpdateFw').disabled, false, 'o botão OTA continua clicável offline');
  h.no('wifiUpdateFw').fire('click');
  assert.match(h.no('wifiActionFeedback').textContent, /está offline/i);
  assert.equal(h.no('wifiFeedback').textContent, '', 'aviso de firmware não vai para o campo geral');
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
    // Aguardando a resposta e o retorno da placa, o botão fica travado.
    assert.equal(h.no('wifiRestart').disabled, true);
    h.enviar(`iotmotor/${placa}/command_ack`, JSON.stringify({device_id: placa, seq: comando.seq,
      action: 'restart', accepted: true, reason: 'reiniciando'}));
    assert.match(h.no('wifiActionFeedback').textContent, /Aguardando reconexão/i);
    assert.equal(h.no('wifiFeedback').textContent, '', 'reinício não usa o campo geral');
    h.enviar(`iotmotor/${placa}/status`, 'offline');
    assert.match(h.no('wifiActionFeedback').textContent, /reiniciando.*aguardando reconexão/i);
    h.enviar(`iotmotor/${placa}/status`, 'online');
    assert.match(h.no('wifiActionFeedback').textContent, /reiniciada e conectada/i);
    assert.doesNotMatch(h.no('wifiActionFeedback').textContent, /A placa está online\?/i);
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
  assert.equal(h.no('wifiUpdateFw').disabled, false, 'firmware atual mantém botão clicável');
  h.no('wifiUpdateFw').fire('click');
  assert.match(h.no('wifiActionFeedback').textContent, /já está atualizado/i, 'o aviso fica visível junto ao botão OTA');
  assert.equal(h.no('wifiFeedback').textContent, '', 'firmware em dia não duplica mensagem no campo geral');
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
  assert.match(h.no('wifiActionFeedback').textContent, /Aguardando reinício|download confirmado/);
  assert.equal(h.no('wifiUpdateFw').disabled, false, 'OTA em andamento mantém o botão clicável');
  h.no('wifiUpdateFw').fire('click');
  assert.match(h.no('wifiActionFeedback').textContent, /já está em andamento/i);

  h.enviar('iotmotor/esp32-01/command_ack', JSON.stringify({
    device_id: 'esp32-01', seq: comando.seq, action: 'update',
    accepted: false, reason: 'falha -1: erro de download'
  }));
  assert.match(h.no('wifiActionFeedback').textContent, /falha -1/i);

  h.no('wifiUpdateFw').fire('click');
  const comando2 = JSON.parse(h.cliente.publicados.at(-1).dados);
  h.enviar('iotmotor/esp32-01/command_ack', JSON.stringify({
    device_id: 'esp32-01', seq: comando2.seq, action: 'update',
    accepted: true, reason: 'baixando firmware'
  }));
  assert.match(h.no('wifiFirmware').textContent, /Atualizando firmware/);
  assert.equal(h.firmwareStatus('esp32-01')?.state, 'updating');
  h.enviar('iotmotor/esp32-01/status', 'offline');
  assert.match(h.no('wifiStatus').textContent, /Atualizando firmware.*reiniciando e reconectando/);
  assert.doesNotMatch(h.no('wifiStatus').textContent, /desligada ou fora da rede/);
  h.enviar('iotmotor/esp32-01/status', 'online');
  assert.match(h.no('wifiStatus').textContent, /confirmando a nova versão/);
  h.enviar('iotmotor/esp32-01/capabilities', JSON.stringify({
    device_id: 'esp32-01', firmware_version: FIRMWARE_PUBLICADO[0]
  }));
  assert.match(h.no('wifiActionFeedback').textContent, /Atualização .*concluída/);
  assert.match(h.no('wifiFirmware').textContent, /Atualizado · Conectado/);
  assert.match(h.no('wifiStatus').textContent, /Atualizado · Conectado/);
  assert.equal(h.firmwareStatus('esp32-01')?.state, 'updated');
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
  assert.equal(h.no('wifiUpdateFw').disabled, false, 'a placa 1 continua com botão clicável');
  h.no('wifiUpdateFw').fire('click');
  assert.match(h.no('wifiActionFeedback').textContent, /já está em andamento/i);

  h.no('wifiDev1').fire('click');
  assert.equal(h.no('wifiUpdateFw').disabled, false, 'a placa 2 continua disponível');
  h.no('wifiUpdateFw').fire('click');
  const envio2 = h.cliente.publicados.at(-1);
  const cmd2 = JSON.parse(envio2.dados);
  assert.equal(envio2.topico, 'iotmotor/esp32-02/command');
  assert.equal(cmd2.action, 'update');
  assert.equal(cmd2.device_id, 'esp32-02');
});

test('OTA que volta com a versão antiga avisa que a placa retornou sozinha', () => {
  const h = abaWifi();
  h.redes('esp32-01');
  h.enviar('iotmotor/esp32-01/status', 'online');
  h.enviar('iotmotor/esp32-01/capabilities', JSON.stringify({
    device_id: 'esp32-01', firmware_version: 'v13-antigo'
  }));
  h.no('wifiUpdateFw').fire('click');
  const comando = JSON.parse(h.cliente.publicados.at(-1).dados);
  h.enviar('iotmotor/esp32-01/command_ack', JSON.stringify({
    device_id: 'esp32-01', seq: comando.seq, action: 'update',
    accepted: true, reason: 'baixando firmware'
  }));
  h.enviar('iotmotor/esp32-01/status', 'offline');
  h.enviar('iotmotor/esp32-01/status', 'online');
  h.enviar('iotmotor/esp32-01/capabilities', JSON.stringify({
    device_id: 'esp32-01', firmware_version: 'v13-antigo'
  }));
  assert.match(h.no('wifiActionFeedback').textContent, /voltou para v13-antigo.*voltou sozinha/);
  assert.equal(h.firmwareStatus('esp32-01'), null, 'não fica preso em "atualizando"');
});

test('versão publicada vem do firmware-latest.json; sem ele, vale a reserva', async () => {
  const {lerFirmwarePublicado} = require('./wifi-manager.js');
  assert.deepEqual(lerFirmwarePublicado({'esp32-01': 'v30-x', 'esp32-02': 's3-sensors-2.0'}), ['v30-x', 's3-sensors-2.0']);
  assert.equal(lerFirmwarePublicado({'esp32-01': 'v30-x'}), null);
  assert.equal(lerFirmwarePublicado({'esp32-01': '<script>', 'esp32-02': 'ok'}), null);
  assert.equal(lerFirmwarePublicado(null), null);

  // A placa com a versão do JSON fica "em dia", mesmo com a reserva velha.
  const pedidos = [];
  const h = abaWifi({fetch: async url => {
    pedidos.push(url);
    return {ok: true, json: async () => ({v: 1, 'esp32-01': 'v99-novo', 'esp32-02': 's3-sensors-9.9'})};
  }});
  await new Promise(r => setImmediate(r));
  assert.deepEqual(pedidos, ['/firmware/firmware-latest.json']);
  h.redes('esp32-01');
  h.enviar('iotmotor/esp32-01/capabilities', JSON.stringify({device_id: 'esp32-01', firmware_version: 'v99-novo'}));
  assert.match(h.no('wifiFirmware').textContent, /v99-novo · em dia/);
  h.enviar('iotmotor/esp32-01/capabilities', JSON.stringify({device_id: 'esp32-01', firmware_version: 'v27-mqtt-cloudflare'}));
  assert.match(h.no('wifiFirmware').textContent, /nova versão publicada: v99-novo/);
});
