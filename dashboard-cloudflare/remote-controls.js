'use strict';
// Controle remoto MQTT sem chave ou jumper: exclusivamente para ensaios sem motor/contatores.
(() => {
  const $ = id => document.getElementById(id);
  const start = $('startBtn'), stop = $('stopBtn');
  if (!start || !stop) return;
  let client = null, connected = false, prefix = '', device = '', boot = '';
  let updatedAt = 0, relays = null, pending = null, sequence = 0;
  const topic = kind => `${prefix}/${device}/${kind}`;
  // Janela de telemetria "recente". Medido no broker publico: intervalos de
  // 8 a 20 s sao comuns, e 10 s desabilitavam os botoes o tempo todo.
  const recent = () => Boolean(boot && Date.now() - updatedAt < 25000 && relays);
  const feedback = message => { $('commandFeedback').textContent = message; };
  function refresh() {
    // A pagina pode pedir a partida com MQTT conectado; nenhum jumper/chave.
    start.disabled = !connected || Boolean(pending && pending.action === 'start');
    stop.disabled = !connected; // Parada prioritária mesmo durante uma partida pendente.
    // Manutencao (Wi-Fi e firmware) so com as saidas confirmadas desligadas.
    const paradas = Array.isArray(relays) && relays.every(v => !v);
    for (const id of ['updateBtn'])
      if ($(id)) $(id).disabled = !connected || !recent() || !paradas;
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
    // Quedas curtas do broker publico (a biblioteca reconecta em 4 s) nao
    // desabilitam os botoes na hora: isso fazia eles piscarem sem motivo.
    // So depois de QUEDA_TOLERADA_MS sem voltar o painel se da por desconectado.
    const QUEDA_TOLERADA_MS = 6000;
    let quedaTimer = null;
    const caiu = () => {
      if (client !== active || quedaTimer) return;
      feedback('Conexão instável; reconectando ao broker…');
      quedaTimer = setTimeout(() => {
        quedaTimer = null;
        if (client !== active || active.connected) return;
        connected = false;
        feedback('Desconectado do broker; comandos indisponíveis.');
        refresh();
      }, QUEDA_TOLERADA_MS);
    };
    const voltou = () => {
      if (quedaTimer) { clearTimeout(quedaTimer); quedaTimer = null; }
    };
    active.on('offline', caiu);
    active.on('close', caiu);
    active.on('reconnect', caiu);
    active.on('connect', voltou);
    active.on('error', error => { if (client === active) feedback('Erro MQTT: ' + error.message); });
    refresh();
  }
  function send(action) {
    if (!client?.connected || !connected || (action === 'start' && pending?.action === 'start')) return;
    const comando = {v: 1, device_id: device, boot: action === 'stop' ? '' : boot, action,
      seq: String(sequence = Math.max(Date.now() * 1000 + Math.floor(Math.random() * 1000), sequence + 1))};
    if (action === 'start') {
      if (!recent()) {feedback('Aguardando telemetria recente do ESP32-01.');return;}
      if (relays.some(Boolean)) {feedback('Há contatores ligados; desligue antes de iniciar.');return;}
      // A partida vem da lista gravada na placa (local-controls.js).
      comando.profile = window.iotmotorPartidaSelecionada?.() || '';
      if (!comando.profile) {feedback('Escolha uma partida.');return;}
    }
    pending = {seq: comando.seq, action};
    feedback('Enviando ' + (action === 'start' ? 'partida' : 'parada') + ' MQTT…');
    client.publish(topic('command'), JSON.stringify(comando), {qos: 1, retain: false}, error => {
      if (error && pending?.seq === comando.seq) { feedback('Falha no envio: ' + error.message); pending = null;refresh(); }
    });
    setTimeout(() => {
      if (pending?.seq === comando.seq) {feedback('Sem confirmação do ESP32. Verifique o Monitor Serial.');pending = null;refresh();}
    }, 6500);
    refresh();
  }
  // Encerra a conexao dos comandos junto com a do painel: antes, "Desconectar"
  // so parava os graficos e os botoes continuavam publicando no broker.
  function desconectar() {
    if (client) client.end(true);
    client = null; connected = false; boot = ''; updatedAt = 0; relays = null; pending = null;
    feedback('Desconectado do broker; comandos indisponíveis.');
    refresh();
  }
  window.iotmotorRemoteControls = {connect, disconnect: desconectar};

  // Manutencao do firmware. As redes Wi-Fi ficam na aba "Wi-Fi" (wifi-manager.js).
  function manutencao(action, aviso) {
    if (!client?.connected || !confirm(aviso)) return;
    const seq = String(sequence = Math.max(Date.now() * 1000 + Math.floor(Math.random() * 1000), sequence + 1));
    feedback('Enviando pedido ao ESP32…');
    client.publish(topic('command'), JSON.stringify({
      v: 1, device_id: device, boot, seq, action, mode: 'none', mask: 0, main: 0, star: 0, delta: 0, seconds: 0
    }), {qos: 1, retain: false});
  }
  $('updateBtn')?.addEventListener('click', () => manutencao('update',
    'A placa vai baixar o firmware publicado no GitHub e reiniciar.\n\nContinuar?'));
  start.addEventListener('click', () => send('start'));
  stop.addEventListener('click', () => send('stop'));
  // Nao conecta sozinho: quem comanda a conexao e o botao Conectar do painel
  // (dual-dashboard.js chama connect/disconnect deste modulo).
  feedback('Desconectado. Use "Conectar ao MQTT" para comandar.');
  refresh();
  setInterval(refresh, 1000);
})();
