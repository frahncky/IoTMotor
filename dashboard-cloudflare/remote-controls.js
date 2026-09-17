'use strict';
// Controle remoto MQTT sem chave ou jumper: exclusivamente para ensaios sem motor/contatores.
(() => {
  const $ = id => document.getElementById(id);
  const start = $('startBtn'), stop = $('stopBtn');
  if (!start || !stop) return;
  let client = null, connected = false, prefix = '', device = '', boot = '';
  let updatedAt = 0, relays = null, pending = null, sequence = 0;
  const topic = kind => `${prefix}/${device}/${kind}`;
  const recent = () => Boolean(boot && Date.now() - updatedAt < 10000 && relays);
  const feedback = message => { $('commandFeedback').textContent = message; };
  function refresh() {
    // A pagina pode pedir a partida com MQTT conectado; nenhum jumper/chave.
    start.disabled = !connected || Boolean(pending && pending.action === 'start');
    stop.disabled = !connected; // Parada prioritária mesmo durante uma partida pendente.
  }
  function configuration() {
    const url = new URL(String($('broker').value || 'wss://test.mosquitto.org:8081').trim());
    const p = String($('prefix').value || 'iotmotor').trim();
    const d = String($('commandDevice').value || 'esp32-01').trim();
    if (url.protocol !== 'wss:' || url.username || url.password ||
        !/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(p) ||
        !/^[a-zA-Z0-9_-]+$/.test(d)) throw Error('Configuração MQTT inválida.');
    return {url: url.toString(), p, d};
  }
  function connect() {
    if (!window.mqtt?.connect) { feedback('Biblioteca MQTT indisponível.'); return; }
    let settings;
    try { settings = configuration(); } catch (e) { feedback(e.message); return; }
    if (client) client.end(true);
    connected = false; boot = ''; updatedAt = 0; relays = null; pending = null;
    prefix = settings.p; device = settings.d;
    const active = window.mqtt.connect(settings.url, {
      clientId: `iotmotor_control_${Math.random().toString(36).slice(2, 12)}`,
      clean: true, reconnectPeriod: 4000, connectTimeout: 10000,
      protocolVersion: 4, keepalive: 30
    });
    client = active;
    active.on('connect', () => {
      if (client !== active) return;
      connected = true;
      active.subscribe([topic('telemetry'), topic('command_ack')], {qos: 1});
      feedback('MQTT conectado. Aguardando telemetria do ESP32-01.');
      refresh();
    });
    active.on('message', (name, payload, packet) => {
      if (client !== active || packet?.retain) return;
      let data;
      try { data = JSON.parse(payload.toString('utf8')); } catch { return; }
      if (!data || data.device_id !== device) return;
      if (name === topic('telemetry')) {
        if (!/^[0-9a-f]{16}$/i.test(String(data.boot || '')) ||
            !Array.isArray(data.relays) || data.relays.length !== 4 ||
            data.relays.some(v => typeof v !== 'boolean')) return;
        boot = data.boot;
        updatedAt = Date.now();
        relays = data.relays;
        if (pending && ((pending.action === 'start' && relays.some(Boolean)) ||
                        (pending.action === 'stop' && relays.every(v => !v)))) {
          feedback(pending.action === 'start' ? 'ESP32 informou contatores ligados.' :
                   'ESP32 informou contatores desligados.');
          pending = null;
        }
      } else if (name === topic('command_ack') && pending && data.seq === pending.seq) {
        if (!data.accepted) {
          feedback('Comando recusado pelo ESP32: ' + (data.reason || 'verifique o estado do dispositivo'));
          pending = null;
        } else {
          feedback(data.action === 'stop' ? 'Parada recebida; aguardando estado dos contatores.' :
                   'Partida recebida; aguardando estado dos contatores.');
        }
      }
      refresh();
    });
    active.on('offline', () => { if (client === active) {connected = false;refresh();} });
    active.on('close', () => { if (client === active) {connected = false;refresh();} });
    active.on('error', error => { if (client === active) feedback('Erro MQTT: ' + error.message); });
    refresh();
  }
  function send(action) {
    if (!client?.connected || !connected || (action === 'start' && pending?.action === 'start')) return;
    const options = {mode: 'none', mask: 0, main: 0, star: 0, delta: 0, seconds: 0};
    if (action === 'start') {
      if (!recent()) {feedback('Aguardando telemetria recente do ESP32-01.');return;}
      if (relays.some(Boolean)) {feedback('Há contatores ligados; desligue antes de iniciar.');return;}
      options.mode = $('startMode').value;
      if (options.mode === 'direct') {
        document.querySelectorAll('.directRelay:checked').forEach(el => {
          options.mask |= 1 << (Number(el.value) - 1);
        });
        if (!options.mask) {feedback('Selecione pelo menos um contator.');return;}
      } else if (options.mode === 'sequence') {
        options.main = Number($('mainRelay').value);
        options.star = Number($('starRelay').value);
        options.delta = Number($('deltaRelay').value);
        options.seconds = Number($('starSeconds').value);
        if (new Set([options.main, options.star, options.delta]).size !== 3 ||
            [options.main, options.star, options.delta].some(v => !Number.isInteger(v) || v < 1 || v > 4) ||
            !Number.isInteger(options.seconds) || options.seconds < 2 || options.seconds > 30) {
          feedback('Selecione três contatores distintos e tempo de 2 a 30 segundos.');return;
        }
      } else {feedback('Modo de partida inválido.');return;}
    }
    const seq = String(sequence = Math.max(Date.now() * 1000 + Math.floor(Math.random() * 1000), sequence + 1));
    const command = {v: 1, device_id: device, boot: action === 'stop' ? '' : boot,
      seq, action, ...options};
    pending = {seq, action};
    feedback('Enviando ' + (action === 'start' ? 'partida' : 'parada') + ' MQTT…');
    client.publish(topic('command'), JSON.stringify(command), {qos: 1, retain: false}, error => {
      if (error && pending?.seq === seq) { feedback('Falha no envio: ' + error.message); pending = null;refresh(); }
    });
    setTimeout(() => {
      if (pending?.seq === seq) {feedback('Sem confirmação do ESP32. Verifique o Monitor Serial.');pending = null;refresh();}
    }, 6500);
    refresh();
  }
  start.addEventListener('click', () => send('start'));
  stop.addEventListener('click', () => send('stop'));
  $('connectionForm')?.addEventListener('submit', () => setTimeout(connect, 0));
  connect();
  setInterval(refresh, 1000);
})();
