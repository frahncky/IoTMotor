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
  function criar() {
    return {
      value: '', checked: true, disabled: false, textContent: '', className: '', title: '',
      type: '', step: '', handlers: {}, children: [], atributos: {},
      get options() { return this.children; },
      addEventListener(name, fn) { this.handlers[name] = fn; },
      fire(name) { this.handlers[name]?.({preventDefault() {}}); },
      replaceChildren() { this.children = []; },
      append(...filhos) { this.children.push(...filhos); },
      setAttribute(nome, valor) { this.atributos[nome] = valor; }
    };
  }
  function node(id) {
    if (!nodes.has(id)) nodes.set(id, criar());
    return nodes.get(id);
  }
  node('broker').value = 'wss://test.mosquitto.org:8081';
  node('prefix').value = 'iotmotor';
  node('sensorDevice').value = 'esp32-02';
  const clients = [];
  const context = vm.createContext({
    document: {getElementById: node, createElement: criar, createTextNode: t => ({textContent: t}), querySelectorAll: () => []},
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
    // Date real, com o agora controlado pelo teste.
    URL, Date: class extends Date { static now() { return now; } },
    Math, JSON, Number, Set, Map, Array, String, Boolean,
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
    alarm_enabled: true, alarm_active: false, mpu_ok: true, temperature_ok: true, ...extra
  }, retain);
  const PADRAO = [
    {id: 'vib', field: 'vibration_peak', board: 'sensors', above: true, limit: 0.5, on: true, firing: false},
    {id: 'temp', field: 'temperature', board: 'sensors', above: true, limit: 60, on: true, firing: false}
  ];
  const alarms = (client, lista = PADRAO, max = 8) => send(client, 'alarms', {alarms: lista, max}, true);
  // Cada linha da lista tem: nome, limite, origem, [disparado], ligado, ops.
  const linhas = () => node('alarmeLista').children;
  const parte = (linha, classe) => linha.children.find(c => c.className === classe);
  return {node, clients, context, connect, send, telemetry, alarms, timers, linhas, parte, PADRAO,
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
  assert.equal(h.node('alarmeSalvar').disabled, false);
  h.advance(10000);
  assert.equal(h.node('alarmeSalvar').disabled, true);
  assert.match(h.node('alarmeEstado').textContent, /sem dados recentes/);
});

test('a lista retida da placa vira as linhas editaveis do painel', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c);
  assert.match(h.node('alarmeResumo').textContent, /firmware antigo/);
  assert.equal(h.node('alarmeAddBtn').disabled, true);
  h.alarms(c);
  assert.equal(h.node('alarmeResumo').textContent, '2 de 8 alarmes gravados na placa.');
  assert.equal(h.linhas().length, 2);
  assert.equal(h.parte(h.linhas()[0], 'nome').textContent, 'Vibração (pico) (g) acima de');
  assert.equal(h.parte(h.linhas()[0], 'limite').value, '0.5');
  assert.equal(h.node('alarmeAddBtn').disabled, false);
  // Lista cheia: nao ha espaco para outro alarme na placa.
  h.alarms(c, [h.PADRAO[0]], 1);
  assert.equal(h.node('alarmeAddBtn').disabled, true);
});

test('editar o limite de uma linha e confirmar grava so aquele alarme', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c); h.alarms(c);
  const linha = h.linhas()[1];
  h.parte(linha, 'limite').value = '75';
  h.parte(linha, 'limite').fire('input');
  h.parte(linha, 'ops').children[0].fire('click');
  assert.deepEqual(c.published[0].data, {
    v: 1, device_id: 'esp32-02', seq: c.published[0].data.seq, action: 'alarm_save',
    alarm: {id: 'temp', field: 'temperature', board: 'sensors', above: true, limit: 75, on: true}
  });
  // O rascunho sobrevive a uma telemetria nova enquanto a placa nao confirma.
  h.telemetry(c);
  assert.equal(h.parte(h.linhas()[1], 'limite').value, '75');
  h.send(c, 'command_ack', {...c.published[0].data, accepted: true, reason: 'alarme atualizado'});
  h.alarms(c, [h.PADRAO[0], {...h.PADRAO[1], limit: 75}]);
  assert.equal(h.parte(h.linhas()[1], 'limite').value, '75');
  assert.equal(h.timers.size, 0);
});

test('o campo do limite pode ser apagado e digitado sem a lista atropelar', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c); h.alarms(c);
  const campo = () => h.parte(h.linhas()[0], 'limite');
  // Apagar o campo é um estado legítimo: nada de voltar o valor da placa.
  campo().value = ''; campo().fire('input');
  h.telemetry(c);
  h.advance(1000);
  assert.equal(campo().value, '');
  // Gravar assim avisa em vez de mandar lixo para a placa.
  h.parte(h.linhas()[0], 'ops').children[0].fire('click');
  assert.equal(c.published.length, 0);
  assert.match(h.node('alarmeFeedback').textContent, /campo está vazio/);
  // Digitando aos poucos, o que já foi escrito continua lá.
  campo().value = '0'; campo().fire('input');
  h.telemetry(c);
  campo().value = '0,8'; campo().fire('input');
  h.telemetry(c);
  h.advance(1000);
  assert.equal(campo().value, '0,8');
  h.parte(h.linhas()[0], 'ops').children[0].fire('click');
  assert.equal(c.published[0].data.alarm.limit, 0.8, 'vírgula vale como decimal');
});

test('adiciona alarme de corrente do quadro de comando e recusa limite fora da faixa', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c); h.alarms(c);
  assert.equal(h.node('alarmeGrandeza').options.length, 8);
  h.node('alarmeGrandeza').value = 'current';
  h.node('alarmeLimite').value = '500';
  h.node('alarmeAddForm').fire('submit');
  assert.equal(c.published.length, 0);
  assert.match(h.node('alarmeFeedback').textContent, /Corrente \(A\): informe de 0 a 200/);
  h.node('alarmeLimite').value = '12.5';
  h.node('alarmeAddForm').fire('submit');
  assert.deepEqual(c.published[0].data.alarm, {
    id: 'current', field: 'current', board: 'command', above: true, limit: 12.5, on: true
  });
  h.send(c, 'command_ack', {...c.published[0].data, accepted: true, reason: 'alarme criado'});
  // O id novo nao colide com o que ja esta na placa.
  h.alarms(c, [...h.PADRAO, {id: 'current', field: 'current', board: 'command', above: true, limit: 12.5, on: true}]);
  h.node('alarmeLado').value = 'below';
  h.node('alarmeLimite').value = '3';
  h.node('alarmeAddForm').fire('submit');
  assert.deepEqual(c.published[1].data.alarm, {
    id: 'current2', field: 'current', board: 'command', above: false, limit: 3, on: true
  });
});

test('o botao de recarregar pede a lista de novo a placa', () => {
  const h = setup(), c = h.connect();
  assert.equal(h.node('alarmeRecarregar').disabled, true);
  h.telemetry(c);
  h.node('alarmeRecarregar').fire('click');
  assert.deepEqual(c.published[0].data, {
    v: 1, device_id: 'esp32-02', seq: c.published[0].data.seq, action: 'alarm_list'
  });
});

test('o botao de remover tira o alarme da placa', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c); h.alarms(c);
  h.parte(h.linhas()[0], 'ops').children[1].fire('click');
  assert.deepEqual(c.published[0].data, {
    v: 1, device_id: 'esp32-02', seq: c.published[0].data.seq, action: 'alarm_remove', id: 'vib'
  });
  assert.match(h.node('alarmeFeedback').textContent, /Removendo/);
});

test('a telemetria diz quais alarmes estao disparados agora', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c); h.alarms(c);
  assert.equal(h.linhas()[0].className, '');
  h.telemetry(c, {alarm_active: true, alarms_firing: ['vib']});
  assert.equal(h.linhas()[0].className, 'atual');
  assert.equal(h.linhas()[1].className, '');
  assert.match(h.node('alarmeEstado').textContent, /ALARME/);
  const ativos = h.node('alarmeAtivosLista').children;
  assert.equal(ativos.length, 1);
  assert.equal(ativos[0].className, 'atual');
  assert.match(ativos[0].children[0].textContent, /Vibração/);
  assert.doesNotMatch(ativos[0].children[0].textContent, /Temperatura/);
  assert.equal(h.node('alarmeAtivosResumo').textContent, '1 alarme ativo neste momento.');
  // Sem nada disparado a frase aparece so no resumo, nao repetida na lista.
  h.telemetry(c, {alarm_active: false, alarms_firing: []});
  assert.equal(h.node('alarmeAtivosLista').children.length, 0);
  assert.equal(h.node('alarmeAtivosResumo').textContent, 'Nenhum alarme ativo.');
});

test('o botao Salvar envia interruptor, bipes e frequencia do buzzer', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c);
  h.node('alarmeOn').checked = false; h.node('alarmeOn').fire('change');
  h.node('alarmeSons').checked = true; h.node('alarmeSons').fire('change');
  h.telemetry(c);
  assert.equal(h.node('alarmeOn').checked, false);
  h.node('alarmeForm').fire('submit');
  assert.deepEqual(c.published[0].data, {v: 1, device_id: 'esp32-02', seq: c.published[0].data.seq,
    action: 'alarm_set', enabled: false, sounds: true, buzzer_hz: 2000});
  h.node('alarmeForm').fire('submit');
  assert.equal(c.published.length, 1);
  h.send(c, 'command_ack', {...c.published[0].data, accepted: true});
  assert.equal(h.node('alarmeSalvar').disabled, false);
  assert.equal(h.timers.size, 0);
});

test('rejeicao, erro de publicacao e timeout liberam o formulario sem perder o rascunho', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c); h.alarms(c);
  h.parte(h.linhas()[0], 'limite').value = '0.9';
  h.parte(h.linhas()[0], 'limite').fire('input');
  h.parte(h.linhas()[0], 'ops').children[0].fire('click');
  h.send(c, 'command_ack', {...c.published[0].data, accepted: false, reason: 'falha ao gravar'});
  assert.match(h.node('alarmeFeedback').textContent, /recusou/);
  assert.equal(h.parte(h.linhas()[0], 'limite').value, '0.9');
  c.publishError = Error('sem rede');
  h.parte(h.linhas()[0], 'ops').children[0].fire('click');
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
  h.telemetry(c, {alarm_active: true, alarms_firing: ['vib']});
  assert.equal(h.node('alarmeEstado').textContent, 'ALARME: limite ultrapassado');
  h.telemetry(c, {alarm_enabled: false});
  assert.equal(h.node('alarmeEstado').textContent, 'alarme desligado');
});

test('reconexao exige novos dados e ignora mensagens da conexao encerrada', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c); h.alarms(c);
  h.node('alarmeTeste').fire('click');
  const next = h.connect();
  assert.equal(c.connected, false);
  assert.equal(h.timers.size, 0);
  assert.equal(h.linhas().length, 0);
  h.telemetry(c);
  assert.equal(h.node('alarmeTeste').disabled, true);
  h.telemetry(next);
  assert.equal(h.node('alarmeTeste').disabled, false);
  next.emit('offline');
  // Quedas curtas do broker sao toleradas por 6 s para evitar oscilacao visual.
  assert.equal(h.node('alarmeTeste').disabled, false);
  next.emit('connect');
  // Ao reconectar o transporte, exige telemetria nova da placa antes de liberar comandos.
  assert.equal(h.node('alarmeTeste').disabled, true);
  h.telemetry(next);
  next.emit('message', 'iotmotor/esp32-02/status', Buffer.from('offline'), {retain: false});
  assert.equal(h.node('alarmeTeste').disabled, true);
});

test('usa o dispositivo selecionado para testar o alarme', () => {
  const h = setup();
  h.node('prefix').value = 'bancada/teste'; h.node('sensorDevice').value = 's3-lab';
  const c = h.connect();
  h.telemetry(c);
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

test('o botao Bipar pede um bipe curto ao S3, sem mexer nos limites', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c);
  h.node('alarmeBipe').fire('click');
  const cmd = c.published[0];
  assert.equal(cmd.topic, 'iotmotor/esp32-02/command');
  assert.deepEqual(cmd.data, {v: 1, device_id: 'esp32-02', seq: cmd.data.seq,
    action: 'buzzer_beep', count: 2, ms: 120, freq: 2000});
});

test('o botao Testar LED envia led_test sem comando de buzzer', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c);
  h.node('alarmeTesteLed').fire('click');
  const cmd = c.published[0];
  assert.equal(cmd.topic, 'iotmotor/esp32-02/command');
  assert.deepEqual(cmd.data, {v: 1, device_id: 'esp32-02', seq: cmd.data.seq,
    action: 'led_test'});
});

test('sensor sem leitura aparece como falha, nao como limite ultrapassado', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c); h.alarms(c);
  h.telemetry(c, {alarm_active: true, alarms_firing: [], temperature_ok: false});
  assert.equal(h.node('alarmeEstado').textContent, 'ALARME: falha de sensor');
  let ativos = h.node('alarmeAtivosLista').children;
  assert.equal(ativos.length, 1);
  assert.match(ativos[0].children[0].textContent, /Falha de sensor: temperatura sem leitura/);
  assert.equal(ativos[0].children[1].textContent, 'falha');
  assert.equal(h.node('alarmeAtivosResumo').textContent, '1 falha de sensor neste momento.');
  // Limite ultrapassado junto com a falha: os dois aparecem.
  h.telemetry(c, {alarm_active: true, alarms_firing: ['vib'], temperature_ok: false});
  assert.equal(h.node('alarmeEstado').textContent, 'ALARME: limite ultrapassado');
  ativos = h.node('alarmeAtivosLista').children;
  assert.equal(ativos.length, 2);
  assert.equal(h.node('alarmeAtivosResumo').textContent, '1 alarme ativo e 1 falha de sensor neste momento.');
  // Com o monitoramento desligado, a placa nao entra em alarme por isso.
  h.telemetry(c, {alarm_enabled: false, alarm_active: false, temperature_ok: false});
  assert.equal(h.node('alarmeAtivosLista').children.length, 0);
});

test('alarmes ativos tambem lista os avisos do painel sem repetir o que a placa ja informa', () => {
  const h = setup(), c = h.connect();
  h.telemetry(c); h.alarms(c);
  const avisos = [
    {kind: 'near', field: 'temperature', level: 'warn', text: 'Temperatura alta: 56.0 °C (limite 60 °C)'},
    {kind: 'over', field: 'vibration_peak', level: 'alarm', text: 'Vibração (pico) alta: 0.70 g (limite 0.5 g)'},
    {kind: 'missing', field: 'temperature', level: 'warn', text: 'Temperatura sem leitura'},
    {kind: 'missing', field: 'pzem', level: 'warn', text: 'Medições elétricas (PZEM) sem leitura'},
    {kind: 'no-data', field: 'command', level: 'warn', text: 'Quadro de comando sem dados'},
    {kind: 'no-data', field: 'sensor', level: 'warn', text: 'Sensores do motor sem dados'}
  ];
  h.context.window.iotmotorPainel = {avisos: () => avisos};
  h.telemetry(c, {alarm_active: true, alarms_firing: ['vib'], temperature_ok: false});
  const textos = h.node('alarmeAtivosLista').children.map(li => `${li.children[0].textContent}|${li.children[1].textContent}`);
  assert.deepEqual(textos, [
    'Vibração (pico) (g) acima de 0.5|disparado',
    'Falha de sensor: temperatura sem leitura (DS18B20)|falha',
    'Temperatura alta: 56.0 °C (limite 60 °C)|atenção',
    'Medições elétricas (PZEM) sem leitura|sem leitura',
    'Quadro de comando sem dados|sem leitura'
  ]);
  assert.equal(h.node('alarmeAtivosResumo').textContent, '1 alarme ativo, 1 falha de sensor e 3 avisos neste momento.');
  // Monitoramento desligado: sem falha listada, a falta de leitura aparece como aviso.
  h.telemetry(c, {alarm_enabled: false, temperature_ok: false});
  assert.ok(h.node('alarmeAtivosLista').children.some(li => li.children[0].textContent === 'Temperatura sem leitura'));
});
