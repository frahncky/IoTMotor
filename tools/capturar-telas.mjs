// Gera as capturas de tela de docs/images a partir do painel desta pasta.
//
//   node tools/capturar-telas.mjs            (todas)
//   node tools/capturar-telas.mjs painel     (so as que tiverem "painel" no nome)
//
// Abre o painel no Edge/Chrome sem janela e troca o MQTT.js por um broker de
// mentira dentro da propria pagina: as duas placas "publicam" telemetria,
// mensagens retidas e historico. Nada sai deste computador, e a bancada real
// nao e tocada. Precisa so do Node 22+ e do Edge (ou Chrome) instalado.
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {extname, join, resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PAINEL = join(RAIZ, 'dashboard-cloudflare');
const SAIDA = process.env.SAIDA_CAPTURAS || join(RAIZ, 'docs', 'images');
const NAVEGADORES = [
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/microsoft-edge',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
];

// Versoes mostradas nas telas: as publicadas para OTA (o painel compara).
const wifiJs = readFileSync(join(PAINEL, 'wifi-manager.js'), 'utf8');
const [, FW_QUADRO, FW_SENSORES] = wifiJs.match(/FIRMWARE_PUBLICADO = \['([^']+)', '([^']+)'\]/);

// ---- Broker de mentira, injetado antes dos scripts da pagina ---------------
function brokerFalso(fwQuadro, fwSensores) {
  const P = 'iotmotor', Q = 'esp32-01', S = 'esp32-02';
  const retidos = new Map(), clientes = new Set();
  const casa = (f, t) => {
    const a = f.split('/'), b = t.split('/');
    for (let i = 0; i < a.length; i++) {
      if (a[i] === '#') return true;
      if (i >= b.length || (a[i] !== '+' && a[i] !== b[i])) return false;
    }
    return a.length === b.length;
  };
  const pacote = texto => {
    const bytes = new TextEncoder().encode(texto);
    bytes.toString = () => texto;
    return bytes;
  };
  function entregar(topico, texto, retain) {
    if (retain) retidos.set(topico, texto);
    for (const c of clientes) if ([...c.filtros].some(f => casa(f, topico)))
      c.emitir('message', topico, pacote(texto), {retain: false});
  }
  const json = (topico, obj) => entregar(`${P}/${topico}`, JSON.stringify(obj), true);

  // Mensagens retidas das placas.
  entregar(`${P}/${Q}/status`, 'online', true);
  entregar(`${P}/${S}/status`, 'online', true);
  json(`${Q}/capabilities`, {device_id: Q, role: 'actuator_mqtt', firmware_version: fwQuadro,
    fields: ['voltage', 'current', 'power', 'energy', 'frequency', 'pf']});
  json(`${S}/capabilities`, {device_id: S, firmware_version: fwSensores, demo: false});
  json('system/acquisition', {v: 1, source: Q, revision: 3, pzem_read_ms: 1000, publish_ms: 1000,
    chart_ms: 1000, record_ms: 1000, vibration_hz: 1000, vibration_window_ms: 1000,
    history_bucket_s: 3600, history_retention_days: 7});
  json(`${Q}/motor_info`, {device_id: Q, power_cv: 5, voltage_v: 220, voltage_y_v: 380,
    current_a: 12.6, current_y_a: 7.3, phases: 3, connection: 'delta', rpm: 1730,
    service_factor: 1.15, maint_interval_h: 2000, maint_done_run_s: 1485000, maint_done_utc: 1788000000});
  json(`${Q}/profiles`, {device_id: Q, max: 6, limit_ms: 300000, run_limit_s: 300, profiles: [
    {id: 'estrela_triangulo', name: 'Estrela-triângulo', cnt: [
      {use: true, on: 0, off: 0}, {use: true, on: 0, off: 5000},
      {use: true, on: 5700, off: 0}, {use: false, on: 500, off: 0}]},
    {id: 'direta', name: 'Partida direta', cnt: [
      {use: true, on: 0, off: 0}, {use: false, on: 0, off: 0},
      {use: false, on: 0, off: 0}, {use: false, on: 0, off: 0}]}]});
  json(`${S}/alarms`, {device_id: S, max: 8, buzzer_hz: 2000, alarms: [
    {id: 'temp', field: 'temperature', board: 'sensors', above: true, limit: 60, on: true, trip: false, firing: false},
    {id: 'vib', field: 'vibration_mms', board: 'sensors', above: true, limit: 4.5, on: true, trip: false, firing: false},
    {id: 'corr', field: 'current', board: 'command', above: true, limit: 14.5, on: true, trip: true, firing: false}]});
  json(`${S}/alarm_log`, {device_id: S, events: []});
  const agoraS = Math.floor(Date.now() / 1000);
  for (const [dev, ip, rssi] of [[Q, '192.168.0.41', -58], [S, '192.168.0.42', -63]])
    json(`${dev}/wifi`, {device_id: dev, max: 8, connected: 'IFMA_IOT',
      networks: [{ssid: 'IFMA_IOT', open: true}, {ssid: 'Laboratorio', open: false}],
      ap: {name: `IoTMotor-${dev}`, open: false},
      diagnostics: {rssi, connected_ms: 5_400_000, last_network: 'IFMA_IOT', reconnections: 1,
        disconnect_reason: 0, uptime_ms: 5_460_000, heap_bytes: 182_000, min_heap_bytes: 151_000,
        reset_reason: 1}, wifi_ip: ip});
  // Historico de 7 dias: o motor gira das 11h as 20h UTC (8h-17h em Brasilia).
  // Temperatura por um modelo termico de primeira ordem (constante de ~1,5 h):
  // sobe para ~46 °C ligado e volta aos 24 °C do ambiente desligado.
  const hoje = Math.floor(agoraS / 86400);
  let tempC = 24;
  for (let d = hoje - 6; d <= hoje; d++) {
    const horas = [];
    for (let h = 0; h < 24; h++) {
      if (d === hoje && h > new Date().getUTCHours()) break;
      // Um dia com o motor parado mais cedo, para o grafico nao ficar repetitivo.
      const ligado = h >= 11 && (d - hoje === -2 ? h < 15 : h < 20);
      tempC += ((ligado ? 46 : 24) - tempC) * (1 - Math.exp(-1 / 1.5));
      const temp = Math.round(tempC * 10);
      horas.push([h, ligado ? 880 + (h % 3) * 12 : null, ligado ? 1040 + (h % 4) * 17 : null,
        2198 + (h % 5), temp, temp + (ligado ? 18 : 6), ligado ? 158 + (h % 3) * 4 : null,
        ligado ? 205 + (h % 4) * 6 : null, ligado ? 60 : 0]);
    }
    json(`${S}/history/${d % 7}`, {device_id: S, day: d, v: 1, vib: 'mm/s', hours: horas});
  }

  // Telemetria de 1 s, com o motor ligado em estrela-triangulo ha 25 min.
  let seq = 0;
  const inicio = Date.now() - 25 * 60 * 1000;
  setInterval(() => {
    seq++;
    const t = Date.now() / 1000, onda = Math.sin(t / 7), ts = Math.floor(t);
    const corrente = 8.78 + 0.12 * onda;
    json(`${Q}/telemetry`, {device_id: Q, seq, boot: 'a1b2c3d4e5f60718', ts, voltage: 220.2 + 0.4 * Math.sin(t / 5),
      current: corrente, power: 2890 + 40 * onda, energy: 612.43 + seq / 3600, frequency: 60.01, pf: 0.86,
      pzem_ok: true, relays: [true, false, true, false], relay_pins: [26, 27, 14, 12],
      lcd: ['IoTMotor  LIGADO', `V:220.2  I:${corrente.toFixed(2)}A`, 'P:2890W E:612.43kWh', 'Estrela-triangulo'],
      mode: 'profile_bench', profile: 'estrela_triangulo', profile_ms: Date.now() - inicio,
      start_phase: 'Triangulo', actuation: true, run_limit_s: -1, link_grace_s: 15, secure: false,
      run_s_total: 1_485_000 + 1650 + seq, starts_total: 1284, starts_today: 4, starts_hour: 1,
      session_s: Math.floor((Date.now() - inicio) / 1000), motor_running: true, reset_reason: 'power_on',
      wifi_ip: '192.168.0.41'});
    json(`${S}/telemetry`, {device_id: S, seq, ts, secure: false, vibration_mms: 1.62 + 0.08 * Math.sin(t / 3),
      vibration_axis: 'y', temperature: 41.1 + 0.2 * Math.sin(t / 11), mpu_ok: true, temperature_ok: true,
      sample_count: 1000, alarm_enabled: true, alarm_active: false, alarms_firing: [], event_sounds: false,
      buzzer_hz: 2000, motor_on: true, command_telemetry_fresh: true});
  }, 1000);

  const falso = {
    connect() {
      const eventos = new Map(), filtros = new Set();
      let fim = false;
      const c = {
        filtros, connected: false,
        on(e, f) { (eventos.get(e) || eventos.set(e, new Set()).get(e)).add(f); return c; },
        emitir(e, ...a) { if (!fim) for (const f of eventos.get(e) || []) f(...a); },
        subscribe(t, o, cb) {
          const lista = Array.isArray(t) ? t : [t];
          if (typeof o === 'function') cb = o;
          for (const f of lista) filtros.add(String(f));
          setTimeout(() => {
            cb?.(null, lista.map(topic => ({topic, qos: 0})));
            for (const [topico, texto] of retidos)
              if (lista.some(f => casa(String(f), topico))) c.emitir('message', topico, pacote(texto), {retain: true});
          }, 5);
          return c;
        },
        unsubscribe(t, o, cb) { (typeof o === 'function' ? o : cb)?.(); return c; },
        publish(t, m, o, cb) { if (typeof o === 'function') cb = o; cb?.(); return c; },
        end() { fim = true; clientes.delete(c); c.connected = false; return c; },
        removeListener() { return c; }, removeAllListeners() { return c; },
      };
      clientes.add(c);
      setTimeout(() => { c.connected = true; c.emitir('connect', {}); }, 30);
      return c;
    },
  };
  Object.defineProperty(window, 'mqtt', {configurable: true, get: () => falso, set() {}});
}

// ---- Servidor estatico do painel ------------------------------------------
const TIPOS = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.png': 'image/png',
  '.mp3': 'audio/mpeg', '.css': 'text/css', '.svg': 'image/svg+xml', '.json': 'application/json'};
const servidor = createServer((req, res) => {
  const caminho = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const arquivo = join(PAINEL, caminho === '/' ? 'index.html' : caminho);
  if (!arquivo.startsWith(PAINEL) || !existsSync(arquivo)) { res.writeHead(404).end(); return; }
  res.writeHead(200, {'content-type': TIPOS[extname(arquivo)] || 'application/octet-stream'});
  res.end(readFileSync(arquivo));
});
await new Promise(ok => servidor.listen(0, '127.0.0.1', ok));
const URL_PAINEL = `http://127.0.0.1:${servidor.address().port}/`;

// ---- Navegador pelo protocolo DevTools ------------------------------------
const exe = NAVEGADORES.find(existsSync);
if (!exe) throw Error('Edge ou Chrome nao encontrado.');
const perfil = mkdtempSync(join(tmpdir(), 'iotmotor-captura-'));
// Porta fixa e endereco pedido por HTTP: no Windows o Edge nao escreve o
// "DevTools listening on" no stderr.
const PORTA_CDP = 9300 + Math.floor(Math.random() * 500);
const nav = spawn(exe, ['--headless=new', `--remote-debugging-port=${PORTA_CDP}`, `--user-data-dir=${perfil}`,
  '--no-first-run', '--hide-scrollbars', '--mute-audio', '--force-color-profile=srgb', 'about:blank']);
let wsUrl = null;
for (let i = 0; i < 60 && !wsUrl; i++) {
  await new Promise(ok => setTimeout(ok, 250));
  try { wsUrl = (await (await fetch(`http://127.0.0.1:${PORTA_CDP}/json/version`)).json()).webSocketDebuggerUrl; } catch {}
}
if (!wsUrl) { nav.kill(); throw Error('o navegador nao abriu a porta de depuracao'); }
const ws = new WebSocket(wsUrl);
await new Promise(ok => ws.addEventListener('open', ok));
let proximo = 0;
const pendentes = new Map();
ws.addEventListener('message', ({data}) => {
  const m = JSON.parse(data);
  if (m.id && pendentes.has(m.id)) {
    const {ok, falha} = pendentes.get(m.id);
    pendentes.delete(m.id);
    m.error ? falha(Error(m.error.message)) : ok(m.result);
  }
});
const cdp = (method, params = {}, sessionId) => new Promise((ok, falha) => {
  const id = ++proximo;
  pendentes.set(id, {ok, falha});
  ws.send(JSON.stringify({id, method, params, sessionId}));
});
const espera = ms => new Promise(ok => setTimeout(ok, ms));

async function abrir({largura, altura, movel = false}) {
  const {targetId} = await cdp('Target.createTarget', {url: 'about:blank'});
  const {sessionId} = await cdp('Target.attachToTarget', {targetId, flatten: true});
  const s = (m, p) => cdp(m, p, sessionId);
  await s('Page.enable');
  await s('Emulation.setDeviceMetricsOverride', {width: largura, height: altura, deviceScaleFactor: 2, mobile: movel});
  await s('Page.addScriptToEvaluateOnNewDocument', {
    source: `(${brokerFalso})(${JSON.stringify(FW_QUADRO)}, ${JSON.stringify(FW_SENSORES)});`});
  await s('Page.navigate', {url: URL_PAINEL});
  await espera(1500);
  const js = async expr => (await s('Runtime.evaluate', {expression: expr, awaitPromise: true, returnByValue: true})).result.value;
  await js(`document.getElementById('connectBtn').click()`);
  await espera(22000);  // Graficos com uns 20 pontos.
  return {s, js, fechar: () => cdp('Target.closeTarget', {targetId})};
}

// Captura um elemento (seletor CSS) ou a janela inteira (sem seletor).
async function capturar(aba, nome, seletor, {preparar, altura} = {}) {
  if (filtro && !nome.includes(filtro)) return;
  if (preparar) { await aba.js(preparar); await espera(800); }
  let clip;
  if (seletor) {
    const r = await aba.js(`(() => { const e = document.querySelector(${JSON.stringify(seletor)});
      if (!e) return null; const r = e.getBoundingClientRect();
      return {x: r.left + scrollX, y: r.top + scrollY, width: r.width, height: r.height}; })()`);
    if (!r) throw Error(`${nome}: ${seletor} nao encontrado`);
    clip = {...r, scale: 1};
  } else {
    const [w, h] = await aba.js(`[innerWidth, ${altura ?? 'innerHeight'}]`);
    clip = {x: 0, y: 0, width: w, height: h, scale: 1};
  }
  const {data} = await aba.s('Page.captureScreenshot', {format: 'png', clip, captureBeyondViewport: true});
  writeFileSync(join(SAIDA, `${nome}.png`), Buffer.from(data, 'base64'));
  console.log(`docs/images/${nome}.png`);
}

const filtro = process.argv[2] || '';
const aba = s => `document.getElementById('tabBtn-${s}').click()`;
const secao = id => `section:has(> #${id}), section:has(#${id})`;
try {
  const desktop = await abrir({largura: 1080, altura: 675});
  await capturar(desktop, 'painel');
  await capturar(desktop, 'historico', secao('historyTitle'), {
    preparar: `[...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Temperatura')?.click()`});
  await capturar(desktop, 'dados-do-motor', secao('motorInfoTitle'), {preparar: aba('alarmes')});
  await capturar(desktop, 'guia-seguranca', secao('ensaioConfigTitle'));
  await capturar(desktop, 'guia-alarmes', secao('alarmeTitle'));
  await capturar(desktop, 'guia-dispositivos', secao('wifiTitle'), {preparar: aba('wifi')});
  await capturar(desktop, 'guia-partida', 'dialog[open]', {preparar: `${aba('painel')};
    [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Editar')?.click()`});
  await desktop.fechar();

  const celular = await abrir({largura: 390, altura: 844, movel: true});
  await celular.js(`document.getElementById('motorVisual').scrollIntoView({block: 'center'})`);
  await capturar(celular, 'celular', `.details`);
  await celular.fechar();
} finally {
  ws.close();
  nav.kill();
  servidor.close();
  await espera(500);
  try { rmSync(perfil, {recursive: true, force: true}); } catch {}
}
