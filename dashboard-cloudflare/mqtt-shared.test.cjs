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
