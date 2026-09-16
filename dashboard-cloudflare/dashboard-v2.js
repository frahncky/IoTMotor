'use strict';
/* IoTMotor web v2: broker MQTT publico => SOMENTE ensaios sem motor ligado. */
const $ = id => document.getElementById(id);
const DEFAULT_BROKER = 'wss://test.mosquitto.org:8081';
const STORAGE_KEY = 'iotmotor_dashboard_connection_v2';
const LEGACY_KEY = 'iotmotor_dashboard_connection_v1';
const NS = 'http://www.w3.org/2000/svg';
const STALE_MS = 10000;
const LIMIT = 120;
const METRICS = [
  {key:'voltage',label:'Tensão',unit:'V',digits:1,color:'#63c6e6',group:'eletrica'},
  {key:'current',label:'Corrente',unit:'A',digits:2,color:'#f5bc67',group:'eletrica'},
  {key:'power',label:'Potência ativa',unit:'W',digits:1,color:'#ef9d70',group:'eletrica'},
  {key:'apparent',label:'Potência aparente',unit:'VA',digits:1,color:'#66d7bd',group:'eletrica'},
  {key:'reactive',label:'Potência reativa',unit:'VAr',digits:1,color:'#91a4ef',group:'eletrica'},
  {key:'pf',label:'Fator de potência',unit:'',digits:2,color:'#86d5a8',group:'eletrica'},
  {key:'frequency',label:'Frequência',unit:'Hz',digits:2,color:'#83c9ff',group:'eletrica'},
  {key:'energy',label:'Energia',unit:'kWh',digits:3,color:'#c8cc89',group:'eletrica'},
  {key:'vibration',label:'Vibração (RMS)',unit:'g',digits:3,color:'#e3adca',group:'mecanica'},
  {key:'temperature',label:'Temperatura',unit:'°C',digits:1,color:'#fd987f',group:'mecanica'}
];
const state = {
  client:null, generation:0, connected:false, subscribed:false,
  config:{broker:DEFAULT_BROKER,prefix:'iotmotor',device:'esp32-01'},
  history:[], sample:null, lastAt:0, messages:0, status:'—',
  group:'todos', pending:null, sequence:null
};
const text = (id, value) => { $(id).textContent = String(value); };
const number = value => {
  if (value === null || value === undefined || value === '') return null;
  const n = typeof value === 'string' ? Number(value.replace(',','.')) : Number(value);
  return Number.isFinite(n) ? n : null;
};
const fromAliases = (src, names) => {
  for (const key of names) { const n = number(src[key]); if (n !== null) return n; }
  return null;
};
function normalizeTelemetry(packet) {
  if (!packet || typeof packet !== 'object' || Array.isArray(packet)) return null;
  const src = packet.data && typeof packet.data === 'object' ? packet.data : packet;
  const s = {
    voltage:fromAliases(src,['voltage','tensao','v']),
    current:fromAliases(src,['current','corrente','i']),
    power:fromAliases(src,['power','potencia','w']),
    pf:fromAliases(src,['pf','power_factor','fator_potencia','fp']),
    frequency:fromAliases(src,['frequency','frequencia','hz']),
    energy:fromAliases(src,['energy','energy_kwh','energia','kwh']),
    vibration:fromAliases(src,['vibration','vibracao','vib']),
    temperature:fromAliases(src,['temperature','temperatura','temp']),
    motorOn:typeof src.motor_on === 'boolean' ? src.motor_on : null,
    benchArmed:src.bench_armed === true,
    demo:src.demo === true || packet.demo === true || src.data_source === 'simulated',
    mode:typeof src.mode === 'string' ? src.mode : '—',
    seq:number(src.seq)
  };
  s.apparent = s.voltage === null || s.current === null ? null : s.voltage * s.current;
  s.reactive = s.apparent === null ? null :
    s.power !== null ? Math.sqrt(Math.max(0,s.apparent*s.apparent-s.power*s.power)) :
    s.pf !== null ? s.apparent * Math.sqrt(Math.max(0,1-s.pf*s.pf)) : null;
  if (!METRICS.some(m => s[m.key] !== null) && s.motorOn === null) return null;
  return s;
}
function safeConfig(input) {
  const broker = String(input.broker || '').trim();
  const prefix = String(input.prefix || '').trim().replace(/^\/+|\/+$/g,'');
  const device = String(input.device || '').trim();
  let url;
  try { url = new URL(broker); } catch { throw Error('URL WSS inválida.'); }
  if (url.protocol !== 'wss:' || !url.hostname || url.username || url.password || url.hash || url.search)
    throw Error('Informe apenas uma URL wss:// válida, sem credenciais ou parâmetros.');
  if (!/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(prefix)) throw Error('Prefixo de tópicos inválido.');
  if (!/^[a-zA-Z0-9_-]+$/.test(device)) throw Error('ID do ESP32 inválido.');
  return {broker:url.toString(),prefix,device};
}
function restore() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || localStorage.getItem(LEGACY_KEY) || 'null');
    if (saved && typeof saved === 'object') {
      const config = safeConfig(saved);
      if (config.broker === 'wss://broker.hivemq.com:8884/mqtt') config.broker = DEFAULT_BROKER;
      state.config = config;
    }
  } catch { /* configuracao anterior malformada nao impede abrir a pagina */ }
  $('broker').value=state.config.broker;
  $('prefix').value=state.config.prefix;
  $('device').value=state.config.device;
}
function diagnostic(message) { text('diagnostic',message); }
function pill(message,kind='') {
  text('connectionText',message);
  $('connection').className=`pill ${kind}`.trim();
  $('connectBtn').textContent=state.client?'Desconectar':'Conectar ao MQTT';
}
function live() { return state.connected && state.subscribed && state.lastAt && Date.now()-state.lastAt<STALE_MS; }
function topic(kind) { return `${state.config.prefix}/${state.config.device}/${kind}`; }
function updateControls() {
  const current=live();
  $('startBtn').disabled=!(current && state.sample && state.sample.benchArmed && !state.pending);
  $('stopBtn').disabled=!state.connected || !!state.pending;
  $('starBtn').disabled=true; // firmware de um rele NAO possui intertravamento estrela-triangulo
  text('armValue',current?(state.sample.benchArmed?'Jumper local habilitado':'Jumper local ausente'):'Sem confirmação recente');
  text('motorValue',current && state.sample.motorOn!==null?(state.sample.motorOn?'Saída ligada':'Saída desligada'):'Estado não confirmado');
  text('modeValue',current?state.sample.mode:'—');
}
function node(tag,attrs={},value) {
  const n=document.createElementNS(NS,tag);
  for (const [key,v] of Object.entries(attrs)) n.setAttribute(key,String(v));
  if (value!==undefined) n.textContent=String(value);
  return n;
}
function chart(svg, metric) {
  svg.replaceChildren();
  const samples=state.history.filter(s=>s[metric.key]!==null);
  if (!samples.length) {svg.append(node('text',{x:320,y:100,'text-anchor':'middle',class:'empty'},'Sem leitura deste sensor'));return;}
  const values=samples.map(s=>s[metric.key]);
  let min=Math.min(...values),max=Math.max(...values);
  const margin=Math.max((max-min)*.14,Math.abs(max)*.01,.01);
  min-=margin;max+=margin;
  for(let k=0;k<4;k++) {
    const y=18+(158*k/3);
    svg.append(node('line',{x1:49,y1:y,x2:635,y2:y,class:'gridline'}));
    svg.append(node('text',{x:43,y:y+4,'text-anchor':'end'},(max-(max-min)*k/3).toFixed(metric.digits>2?2:metric.digits)));
  }
  const coords=values.map((v,i)=>{
    const x=52+(values.length===1?290:580*i/(values.length-1));
    const y=176-(v-min)/(max-min)*158;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');
  svg.append(node('polyline',{points:coords,stroke:metric.color}));
  svg.append(node('text',{x:52,y:207},'Mais antigo'));
  svg.append(node('text',{x:635,y:207,'text-anchor':'end'},'Mais recente'));
}
function renderCards() {
  for(const m of METRICS) {
    const value=state.sample && state.sample[m.key]!==null?state.sample[m.key].toFixed(m.digits):'—';
    text(`value-${m.key}`,value);
    text(`hint-${m.key}`,state.sample && state.sample[m.key]!==null?
      (state.sample.demo?'Simulado · não é medição':'Leitura recebida do ESP32'):'Sem leitura disponível');
  }
  text('dataSource',!state.sample?'Aguardando dados':state.sample.demo?'DADOS SIMULADOS — somente teste':'SENSORES — confira calibração');
  $('dataSource').className=state.sample && state.sample.demo?'source demo':'source';
  text('sampleAge',state.lastAt?`Última mensagem: ${new Date(state.lastAt).toLocaleTimeString('pt-BR')} ${live()?'· atual':'· desatualizada'}`:'Nenhuma amostra recebida');
  text('messageCount',state.messages);
  $('exportBtn').disabled=state.history.length===0;
  updateControls();
  renderCharts();
}
function buildCards() {
  const grid=$('metrics');
  for(const m of METRICS) {
    const card=document.createElement('article');card.className='metric panel';
    const label=document.createElement('div');label.className='metric-label';label.textContent=m.label;
    const value=document.createElement('div');value.className='metric-value';
    const numberNode=document.createElement('span');numberNode.id=`value-${m.key}`;numberNode.textContent='—';
    const unit=document.createElement('span');unit.className='unit';unit.textContent=m.unit;
    value.append(numberNode,unit);
    const hint=document.createElement('small');hint.id=`hint-${m.key}`;hint.textContent='Sem leitura disponível';
    card.append(label,value,hint);grid.append(card);
  }
}
function renderCharts() {
  const root=$('plots');root.replaceChildren();
  for(const m of METRICS.filter(m=>state.group==='todos'||m.group===state.group)) {
    const card=document.createElement('article');card.className='panel chart-card';
    const title=document.createElement('h3');title.textContent=`${m.label}${m.unit?` (${m.unit})`:''}`;
    const svg=node('svg',{viewBox:'0 0 650 215',class:'chart',role:'img','aria-label':`Gráfico de ${m.label}`});
    chart(svg,m);card.append(title,svg);root.append(card);
  }
}
function clearSession() {
  state.history=[];state.sample=null;state.lastAt=0;state.messages=0;
  state.status='—';state.subscribed=false;state.pending=null;state.sequence=null;
  text('statusValue','—');text('commandFeedback','Nenhum comando enviado.');
  renderCards();
}
function disconnect() {
  const old=state.client;state.generation++;state.client=null;state.connected=false;state.subscribed=false;
  if(old)old.end(true);
  clearSession();pill('Desconectado');diagnostic('Desconectado.');
}
function connect() {
  let config;
  try{config=safeConfig({broker:$('broker').value,prefix:$('prefix').value,device:$('device').value});}
  catch(e){diagnostic(e.message);return;}
  if(!window.mqtt || typeof window.mqtt.connect!=='function'){
    pill('Biblioteca indisponível','error');diagnostic('MQTT.js não carregou. Verifique o acesso a cdnjs.cloudflare.com.');return;
  }
  if(state.client)disconnect();
  state.config=config;
  try{localStorage.setItem(STORAGE_KEY,JSON.stringify(config));}catch{}
  text('brokerValue',config.broker);text('deviceValue',config.device);
  const generation=++state.generation;
  pill('Conectando…','wait');diagnostic(`Abrindo ${config.broker} e aguardando a assinatura de ${topic('telemetry')}.`);
  let client;
  try{client=window.mqtt.connect(config.broker,{
    clientId:`iotmotor_web_${Math.random().toString(36).slice(2,12)}`,clean:true,
    protocolVersion:4,reconnectPeriod:4000,connectTimeout:10000,keepalive:30,resubscribe:true
  });}catch(e){pill('Erro','error');diagnostic(e.message);return;}
  state.client=client;clearSession();pill('Conectando…','wait');
  const active=()=>state.client===client && generation===state.generation;
  client.on('connect',()=>{
    if(!active())return;
    state.connected=true;pill('Broker conectado','live');
    client.subscribe([topic('telemetry'),topic('status'),topic('capabilities')],{qos:0},(e)=>{
      if(!active())return;
      state.subscribed=!e;
      diagnostic(e?`Falha ao assinar tópicos: ${e.message}`:
        `MQTT conectado; aguardando novas mensagens em ${topic('telemetry')}.`);
      updateControls();
    });
  });
  client.on('message',(destination,payload,packet)=>{
    if(!active())return;
    if(destination===topic('status')){
      state.status=payload.toString('utf8').slice(0,90);text('statusValue',state.status);
      if(!state.lastAt)diagnostic('Status recebido; status retido não prova telemetria atual.');
      return;
    }
    if(destination===topic('capabilities'))return;
    if(destination!==topic('telemetry'))return;
    // O sketch antigo marcava telemetria como retained por engano.
    // Descarta SOMENTE a copia historica entregue na assinatura.
    if(packet && packet.retain===true){diagnostic('Telemetria retida antiga ignorada; aguardando publicação nova.');return;}
    let parsed;try{parsed=JSON.parse(payload.toString('utf8'));}
    catch{diagnostic('Telemetria recebida, mas o JSON é inválido.');return;}
    if(parsed.device_id!==config.device){diagnostic('Telemetria com device_id diferente do selecionado.');return;}
    const next=normalizeTelemetry(parsed);
    if(!next){diagnostic('JSON sem grandezas reconhecidas.');return;}
    state.sample=next;state.lastAt=Date.now();state.messages++;
    state.history.push({...next,receivedAt:new Date(state.lastAt).toISOString()});
    if(state.history.length>LIMIT)state.history.shift();
    if(state.pending && state.lastAt>state.pending.at && next.motorOn===state.pending.target){
      text('commandFeedback',`ESP32 informou saída ${next.motorOn?'ligada':'desligada'} após o comando.`);
      state.pending=null;
    }
    diagnostic(`Telemetria atual recebida de ${config.device} (seq ${next.seq??'—'}).`);
    renderCards();
  });
  client.on('reconnect',()=>{if(!active())return;state.connected=false;state.subscribed=false;pill('Reconectando…','wait');updateControls();});
  client.on('offline',()=>{if(!active())return;state.connected=false;state.subscribed=false;pill('Broker indisponível','error');diagnostic('Sem conexão WSS: verifique porta 8081, rede e disponibilidade do broker.');updateControls();});
  client.on('error',e=>{if(active())diagnostic(`Erro MQTT: ${String(e.message||e).slice(0,150)}`);});
  client.on('close',()=>{if(!active())return;state.connected=false;state.subscribed=false;pill('Conexão encerrada','error');updateControls();});
}
function sendCommand(command,mode) {
  if(!state.client||!state.connected||state.pending)return;
  if(command==='start'){
    if(!live()||!state.sample||!state.sample.benchArmed)return;
    if(!window.confirm('TESTE DE BANCADA: confirme que NÃO há motor nem contator ligado ao relé e que o jumper local GPIO32–GND está instalado. Enviar partida direta?'))return;
  }
  const payload=JSON.stringify({device_id:state.config.device,command,mode,origin:'web_bench',timestamp:new Date().toISOString()});
  const target=command==='start';
  state.pending={target,at:Date.now()};
  text('commandFeedback',`Enviando ${command==='start'?'partida direta':'parada'}; aguardando retorno do ESP32…`);
  updateControls();
  state.client.publish(topic('command'),payload,{qos:0,retain:false},e=>{
    if(e){state.pending=null;text('commandFeedback',`Falha ao enviar: ${e.message}`);updateControls();}
  });
}
function exportCsv(){
  if(!state.history.length)return;
  const keys=METRICS.map(m=>m.key);
  const rows=[['received_at','demo','bench_armed','motor_on','mode',...keys].join(',')];
  for(const s of state.history)rows.push([s.receivedAt,s.demo,s.benchArmed,s.motorOn,s.mode,...keys.map(k=>s[k]??'')].join(','));
  const blob=new Blob(['\ufeff'+rows.join('\r\n')],{type:'text/csv;charset=utf-8'});
  const url=URL.createObjectURL(blob);const a=document.createElement('a');
  a.href=url;a.download=`iotmotor-${state.config.device}-${new Date().toISOString().slice(0,10)}.csv`;a.click();
  setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function init(){
  restore();buildCards();renderCards();
  text('brokerValue',state.config.broker);text('deviceValue',state.config.device);
  $('connectBtn').addEventListener('click',()=>state.client?disconnect():connect());
  $('connectionForm').addEventListener('submit',e=>{e.preventDefault();connect();});
  $('startBtn').addEventListener('click',()=>sendCommand('start','direct'));
  $('stopBtn').addEventListener('click',()=>sendCommand('stop','manual_stop'));
  $('exportBtn').addEventListener('click',exportCsv);
  for(const btn of document.querySelectorAll('[data-group]'))btn.addEventListener('click',()=>{
    state.group=btn.dataset.group;
    for(const b of document.querySelectorAll('[data-group]'))b.setAttribute('aria-pressed',String(b===btn));
    renderCharts();
  });
  setInterval(()=>{
    if(state.pending&&Date.now()-state.pending.at>6000){
      text('commandFeedback','Sem confirmação do ESP32. Verifique a placa; não presuma que a saída está desligada.');
      state.pending=null;
    }
    if(state.lastAt && !live() && state.connected)diagnostic('Broker conectado, mas sem telemetria recente do ESP32. Verifique a rede e o firmware.');
    if(state.lastAt)text('sampleAge',`Última mensagem: ${new Date(state.lastAt).toLocaleTimeString('pt-BR')} ${live()?'· atual':'· desatualizada'}`);
    updateControls();
  },1000);
}
if(typeof document!=='undefined')init();
if(typeof module!=='undefined'&&module.exports)module.exports={normalizeTelemetry,safeConfig,METRICS};
