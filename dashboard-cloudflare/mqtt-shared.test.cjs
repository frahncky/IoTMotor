const test = require('node:test');
const assert = require('node:assert/strict');
const {installSharedMqtt, topicMatches} = require('./mqtt-shared.js');

function fakeMqtt() {
  const physical = {
    connected: false,
    handlers: new Map(),
    subscriptions: [],
    published: [],
    ended: 0,
    on(event, callback) { this.handlers.set(event, callback); return this; },
    emit(event, ...args) { this.handlers.get(event)?.(...args); },
    subscribe(topics, options, callback) {
      this.subscriptions.push(...(Array.isArray(topics) ? topics : [topics]));
      callback?.(null, []);
    },
    publish(...args) { this.published.push(args); },
    end() { this.ended++; }
  };
  let connections = 0;
  const target = {mqtt: {connect() { connections++; return physical; }}};
  return {target, physical, connections: () => connections};
}

test('cinco clientes virtuais usam uma unica conexao fisica', () => {
  const h = fakeMqtt();
  assert.equal(installSharedMqtt(h.target), true);
  const clients = Array.from({length: 5}, () => h.target.mqtt.connect('wss://publico/mqtt', {}));
  assert.equal(h.connections(), 1);
  clients.slice(0, 4).forEach(client => client.end(true));
  assert.equal(h.physical.ended, 0);
  clients[4].end(true);
  assert.equal(h.physical.ended, 1);
});

test('cada cliente recebe somente os topicos que assinou', () => {
  const h = fakeMqtt(); installSharedMqtt(h.target);
  const a = h.target.mqtt.connect('wss://publico/mqtt', {});
  const b = h.target.mqtt.connect('wss://publico/mqtt', {});
  let mensagensA = 0, mensagensB = 0;
  a.on('message', () => mensagensA++).subscribe('iotmotor/+/telemetry', {});
  b.on('message', () => mensagensB++).subscribe('iotmotor/esp32-02/alarms', {});
  h.physical.emit('message', 'iotmotor/esp32-01/telemetry', Buffer.from('{}'), {});
  assert.equal(mensagensA, 1); assert.equal(mensagensB, 0);
  assert.equal(topicMatches('iotmotor/#', 'iotmotor/esp32-02/alarms'), true);
});

test('funciona com o MQTT.js de verdade, que exporta connect so para leitura', () => {
  const vm = require('node:vm');
  const fs = require('node:fs');
  const path = require('node:path');
  const contexto = {console, setTimeout, clearTimeout, setInterval, clearInterval, TextEncoder,
    TextDecoder, URL, queueMicrotask, AbortController, AbortSignal, EventTarget, Event,
    navigator: {userAgent: 'node'}};
  contexto.globalThis = contexto;
  contexto.window = contexto;
  contexto.self = contexto;
  vm.createContext(contexto);
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'vendor/mqtt-5.10.4.min.js'), 'utf8'), contexto);
  const original = contexto.mqtt;
  assert.equal(typeof original.connect, 'function');
  // Era este o erro da pagina: o connect da biblioteca nao aceita troca.
  assert.throws(() => { 'use strict'; original.connect = () => {}; }, TypeError);
  const alvo = {mqtt: original};
  assert.equal(installSharedMqtt(alvo), true);
  assert.notEqual(alvo.mqtt, original);
  assert.equal(alvo.mqtt.__iotmotorShared, true);
  assert.equal(alvo.mqtt.Client, original.Client, 'o resto da biblioteca continua igual');
  assert.equal(installSharedMqtt(alvo), false, 'instalar de novo nao embrulha outra vez');
});

test('connect so leitura, como no MQTT.js: uma conexao fisica para varios clientes', () => {
  let conexoes = 0;
  const fisico = {connected: false, on() { return this; }, subscribe() {}, publish() {}, end() {}};
  const biblioteca = {};
  Object.defineProperty(biblioteca, 'connect', {get: () => () => { conexoes++; return fisico; }, enumerable: true});
  const alvo = {mqtt: biblioteca};
  assert.equal(installSharedMqtt(alvo), true);
  alvo.mqtt.connect('wss://x/mqtt', {});
  alvo.mqtt.connect('wss://x/mqtt', {});
  assert.equal(conexoes, 1);
});
