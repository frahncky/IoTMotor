const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');

const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');

function makeBrowser(savedConfig = null) {
  const nodes = new Map();
  const connections = [];
  const writes = [];
  const node = (id = '') => ({
    id, value: '', textContent: '', className: '', disabled: false, children: [], listeners: {},
    setAttribute() {}, append(...items) { this.children.push(...items); },
    replaceChildren(...items) { this.children = [...items]; },
    addEventListener(event, fn) { this.listeners[event] = fn; },
    click() { if (this.listeners.click) this.listeners.click(); }
  });
  const document = {
    getElementById(id) { if (!nodes.has(id)) nodes.set(id, node(id)); return nodes.get(id); },
    createElementNS(_namespace, tag) { return node(tag); },
    createElement(tag) { return node(tag); }
  };
  const browser = {
    document, localStorage: {
      getItem() { return savedConfig === null ? null : JSON.stringify(savedConfig); },
      setItem(key, value) { writes.push({ key, value: JSON.parse(value) }); }
    },
    URL, Date, Math, JSON, Number, String, setInterval() {}, setTimeout() {},
    window: {
      mqtt: {
        connect(url, options) {
          const client = new EventEmitter();
          client.url = url;
          client.options = options;
          client.subscribe = (topics, _options, cb) => { client.topics = topics; cb(null); };
          client.end = () => { client.ended = true; };
          connections.push(client);
          return client;
        }
      }
    }
  };
  vm.runInNewContext(source, browser, { filename: 'app.js' });
  return { get: document.getElementById, connections, writes };
}

test('Usa Mosquitto WSS por padrao e assina somente esp32-01', () => {
  const app = makeBrowser();
  assert.equal(app.get('broker').value, 'wss://test.mosquitto.org:8081');
  app.get('connectBtn').click();
  assert.equal(app.connections.length, 1);
  const client = app.connections[0];
  assert.equal(client.url, 'wss://test.mosquitto.org:8081/');
  client.emit('connect');
  assert.deepEqual(Array.from(client.topics), [
    'iotmotor/esp32-01/telemetry', 'iotmotor/esp32-01/status'
  ]);
  assert.equal(app.get('connectionText').textContent, 'Broker conectado');
});

test('Migra apenas o padrao HiveMQ antigo, sem apagar broker personalizado', () => {
  const previous = { broker: 'wss://broker.hivemq.com:8884/mqtt', prefix: 'iotmotor', device: 'esp32-01' };
  const migrated = makeBrowser(previous);
  assert.equal(migrated.get('broker').value, 'wss://test.mosquitto.org:8081');
  assert.equal(migrated.writes.length, 1);
  assert.equal(migrated.writes[0].value.broker, 'wss://test.mosquitto.org:8081');
  const custom = makeBrowser({ broker: 'wss://broker.exemplo.org/mqtt', prefix: 'planta1', device: 'esp32-08' });
  assert.equal(custom.get('broker').value, 'wss://broker.exemplo.org/mqtt');
  assert.equal(custom.get('prefix').value, 'planta1');
  assert.equal(custom.writes.length, 0);
});

test('Exibe telemetria recebida e exportacao CSV sem publicar comandos', () => {
  const app = makeBrowser();
  app.get('connectBtn').click();
  const client = app.connections[0];
  client.emit('connect');
  client.emit('message', 'iotmotor/esp32-01/telemetry', Buffer.from(JSON.stringify({
    device_id: 'esp32-01', voltage: 221.47, current: 3.8, motor_on: true
  })));
  assert.equal(app.get('voltage').textContent, '221.5');
  assert.equal(app.get('current').textContent, '3.80');
  assert.equal(app.get('motor').textContent, 'Ligado');
  assert.equal(app.get('messages').textContent, '1');
  assert.equal(app.get('csvBtn').disabled, false);
  assert.equal(typeof client.publish, 'undefined', 'o painel nao deve publicar comandos');
  client.emit('message', 'iotmotor/esp32-02/telemetry', Buffer.from('{"voltage":999}'));
  assert.equal(app.get('voltage').textContent, '221.5');
});

test('Rejeita WS inseguro e conserva a interface desconectada', () => {
  const app = makeBrowser();
  app.get('broker').value = 'ws://test.mosquitto.org:8080';
  app.get('connectBtn').click();
  assert.equal(app.connections.length, 0);
  assert.match(app.get('diagnostic').textContent, /wss:\/\//);
});

test('Nao confunde mensagem de status retida com telemetria atual', () => {
  const app = makeBrowser();
  app.get('connectBtn').click();
  const client = app.connections[0];
  client.emit('connect');
  client.emit('message', 'iotmotor/esp32-01/status', Buffer.from('online'));
  assert.equal(app.get('statusValue').textContent, 'online');
  assert.equal(app.get('freshness').textContent, 'Não');
  assert.match(app.get('diagnostic').textContent, /Status retido/);
});
