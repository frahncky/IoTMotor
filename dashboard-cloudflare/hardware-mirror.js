'use strict';
/* Espelho SOMENTE LEITURA. Nao publica MQTT; nenhum clique aciona reles. */
(() => {
  const $ = id => document.getElementById(id);
  const DEFAULT = {broker:'wss://test.mosquitto.org:8081',prefix:'iotmotor',device:'esp32-01'};
  const SAVE = 'iotmotor_hardware_monitor_v1';
  const PINS = [19,18,23,27];
  const STALE_MS = 10000;
  const state = {config:{...DEFAULT},client:null,generation:0,connected:false,lastAt:0,count:0,sample:null};
  function message(value){$('diagnostic').textContent=value;}
  function badge(value,kind=''){$('connection').textContent=value;$('connection').className=`badge ${kind}`.trim();}
  function numeric(value){if(value===null||value===undefined||value==='')return null;const n=Number(value);return Number.isFinite(n)?n:null;}
  function pad(text){return String(text??'').slice(0,20).padEnd(20,' ');}
  function left(value,size){return String(value).padStart(size,' ');}
  function fresh(){return state.connected&&!!state.lastAt&&Date.now()-state.lastAt<STALE_MS;}
  function parse(raw){
    let packet;
    try{packet=JSON.parse(raw);}catch{return null;}
    if(!packet||typeof packet!=='object'||Array.isArray(packet))return null;
    const data=packet.data&&typeof packet.data==='object'&&!Array.isArray(packet.data)?packet.data:packet;
    if(String(packet.device_id||data.device_id||'')!==state.config.device)return null;
    const leds=Array.isArray(data.relays)&&data.relays.length===4&&data.relays.every(v=>typeof v==='boolean')?data.relays:
      Array.isArray(data.relay_states)&&data.relay_states.length===4&&data.relay_states.every(v=>typeof v==='boolean')?data.relay_states:null;
    const lines=Array.isArray(data.lcd)&&data.lcd.length===4&&data.lcd.every(v=>typeof v==='string')?data.lcd:
      Array.isArray(data.lcd_lines)&&data.lcd_lines.length===4&&data.lcd_lines.every(v=>typeof v==='string')?data.lcd_lines:null;
    const mode=typeof data.mode==='string'?data.mode:'';
    const machine=typeof data.state==='string'?data.state:'';
    const sensorOk=data.pzem_ok===true||data.sensor_ok===true;
    const voltage=numeric(data.voltage),current=numeric(data.current),power=numeric(data.power),energy=numeric(data.energy);
    return {leds,lines,mode,machine,sensorOk,voltage,current,power,energy,ip:typeof data.wifi_ip==='string'?data.wifi_ip:null,pins:data.relay_pins};
  }
  function inferRelays(s){
    if(s.leds)return {values:s.leds,exact:true};
    if(s.machine==='parado')return {values:[false,false,false,false],exact:false};
    if(s.machine==='estrela')return {values:[true,true,false,true],exact:false};
    if(s.machine==='tempo_morto')return {values:[true,false,false,true],exact:false};
    if(s.machine==='rodando'&&(s.mode==='direct'||s.mode==='star_delta'))return {values:[true,false,true,true],exact:false};
    return {values:null,exact:false};
  }
  function previewLcd(s,relays){
    if(s.lines)return {rows:s.lines.map(pad),exact:true};
    const first=s.ip?`IP:${s.ip}`:'IP: nao informado';
    const second=s.sensorOk&&s.voltage!==null&&s.current!==null?
      `V:${left(s.voltage.toFixed(1),5)}  I:${left(s.current.toFixed(2),6)}A`:'PZEM sem leitura';
    const third=s.sensorOk&&s.power!==null&&s.energy!==null?
      `P:${left(s.power.toFixed(0),4)}W E:${left(s.energy.toFixed(2),7)}kWh`:'';
    const names={estrela:'ESTRELA',tempo_morto:'COMUTA ',rodando:'RODANDO',parado:'PARADO '};
    const flags=relays?relays.map((on,i)=>on?String(i+1):'-').join(''):'????';
    const fourth=`${names[s.machine]||'SEM SINAL'} ${flags} MQ`;
    return {rows:[first,second,third,fourth].map(pad),exact:false};
  }
  function render(){
    const live=fresh(),s=live?state.sample:null;
    const info=s?inferRelays(s):{values:null,exact:false};
    $('relaySource').textContent=!s?'Sem telemetria recente.':info.exact?'Estados lógicos informados pelo firmware (sem feedback físico).':'Estados previstos pela etapa do acionamento; firmware ainda não publica cada saída.';
    info.values?.forEach((on,i)=>{});
    for(let i=0;i<4;i++){
      const on=info.values?.[i];
      $('relay'+i).className='relay '+(on===undefined?'unknown':on?'on':'off');
      $('relayText'+i).textContent=on===undefined?'Sem sinal':on?'Comando LIGADO':'Comando DESLIGADO';
    }
    const screen=s?previewLcd(s,info.values):{rows:['IoTMotor Modulo 1','Sem sinal recente','',''].map(pad),exact:false};
    $('lcdText').textContent=screen.rows.join('\n');
    $('lcdSource').textContent=screen.exact?'Espelho do buffer de 4 linhas enviado pelo ESP32 (não é leitura ótica do LCD).':'Prévia calculada: o firmware atual não transmite as linhas reais do LCD.';
    $('lastSeen').textContent=state.lastAt?`Última mensagem: ${new Date(state.lastAt).toLocaleTimeString('pt-BR')}${live?'':' · desatualizada'}`:'Nenhuma telemetria recebida.';
    $('stateValue').textContent=s?.machine||'—';$('modeValue').textContent=s?.mode||'—';
    $('pzemValue').textContent=!s?'Sem sinal':s.sensorOk?'Leitura válida':'Sem leitura válida';
    $('messageCount').textContent=state.count;
  }
  function getConfig(){
    const broker=$('broker').value.trim(),prefix=$('prefix').value.trim().replace(/^\/+|\/+$/g,''),device=$('device').value.trim();
    let url;try{url=new URL(broker);}catch{throw Error('URL inválida. Use WSS.');}
    if(url.protocol!=='wss:'||!url.hostname||url.username||url.password||url.hash||url.search)throw Error('Use wss:// sem usuário, senha ou parâmetros.');
    if(!/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(prefix)||!/^[a-zA-Z0-9_-]+$/.test(device))throw Error('Prefixo ou ID inválido.');
    return {broker:url.toString(),prefix,device};
  }
  function connect(){
    let config;try{config=getConfig();}catch(error){message(error.message);return;}
    if(!window.mqtt?.connect){badge('Biblioteca indisponível','error');message('MQTT.js não carregou da CDN.');return;}
    if(state.client)state.client.end(true);
    const gen=++state.generation;state.config=config;state.connected=false;state.lastAt=0;state.sample=null;state.count=0;render();
    try{localStorage.setItem(SAVE,JSON.stringify(config));}catch{}
    const client=window.mqtt.connect(config.broker,{clientId:`iotmotor_lcd_${Math.random().toString(36).slice(2,12)}`,clean:true,reconnectPeriod:4000,connectTimeout:10000,protocolVersion:4,keepalive:30});
    state.client=client;badge('Conectando…');message(`Conectando a ${config.broker}…`);
    const active=()=>state.generation===gen&&state.client===client;
    client.on('connect',()=>{if(!active())return;state.connected=true;badge('Broker conectado','ok');
      client.subscribe([`${config.prefix}/${config.device}/telemetry`,`${config.prefix}/${config.device}/status`],{qos:0},err=>message(err?'Falha ao assinar tópicos: '+err.message:'Broker conectado. Aguardando dados do ESP32-01.'));render();});
    client.on('message',(topic,payload,packet)=>{
      if(!active())return;
      if(topic===`${config.prefix}/${config.device}/status`){$('statusValue').textContent=payload.toString('utf8').slice(0,65);return;}
      if(topic!==`${config.prefix}/${config.device}/telemetry`||packet?.retain===true)return;
      const parsed=parse(payload.toString('utf8'));
      if(!parsed){message('Telemetria inválida ou de outro device_id.');return;}
      state.sample=parsed;state.lastAt=Date.now();state.count++;render();
      message(parsed.lines&&parsed.leds?'Recebendo espelho do LCD e estados individuais dos quatro contatores.':'Recebendo telemetria; para espelho exato o firmware precisa publicar lcd e relays.');
    });
    client.on('reconnect',()=>{if(!active())return;state.connected=false;badge('Reconectando…');render();});
    client.on('offline',()=>{if(!active())return;state.connected=false;badge('Broker indisponível','error');message('Não foi possível conectar via WebSocket seguro.');render();});
    client.on('error',e=>{if(active())message('Erro MQTT: '+String(e.message||e).slice(0,140));});
    client.on('close',()=>{if(!active())return;state.connected=false;badge('Conexão encerrada','error');render();});
  }
  try{const stored=JSON.parse(localStorage.getItem(SAVE)||'null');if(stored&&typeof stored==='object'){
    if(typeof stored.broker==='string')DEFAULT.broker=stored.broker;
    if(typeof stored.prefix==='string')DEFAULT.prefix=stored.prefix;
    if(typeof stored.device==='string')DEFAULT.device=stored.device;
  }}catch{}
  $('broker').value=DEFAULT.broker;$('prefix').value=DEFAULT.prefix;$('device').value=DEFAULT.device;
  $('configForm').addEventListener('submit',event=>{event.preventDefault();connect();});
  render();setInterval(render,1500);
})();
