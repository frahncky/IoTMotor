'use strict';
/* O controle continua no HTTP LOCAL do ESP32 v6. Nenhum comando MQTT e enviado.
 * Um browser HTTPS nao pode usar fetch() para acionar um IP HTTP da LAN. */
(() => {
  const container = document.querySelector('.control .buttons');
  if (!container || !window.mqtt || typeof window.mqtt.connect !== 'function') return;
  const wrapper = document.createElement('div');
  wrapper.style.cssText = 'margin-top:14px;padding:14px;border:1px solid #4a7081;border-radius:10px;background:#092633';
  const title = document.createElement('strong');
  title.textContent = 'Ligar e desligar · painel local do ESP32';
  const explanation = document.createElement('p');
  explanation.className = 'muted';
  explanation.style.margin = '5px 0 10px';
  explanation.textContent = 'Abra o painel do ESP32 na mesma rede Wi-Fi para operar os quatro relés. O Cloudflare não envia comandos MQTT à versão local do firmware.';
  const link = document.createElement('a');
  link.className = 'btn secondary';
  link.textContent = 'Aguardando endereço IP da placa…';
  link.style.cssText = 'display:inline-block;pointer-events:none;opacity:.55;text-decoration:none';
  link.setAttribute('aria-disabled','true');
  link.target = '_blank';
  link.rel = 'noopener noreferrer';
  const notice = document.createElement('p');
  notice.className = 'muted';
  notice.style.margin = '10px 0 0';
  notice.textContent = 'Sem endereço IP confirmado. Confira o IP na primeira linha do LCD físico.';
  wrapper.append(title, explanation, link, notice);
  container.insertAdjacentElement('afterend', wrapper);

  let client = null;
  let lastAt = 0;
  let localIp = null;
  let topic = '';
  function ipv4(value) {
    if (typeof value !== 'string' || !/^\d{1,3}(?:\.\d{1,3}){3}$/.test(value)) return null;
    const parts = value.split('.').map(Number);
    if (parts.some(x => x > 255)) return null;
    const [a,b] = parts;
    if (!(a === 10 || a === 192 && b === 168 || a === 172 && b >= 16 && b <= 31)) return null;
    return parts.join('.');
  }
  function readIp(data) {
    const explicit = ipv4(data.wifi_ip);
    if (explicit) return explicit;
    const rows = data.lcd || data.lcd_lines;
    if (!Array.isArray(rows) || typeof rows[0] !== 'string') return null;
    return ipv4((rows[0].match(/\bIP:\s*(\d{1,3}(?:\.\d{1,3}){3})\b/i) || [])[1]);
  }
  function refresh() {
    const current = Boolean(client?.connected && localIp && Date.now()-lastAt<10000);
    if (!current) {
      link.removeAttribute('href');
      link.setAttribute('aria-disabled','true');
      link.style.pointerEvents = 'none';
      link.style.opacity = '.55';
      link.textContent = 'Painel local indisponível';
      notice.textContent = 'Não há telemetria recente com IP local válido; veja o IP no LCD e abra-o no navegador da mesma rede.';
      return;
    }
    link.href = `http://${localIp}/`;
    link.removeAttribute('aria-disabled');
    link.style.pointerEvents = 'auto';
    link.style.opacity = '1';
    link.textContent = 'Abrir painel local · Ligar / Desligar';
    notice.textContent = `Endereço informado pela placa: ${localIp}. Verifique-o no LCD antes de abrir. A operação ocorre no ESP32, não no Cloudflare.`;
  }
  function begin() {
    let saved = {};
    try { saved = JSON.parse(localStorage.getItem('iotmotor_dashboard_dual_v1') || '{}') || {}; } catch {}
    const broker = String(saved.broker || 'wss://test.mosquitto.org:8081').trim();
    const prefix = String(saved.prefix || 'iotmotor').trim();
    const device = String(saved.commandDevice || 'esp32-01').trim();
    let parsed;
    try { parsed = new URL(broker); } catch { return; }
    if (parsed.protocol !== 'wss:' || parsed.username || parsed.password || !/^[\w-]+(?:\/[\w-]+)*$/.test(prefix) || !/^[\w-]+$/.test(device)) return;
    if (client) client.end(true);
    localIp = null;
    lastAt = 0;
    topic = `${prefix}/${device}/telemetry`;
    client = window.mqtt.connect(parsed.toString(), {clientId:`iotmotor_lan_${Math.random().toString(36).slice(2,12)}`,clean:true,reconnectPeriod:4000,connectTimeout:10000,protocolVersion:4,keepalive:30});
    client.on('connect',() => client.subscribe(topic, {qos:0}));
    client.on('message',(destination,payload,packet) => {
      if (destination !== topic || packet?.retain) return;
      let data;
      try { data = JSON.parse(payload.toString('utf8')); } catch { return; }
      if (!data || data.device_id !== device) return;
      const pins = data.relay_pins;
      if (!Array.isArray(pins) || pins.length !== 4 || pins.some((pin,i)=>pin!==[19,18,23,27][i])) return;
      const ip = readIp(data);
      if (!ip) return;
      localIp = ip;
      lastAt = Date.now();
      refresh();
    });
    client.on('offline', refresh);
    client.on('close', refresh);
  }
  const form = document.getElementById('connectionForm');
  form?.addEventListener('submit',()=>setTimeout(begin,0));
  begin();
  setInterval(refresh,1500);
})();
