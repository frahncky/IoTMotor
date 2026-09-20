const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {EventEmitter} = require('node:events');

function setup() {
  let now = 100000;
  const timers = new Map(), intervals = [];
  let timerId = 0;
  const nodes = new Map();
  function node(id) {
    if (!nodes.has(id)) nodes.set(id, {
      value: '', checked: true, disabled: false, textContent: '', className: '', handlers: {},
      addEventListener(name, fn) { this.handlers[name] = fn; },
      fire(name) { this.handlers[name]?.({preventDefault() {}}); },
      replaceChildren() {}, append() {}, setAttribute() {}
    });
    return nodes.get(id);
  }
  node('broker').value = 'wss://test.mosquitto.org:8081';
  node('prefix').value = 'iotmotor';
  node('sensorDevice').value = 'esp32-02';
  const clients = [];
  const context = vm.createContext({
    document: {getElementById: node, createElement: () => node(Symbol()), querySelectorAll: () => []},
    window: {mqtt: {connect() {
      const c = new EventEmitter();
      c.connected = false; c.published = [];
      c.subscribe = (topics, options, callback) => { c.topics = topics; callback?.(null, topics.map(topic => ({topic, qos: 1}))); };
      c.publish = (topic, payload, options, callback) => {
        c.published.push({topic, data: JSON.parse(payload), options}); callback?.(c.publishError);
      };
      c.end = () => { c.connected = false; c.emit('close'); };
      clients.push(c);
      return c;
    }}},
    URL, Date: {now: () => now}, Math, JSON,
    setTimeout(fn) { const id = ++timerId; timers.set(id, fn); return id; },
    clearTimeout(id) { timers.delete(id); },
    setInterval(fn) { intervals.push(fn); },
    localStorage: {getItem: () => null, setItem() {}}
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'alarm-controls.js'), 'utf8'), context);
  function connect() {
    context.window.iotmotorAlarme.connect();
    const client = clients.at(-1);
    client.connected = true; client.emit('connect');
    return client;
  }
  const send = (client, kind, extra = {}, retain = false) => client.emit('message',
    `${node('prefix').value}/${node('sensorDevice').value}/${kind}`,
    Buffer.from(JSON.stringify({device_id: node('sensorDevice').value, ...extra})), {retain});
  const telemetry = (client, extra = {}, retain = false) => send(client, 'telemetry', {
    alarm_enabled: true, alarm_active: false, vibration_limit: 0.5, temperature_limit: 60,
    mpu_ok: true, temperature_ok: true, ...extra
  }, retain);
  return {node, clients, context, connect, send, telemetry, timers,
    advance(ms) { now += ms; intervals.forEach(fn => fn()); }};
}

test('espera telemetria atual do firmware de alarme; dados retidos ou de outro S3 nao habilitam comandos', () => {
  const h = setup(), c = h.connect();
  assert.equal(h.node('alarmeSalvar').disabled, true);
  h.telemetry(c, {}, true);
  h.telemetry(c, {device_id: 'outro'});
  h.telemetry(c, {alarm_enabled: undefined});
  assert.equal(h.node('alarmeSalvar').disabled, true);
  h.telemetry(c);
  assert.equal(h.node('alarmeVib').value, 0.5);
  assert.equal(h.node('alarmeSalvar').disabled, false);
  h.advance(10000);
  assert.equal(h.node('alarmeSalvar').disabled, true);
  assert.match(h.node('alarmeEstado').textContent, /sem dados recentes/);
});

test('preserva limites e checkbox editados entre telemetrias e confirma somente o ACK correto', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c);
  h.node('alarmeVib').value = '0.8'; h.node('alarmeVib').fire('input');
  h.node('alarmeTemp').value = '70'; h.node('alarmeTemp').fire('input');
  h.node('alarmeOn').checked = false; h.node('alarmeOn').fire('change');
  h.telemetry(c);
  assert.equal(h.node('alarmeVib').value, '0.8');
  assert.equal(h.node('alarmeOn').checked, false);
  h.node('alarmeForm').fire('submit');
  const cmd = c.published[0];
  assert.equal(cmd.topic, 'iotmotor/esp32-02/command');
  assert.equal(cmd.options.retain, false);
  assert.deepEqual(cmd.data, {v: 1, device_id: 'esp32-02', seq: cmd.data.seq,
    action: 'alarm_set', enabled: false, vibration_limit: 0.8, temperature_limit: 70});
  h.node('alarmeForm').fire('submit');
  assert.equal(c.published.length, 1);
  h.send(c, 'command_ack', {...cmd.data, action: 'alarm_test', accepted: true});
  assert.equal(h.node('alarmeSalvar').disabled, true);
  h.send(c, 'command_ack', {...cmd.data, accepted: 'false'});
  assert.equal(h.node('alarmeSalvar').disabled, true);
  h.send(c, 'command_ack', {...cmd.data, accepted: true}, true);
  assert.equal(h.node('alarmeSalvar').disabled, true);
  h.send(c, 'command_ack', {...cmd.data, accepted: true});
  assert.equal(h.node('alarmeSalvar').disabled, false);
  assert.equal(h.node('alarmeVib').value, 0.8);
  assert.equal(h.timers.size, 0);
});

test('rejeicao, erro de publicacao e timeout liberam o formulario sem perder o rascunho', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c);
  h.node('alarmeVib').value = '0.9'; h.node('alarmeVib').fire('input');
  h.node('alarmeForm').fire('submit');
  h.send(c, 'command_ack', {...c.published[0].data, accepted: false, reason: 'falha ao gravar'});
  assert.match(h.node('alarmeFeedback').textContent, /recusou/);
  assert.equal(h.node('alarmeVib').value, '0.9');
  c.publishError = Error('sem rede');
  h.node('alarmeForm').fire('submit');
  assert.match(h.node('alarmeFeedback').textContent, /Falha ao enviar/);
  assert.equal(h.node('alarmeSalvar').disabled, false);
  c.publishError = null;
  h.node('alarmeTeste').fire('click');
  for (const fn of [...h.timers.values()]) fn();
  assert.match(h.node('alarmeFeedback').textContent, /Sem resposta/);
  assert.equal(h.node('alarmeSalvar').disabled, false);
});

test('mostra sensores ausentes, alarme ativo e alarme desligado', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c, {mpu_ok: false, temperature_ok: false});
  assert.equal(h.node('alarmeEstado').textContent, 'sem sensores válidos');
  h.telemetry(c, {alarm_active: true});
  assert.match(h.node('alarmeEstado').textContent, /ALARME/);
  h.telemetry(c, {alarm_enabled: false});
  assert.equal(h.node('alarmeEstado').textContent, 'alarme desligado');
});

test('reconexao exige novos dados e ignora mensagens da conexao encerrada', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c);
  h.node('alarmeTeste').fire('click');
  const next = h.connect();
  assert.equal(c.connected, false);
  assert.equal(h.timers.size, 0);
  h.telemetry(c);
  assert.equal(h.node('alarmeTeste').disabled, true);
  h.telemetry(next);
  assert.equal(h.node('alarmeTeste').disabled, false);
  next.emit('offline');
  assert.equal(h.node('alarmeTeste').disabled, true);
  next.emit('connect');
  assert.equal(h.node('alarmeTeste').disabled, true);
  h.telemetry(next);
  next.emit('message', 'iotmotor/esp32-02/status', Buffer.from('offline'), {retain: false});
  assert.equal(h.node('alarmeTeste').disabled, true);
});

test('recusa limites fora da faixa e usa o dispositivo selecionado para testar o alarme', () => {
  const h = setup();
  h.node('prefix').value = 'bancada/teste'; h.node('sensorDevice').value = 's3-lab';
  const c = h.connect();
  h.telemetry(c);
  for (const value of ['', '0.01', '9', 'Infinity', 'NaN']) {
    h.node('alarmeVib').value = value;
    h.node('alarmeForm').fire('submit');
  }
  assert.equal(c.published.length, 0);
  h.node('alarmeTeste').fire('click');
  assert.equal(c.published[0].topic, 'bancada/teste/s3-lab/command');
  assert.equal(c.published[0].data.action, 'alarm_test');
});

test('dashboard conecta os auxiliares depois de substituir a conexao e desconecta todos juntos', () => {
  const h = setup();
  // Carrega as funcoes do dashboard sem inicializar sua interface grafica.
  const document = h.context.document;
  delete h.context.document;
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'dual-dashboard.js'), 'utf8'), h.context);
  h.context.document = document;
  vm.runInContext('render = () => {};', h.context);
  h.node('commandDevice').value = 'esp32-01';
  const calls = [];
  for (const name of ['iotmotorRemoteControls', 'iotmotorWifi', 'iotmotorAlarme'])
    h.context.window[name] = {connect: () => calls.push(name + ':connect'), disconnect: () => calls.push(name + ':disconnect')};
  vm.runInContext('connect()', h.context);
  assert.equal(calls.length, 3);
  calls.length = 0;
  vm.runInContext('connect()', h.context);
  assert.deepEqual(calls.map(c => c.split(':')[1]), ['disconnect', 'disconnect', 'disconnect', 'connect', 'connect', 'connect']);
  calls.length = 0;
  h.node('broker').value = 'http://invalid';
  vm.runInContext('connect()', h.context);
  assert.equal(calls.length, 0);
  vm.runInContext('disconnect()', h.context);
  assert.equal(calls.length, 3);
  const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
  assert.match(html, /<script src="\.\/alarm-controls\.js" defer><\/script>/);
});