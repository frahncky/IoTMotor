'use strict';

// Painel somente leitura: não envia comandos ao motor.
const $ = (id) => document.getElementById(id);
const STORAGE_KEY = 'iotmotor_dashboard_connection_v1';
const DEFAULT_BROKER = 'wss://test.mosquitto.org:8081';
const LEGACY_BROKER = 'wss://broker.hivemq.com:8884/mqtt';
const HISTORY_LIMIT = 120;
const STALE_AFTER_MS = 10000;
const ns = 'http://www.w3.org/2000/svg';
const state = {
  client: null, generation: 0, connected: false, connectedAt: 0,
  lastSampleAt: 0, messages: 0, lastStatus: '—', history: [],
  voltage: null, current: null, motorOn: null,
  config: { broker: DEFAULT_BROKER, prefix: 'iotmotor', device: 'esp32-01' }
};
function text(id, value) { $(id).textContent = String(value); }
function friendlyError(error) { return String(error?.message || error || 'Erro desconhecido').slice(0, 180); }
function numeric(value) {
  if (value === null || value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}
function dateTime(value) { return new Date(value).toLocaleTimeString('pt-BR', { hour12: false }); }
function setConnection(label, kind = '') {
  text('connectionText', label);
  $('connection').className = `pill ${kind}`.trim();
  text('mqttState', label);
  $('connectBtn').textContent = state.client ? 'Desconectar' : 'Conectar ao MQTT';
}
function showDiagnostic(message) { text('diagnostic', message); }
function validateConfig() {
  const broker = $('broker').value.trim();
  const prefix = $('prefix').value.trim().replace(/^\/+|\/+$/g, '');
  const device = $('device').value.trim();
  let url;
  try { url = new URL(broker); } catch { throw new Error('URL do broker inválida.'); }
  if (url.protocol !== 'wss:' || !url.hostname || url.username || url.password || url.hash) {
    throw new Error('Informe uma URL wss:// válida, sem usuário, senha ou fragmento.');
  }
  if (!/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(prefix)) {
    throw new Error('O prefixo deve conter somente letras, números, hífen, sublinhado e barras entre segmentos.');
  }
  if (!/^[a-zA-Z0-9_-]+$/.test(device)) {
    throw new Error('O ID do dispositivo deve conter somente letras, números, hífen e sublinhado.');
  }
  return { broker: url.toString(), prefix, device };
}
function persistConfig() {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state.config)); } catch { /* opcional */ }
}
function restoreConfig() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
    if (saved && typeof saved === 'object') {
      for (const key of ['broker', 'prefix', 'device']) {
        if (typeof saved[key] === 'string' && saved[key].length < 250) state.config[key] = saved[key];
      }
    }
  } catch { /* sem dados salvos */ }
  // A versão anterior salvava HiveMQ como padrão: migrar SOMENTE esse padrão,
  // preservando URLs privadas ou Mosquitto escolhidas conscientemente.
  if (state.config.broker === LEGACY_BROKER || state.config.broker === `${LEGACY_BROKER}/`) {
    state.config.broker = DEFAULT_BROKER;
    persistConfig();
  }
  $('broker').value = state.config.broker;
  $('prefix').value = state.config.prefix;
  $('device').value = state.config.device;
  text('brokerValue', state.config.broker);
  text('deviceValue', state.config.device);
  text('deviceTitle', state.config.device);
}
function resetTelemetry() {
  state.lastSampleAt = 0;
  state.connectedAt = 0;
  state.messages = 0;
  state.lastStatus = '—';
  state.history = [];
  state.voltage = null;
  state.current = null;
  state.motorOn = null;
  text('statusValue', '—');
  text('messages', '0');
  $('csvBtn').disabled = true;
  refreshView();
}
function disconnect() {
  const old = state.client;
  state.generation += 1;
  state.client = null;
  state.connected = false;
  state.connectedAt = 0;
  if (old) old.end(true);
  setConnection('Desconectado');
  showDiagnostic('Desconectado manualmente. Os dados anteriores podem estar desatualizados.');
  refreshView();
}
function connect() {
  let config;
  try { config = validateConfig(); } catch (error) { showDiagnostic(friendlyError(error)); return; }
  if (!window.mqtt || typeof window.mqtt.connect !== 'function') {
    setConnection('Biblioteca indisponível', 'error');
    showDiagnostic('A biblioteca MQTT.js não carregou. Recarregue a página e confira se o navegador acessa cdnjs.cloudflare.com.');
    return;
  }
  const previous = state.client;
  state.generation += 1;
  const generation = state.generation;
  state.client = null;
  state.connected = false;
  if (previous) previous.end(true);
  state.config = config;
  persistConfig();
  resetTelemetry();
  text('brokerValue', config.broker);
  text('deviceValue', config.device);
  text('deviceTitle', config.device);
  setConnection('Conectando…', 'wait');
  showDiagnostic(`Conectando ao broker ${config.broker} por WSS. A porta 1883 é somente para o ESP32.`);
  const id = `iotmotor_web_${Math.random().toString(36).slice(2, 12)}`;
  let client;
  try {
    client = window.mqtt.connect(config.broker, {
      clientId: id, clean: true, protocolVersion: 4,
      reconnectPeriod: 4000, connectTimeout: 10000, keepalive: 30, resubscribe: true
    });
  } catch (error) {
    setConnection('Falha na conexão', 'error');
    showDiagnostic(`Não foi possível iniciar o MQTT: ${friendlyError(error)}`);
    return;
  }
  state.client = client;
  const active = () => generation === state.generation && state.client === client;
  client.on('connect', () => {
    if (!active()) return;
    state.connected = true;
    state.connectedAt = Date.now();
    setConnection('Broker conectado', 'live');
    const topics = [`${config.prefix}/${config.device}/telemetry`, `${config.prefix}/${config.device}/status`];
    client.subscribe(topics, { qos: 0 }, (error) => {
      if (!active()) return;
      if (error) showDiagnostic(`Broker conectado, mas a assinatura dos tópicos falhou: ${friendlyError(error)}`);
      else showDiagnostic(`Broker conectado. Assinando ${topics[0]}. Se não chegar telemetria, o ESP32 pode estar em outro broker, sem Wi-Fi ou sem publicar.`);
    });
  });
  client.on('message', (topic, payload) => {
    if (!active()) return;
    const telemetryTopic = `${config.prefix}/${config.device}/telemetry`;
    const statusTopic = `${config.prefix}/${config.device}/status`;
    if (topic === statusTopic) {
      state.lastStatus = payload.toString('utf8').slice(0, 80);
      text('statusValue', state.lastStatus);
      if (!state.lastSampleAt) showDiagnostic(`Status recebido: ${state.lastStatus}. Status retido não confirma conexão atual; aguardando ${telemetryTopic}.`);
      return;
    }
    if (topic !== telemetryTopic) return;
    let packet;
    try { packet = JSON.parse(payload.toString('utf8')); }
    catch { showDiagnostic('Mensagem recebida no tópico de telemetria não é JSON válido.'); return; }
    const data = packet && typeof packet === 'object' && packet.data && typeof packet.data === 'object' ? packet.data : packet;
    if (!data || typeof data !== 'object' || (packet.device_id && packet.device_id !== config.device)) {
      showDiagnostic('A mensagem recebida possui um ID de dispositivo diferente ou estrutura inválida.');
      return;
    }
    const voltage = numeric(data.voltage);
    const current = numeric(data.current);
    if (voltage === null && current === null && typeof data.motor_on !== 'boolean') {
      showDiagnostic('A mensagem não contém voltage, current nem motor_on. Confira o firmware instalado.');
      return;
    }
    if (voltage !== null) state.voltage = voltage;
    if (current !== null) state.current = current;
    if (typeof data.motor_on === 'boolean') state.motorOn = data.motor_on;
    state.messages += 1;
    state.lastSampleAt = Date.now();
    state.history.push({ timestamp: new Date(state.lastSampleAt).toISOString(), voltage: state.voltage, current: state.current, motorOn: state.motorOn });
    if (state.history.length > HISTORY_LIMIT) state.history.shift();
    text('messages', state.messages);
    $('csvBtn').disabled = false;
    showDiagnostic(`Recebendo telemetria de ${config.device} em ${telemetryTopic}.`);
    refreshView();
  });
  client.on('reconnect', () => {
    if (!active()) return;
    state.connected = false;
    state.connectedAt = 0;
    setConnection('Reconectando…', 'wait');
    showDiagnostic('A conexão MQTT caiu. Tentando reconectar ao broker automaticamente.');
    refreshView();
  });
  client.on('offline', () => {
    if (!active()) return;
    state.connected = false;
    state.connectedAt = 0;
    setConnection('Broker indisponível', 'error');
    showDiagnostic(`Não foi possível alcançar ${config.broker}. Confira WSS, rede e certificado; o broker público de testes pode ficar indisponível.`);
    refreshView();
  });
  client.on('error', (error) => {
    if (!active()) return;
    showDiagnostic(`Erro MQTT/WebSocket: ${friendlyError(error)}. O painel tentará reconectar.`);
  });
  client.on('close', () => {
    if (!active()) return;
    state.connected = false;
    state.connectedAt = 0;
    setConnection('Conexão encerrada', 'error');
    refreshView();
  });
  setConnection('Conectando…', 'wait');
}
function svgNode(tag, attrs = {}, label) {
  const node = document.createElementNS(ns, tag);
  for (const [name, value] of Object.entries(attrs)) node.setAttribute(name, String(value));
  if (label !== undefined) node.textContent = String(label);
  return node;
}
function plot(id, key, color) {
  const svg = $(id);
  svg.replaceChildren();
  const values = state.history.map((entry) => entry[key]).filter((value) => Number.isFinite(value));
  const x0 = 43, x1 = 630, y0 = 15, y1 = 184;
  if (values.length === 0) {
    svg.append(svgNode('text', { x: 320, y: 102, 'text-anchor': 'middle', class: 'empty' }, 'Aguardando telemetria'));
    return;
  }
  let min = Math.min(...values), max = Math.max(...values);
  const margin = Math.max((max - min) * .13, Math.abs(max) * .01, .02);
  min -= margin; max += margin;
  for (let i = 0; i <= 3; i++) {
    const y = y0 + (y1 - y0) * i / 3;
    svg.append(svgNode('line', { x1: x0, y1: y, x2: x1, y2: y, class: 'gridline' }));
    svg.append(svgNode('text', { x: x0 - 9, y: y + 4, 'text-anchor': 'end' }, (max - (max - min) * i / 3).toFixed(key === 'voltage' ? 0 : 1)));
  }
  const coordinates = values.map((value, i) => {
    const x = x0 + (x1 - x0) * (values.length === 1 ? .5 : i / (values.length - 1));
    const y = y1 - (value - min) / (max - min) * (y1 - y0);
    return `${x.toFixed(2)},${y.toFixed(2)}`;
  }).join(' ');
  svg.append(svgNode('polyline', { points: coordinates, stroke: color }));
  const finalX = x0 + (x1 - x0) * (values.length === 1 ? .5 : 1);
  const finalY = y1 - (values[values.length - 1] - min) / (max - min) * (y1 - y0);
  svg.append(svgNode('circle', { cx: finalX, cy: finalY, r: 4, fill: color }));
  svg.append(svgNode('text', { x: x0, y: 210 }, 'Mais antigo'));
  svg.append(svgNode('text', { x: x1, y: 210, 'text-anchor': 'end' }, 'Mais recente'));
}
function refreshView() {
  const isFresh = state.connected && !!state.lastSampleAt && Date.now() - state.lastSampleAt < STALE_AFTER_MS;
  text('voltage', state.voltage === null ? '—' : state.voltage.toFixed(1));
  text('current', state.current === null ? '—' : state.current.toFixed(2));
  text('motor', !isFresh ? 'Sem sinal' : state.motorOn === null ? 'Indefinido' : state.motorOn ? 'Ligado' : 'Desligado');
  $('motor').className = `num ${isFresh && state.motorOn ? 'green' : 'amber'}`;
  text('telemetry', isFresh ? 'Recebendo' : state.lastSampleAt ? 'Sem sinal' : 'Sem dados');
  $('telemetry').className = `num ${isFresh ? 'green' : 'amber'}`;
  text('lastSeen', state.lastSampleAt ? `Última amostra às ${dateTime(state.lastSampleAt)}` : 'Nenhuma amostra recebida');
  text('freshness', isFresh ? 'Sim (menos de 10 s)' : 'Não');
  plot('voltageChart', 'voltage', '#6bc4e6');
  plot('currentChart', 'current', '#f4b653');
}
function exportCsv() {
  if (!state.history.length) return;
  const lines = ['timestamp,voltage_v,current_a,motor_on'];
  for (const item of state.history) {
    lines.push([item.timestamp, item.voltage ?? '', item.current ?? '', item.motorOn === null ? '' : item.motorOn].join(','));
  }
  const blob = new Blob(['\ufeff' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
  const href = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = href;
  anchor.download = `iotmotor-${state.config.device}-${new Date().toISOString().slice(0, 10)}.csv`;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(href), 1000);
}
$('connectBtn').addEventListener('click', () => state.client ? disconnect() : connect());
$('settingsForm').addEventListener('submit', (event) => { event.preventDefault(); connect(); });
$('csvBtn').addEventListener('click', exportCsv);
restoreConfig();
refreshView();
text('clock', dateTime(Date.now()));
setInterval(() => {
  text('clock', dateTime(Date.now()));
  const wasFresh = $('freshness').textContent.startsWith('Sim');
  const isFresh = state.connected && !!state.lastSampleAt && Date.now() - state.lastSampleAt < STALE_AFTER_MS;
  if (wasFresh !== isFresh) {
    refreshView();
    if (state.connected && state.lastSampleAt && !isFresh) {
      showDiagnostic('Broker conectado, mas o ESP32 parou de publicar telemetria. Verifique energia, Wi-Fi e firmware.');
    }
  }
  if (state.connected && state.connectedAt && !state.lastSampleAt && Date.now() - state.connectedAt >= STALE_AFTER_MS) {
    showDiagnostic(`Broker conectado, mas sem telemetria no tópico ${state.config.prefix}/${state.config.device}/telemetry. Confirme no Monitor Serial que o ESP32 também conectou e publica no mesmo broker.`);
  }
}, 1500);
