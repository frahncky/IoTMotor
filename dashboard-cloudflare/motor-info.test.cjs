const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {EventEmitter} = require('node:events');

// Sobe a seção "Dados do motor" com um DOM de mentira.
function secao() {
  const nos = new Map();
  const criar = () => ({
    value: '', checked: false, disabled: false, textContent: '', hidden: false,
    handlers: {}, labels: [],
    addEventListener(nome, fn) { this.handlers[nome] = fn; },
    fire(nome) { this.handlers[nome]?.({preventDefault() {}}); }
  });
  const no = id => { if (!nos.has(id)) nos.set(id, criar()); return nos.get(id); };
  no('broker').value = 'wss://test.mosquitto.org:8081';
  no('prefix').value = 'iotmotor';
  no('commandDevice').value = 'esp32-01';
  no('motorInfoForm');
  const clientes = [];
  const contexto = vm.createContext({
    document: {getElementById: no},
    window: {mqtt: {connect() {
      const c = new EventEmitter();
      c.connected = true; c.publicados = [];
      c.subscribe = (topicos, opcoes, cb) => cb?.(null);
      c.publish = (topico, dados) => c.publicados.push({topico, dados: JSON.parse(dados)});
      c.end = () => {};
      clientes.push(c);
      return c;
    }}},
    URL, Date, Math, JSON, Number, String, Object, Array,
    setTimeout() { return 0; }, clearTimeout() {}, confirm: () => true
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'motor-info.js'), 'utf8'), contexto);
  contexto.window.iotmotorMotorInfo.connect();
  const cliente = clientes.at(-1);
  cliente.emit('connect');
  const receber = (tipo, dados) => cliente.emit('message', `iotmotor/esp32-01/${tipo}`,
    Buffer.from(JSON.stringify({device_id: 'esp32-01', ...dados})));
  return {no, cliente, receber, api: contexto.window.iotmotorMotorInfo};
}

test('dados retidos da placa preenchem o formulário e ficam disponíveis para o painel', () => {
  const h = secao();
  assert.equal(h.api.dados(), null);
  assert.equal(h.no('motorInfoCargaDica').hidden, false);
  h.receber('motor_info', {current_a: 4.2, voltage_v: 220, rpm: 1730, phases: 3});
  assert.equal(h.no('motorInfoA').value, '4,2');
  assert.equal(h.no('motorInfoV').value, '220');
  assert.equal(h.no('motorInfoCv').value, '');
  assert.equal(h.no('motorInfoFases').value, '3');
  assert.equal(h.api.dados().current_a, 4.2);
  assert.equal(h.no('motorInfoCargaDica').hidden, true, 'com corrente nominal a dica some');
});

test('gravar envia só os campos preenchidos, aceita vírgula e recusa valor fora da faixa', () => {
  const h = secao();
  h.no('motorInfoA').value = '4,2';
  h.no('motorInfoFs').value = '1,15';
  h.no('motorInfoCv').value = '1,5';
  h.no('motorInfoFases').value = '1';
  h.no('motorInfoForm').fire('submit');
  const envio = h.cliente.publicados.at(-1);
  assert.equal(envio.topico, 'iotmotor/esp32-01/command');
  assert.equal(envio.dados.action, 'motor_info_set');
  assert.deepEqual(envio.dados.motor, {power_cv: 1.5, current_a: 4.2, service_factor: 1.15, phases: 1});
  h.receber('command_ack', {seq: envio.dados.seq, action: 'motor_info_set', accepted: true, reason: 'dados do motor gravados'});
  assert.match(h.no('motorInfoFeedback').textContent, /confirmou/);

  const antes = h.cliente.publicados.length;
  h.no('motorInfoFs').value = '0,5';  // Fator de serviço abaixo de 1.
  h.no('motorInfoForm').fire('submit');
  assert.equal(h.cliente.publicados.length, antes, 'valor inválido não sai para a placa');
});

test('zerar horímetro pede o comando próprio ao quadro', () => {
  const h = secao();
  h.no('motorInfoZerar').fire('click');
  assert.equal(h.cliente.publicados.at(-1).dados.action, 'motor_counters_reset');
});

test('trifásico de dupla tensão: grava os dois pares e a ligação; a carga usa a corrente da ligação em uso', () => {
  const h = secao();
  h.no('motorInfoFases').value = '3';
  h.no('motorInfoV').value = '380/220';  // Fora de ordem: o painel põe o triângulo primeiro.
  h.no('motorInfoA').value = '12,6 / 7,3';
  h.no('motorInfoV').fire('input');
  assert.equal(h.no('motorInfoLigacaoCampo').hidden, false, 'com duas tensões aparece a ligação');
  h.no('motorInfoLigacao').value = 'delta';
  h.no('motorInfoForm').fire('submit');
  assert.deepEqual(h.cliente.publicados.at(-1).dados.motor,
    {phases: 3, voltage_v: 220, voltage_y_v: 380, current_a: 12.6, current_y_a: 7.3, connection: 'delta'});
  const envio = h.cliente.publicados.at(-1).dados;
  h.receber('command_ack', {seq: envio.seq, action: envio.action, accepted: true, reason: 'dados do motor gravados'});

  h.receber('motor_info', {voltage_v: 220, voltage_y_v: 380, current_a: 12.6, current_y_a: 7.3, phases: 3, connection: 'star'});
  assert.equal(h.no('motorInfoV').value, '220/380');
  assert.equal(h.no('motorInfoA').value, '12,6/7,3');
  assert.equal(h.no('motorInfoLigacao').value, 'star');
  assert.equal(h.api.dados().current_in_use_a, 7.3, 'em estrela vale a corrente da estrela');
  assert.equal(h.api.dados().voltage_in_use_v, 380);
});

test('dupla tensão exige trifásico e os dois pares completos', () => {
  const h = secao();
  const antes = h.cliente.publicados.length;
  h.no('motorInfoV').value = '220/380';
  h.no('motorInfoA').value = '12,6/7,3';
  h.no('motorInfoFases').value = '1';
  h.no('motorInfoForm').fire('submit');
  assert.match(h.no('motorInfoFeedback').textContent, /só em motor trifásico/);
  h.no('motorInfoFases').value = '3';
  h.no('motorInfoA').value = '12,6';
  h.no('motorInfoForm').fire('submit');
  assert.match(h.no('motorInfoFeedback').textContent, /as duas tensões e as duas correntes/);
  h.no('motorInfoA').value = '12,6/abc';
  h.no('motorInfoForm').fire('submit');
  assert.match(h.no('motorInfoFeedback').textContent, /Corrente: use um valor/);
  assert.equal(h.cliente.publicados.length, antes);
});

test('manutenção: intervalo vai no cadastro e "Manutenção feita" pede o comando próprio', () => {
  const h = secao();
  h.no('motorInfoManutH').value = '2000';
  h.no('motorInfoForm').fire('submit');
  assert.equal(h.cliente.publicados.at(-1).dados.motor.maint_interval_h, 2000);
  const envio = h.cliente.publicados.at(-1).dados;
  h.receber('command_ack', {seq: envio.seq, action: envio.action, accepted: true, reason: 'ok'});
  h.no('motorInfoManutFeita').fire('click');
  assert.equal(h.cliente.publicados.at(-1).dados.action, 'maintenance_done');
  h.receber('motor_info', {maint_interval_h: 2000, maint_done_run_s: 7200, maint_done_utc: 1790000000});
  assert.equal(h.api.dados().maint_done_run_s, 7200);
  assert.equal(h.api.dados().maint_done_utc, 1790000000);
});
