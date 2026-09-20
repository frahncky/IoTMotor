'use strict';
// IoTMotor: esp32-01 PZEM + comandos; esp32-02 MPU6050/DS18B20 (somente leitura).
const $=id=>document.getElementById(id);
const STORE='iotmotor_dashboard_dual_v1';
const DEFAULT={broker:'wss://test.mosquitto.org:8081',prefix:'iotmotor',commandDevice:'esp32-01',sensorDevice:'esp32-02'};
const METRICS=[
 {key:'voltage',label:'Tensão',unit:'V',digits:1,group:'eletrica',color:'#65c7e8',source:'command'},
 {key:'current',label:'Corrente',unit:'A',digits:2,group:'eletrica',color:'#ffc46a',source:'command'},
 {key:'power',label:'Potência ativa',unit:'W',digits:1,group:'eletrica',color:'#e6a179',source:'command'},
 {key:'apparent',label:'Potência aparente',unit:'VA',digits:1,group:'eletrica',color:'#69d3b7',source:'command'},
 {key:'reactive',label:'Potência reativa',unit:'VAr',digits:1,group:'eletrica',color:'#a2adf4',source:'command'},
 {key:'pf',label:'Fator de potência',unit:'',digits:2,group:'eletrica',color:'#83d8a2',source:'command'},
 {key:'frequency',label:'Frequência',unit:'Hz',digits:2,group:'eletrica',color:'#95c8ff',source:'command'},
 {key:'energy',label:'Energia',unit:'kWh',digits:3,group:'eletrica',color:'#d4cf87',source:'command'},
 {key:'vibration',label:'Vibração RMS',unit:'g',digits:3,group:'mecanica',color:'#e6b2d4',source:'sensor'},
 {key:'temperature',label:'Temperatura',unit:'°C',digits:1,group:'mecanica',color:'#f69d84',source:'sensor'}
];
const alias={voltage:['voltage','tensao','v'],current:['current','corrente','i'],power:['power','potencia','w'],pf:['pf','power_factor','fator_potencia','fp'],frequency:['frequency','frequencia','hz'],energy:['energy','energy_kwh','energia','kwh'],vibration:['vibration','vibracao','vib'],temperature:['temperature','temperatura','temp']};
const state={config:{...DEFAULT},client:null,generation:0,connected:false,subscribed:false,group:'todos',
 command:{sample:null,at:0,count:0,status:'—'},sensor:{sample:null,at:0,count:0,status:'—'},
 series:Object.fromEntries(METRICS.map(m=>[m.key,[]])),records:[],pending:null};
function numeric(v){if(v===null||v===undefined||v==='')return null;const n=Number(typeof v==='string'?v.replace(',','.'):v);return Number.isFinite(n)?n:null;}
function field(source,keys){for(const key of keys){const n=numeric(source[key]);if(n!==null)return n;}return null;}
function parseTelemetry(json){
 if(!json||typeof json!=='object'||Array.isArray(json))return null;
 const source=json.data&&typeof json.data==='object'&&!Array.isArray(json.data)?json.data:json;
 const result={deviceId:String(json.device_id||source.device_id||''),demo:json.demo===true||source.demo===true||source.data_source==='simulated',
  dataSource:String(json.data_source||source.data_source||'não informada'),seq:numeric(source.seq),
  benchArmed:source.bench_armed===true,motorOn:typeof source.motor_on==='boolean'?source.motor_on:null,
  mode:typeof source.mode==='string'?source.mode:'—',phase:typeof source.start_phase==='string'?source.start_phase:null,vibrationPeak:numeric(source.vibration_peak),
  relays:Array.isArray(source.relays)&&source.relays.length===4&&source.relays.every(v=>typeof v==='boolean')?source.relays:null};
 for(const [name,keys]of Object.entries(alias))result[name]=field(source,keys);
 result.apparent=result.voltage!==null&&result.current!==null?result.voltage*result.current:null;
 result.reactive=result.apparent===null?null:result.power!==null?
 Math.sqrt(Math.max(0,result.apparent**2-result.power**2)):
 result.pf!==null?result.apparent*Math.sqrt(Math.max(0,1-result.pf**2)):null;
 return result;
}
function validateConfig(input){
 const broker=String(input.broker||'').trim(),prefix=String(input.prefix||'').trim().replace(/^\/+|\/+$/g,'');
 const commandDevice=String(input.commandDevice||'').trim(),sensorDevice=String(input.sensorDevice||'').trim();
 let url;try{url=new URL(broker);}catch{throw Error('URL WSS inválida.');}
 if(url.protocol!=='wss:'||!url.hostname||url.username||url.password||url.search||url.hash)throw Error('Informe apenas uma URL wss:// válida, sem credenciais.');
 if(!/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(prefix))throw Error('Prefixo de tópicos inválido.');
 if(!/^[a-zA-Z0-9_-]+$/.test(commandDevice)||!/^[a-zA-Z0-9_-]+$/.test(sensorDevice)||commandDevice===sensorDevice)throw Error('Informe IDs distintos e válidos para os dois ESP32.');
 return {broker:url.toString(),prefix,commandDevice,sensorDevice};
}
function text(id,value){$(id).textContent=String(value);}
function diag(message){text('diagnostic',message);}
function pill(message,kind=''){text('connectionText',message);$('connection').className=`pill ${kind}`.trim();$('connectBtn').textContent=state.client?'Desconectar':'Conectar ao MQTT';}
function topic(device,kind){return `${state.config.prefix}/${device}/${kind}`;}
function freshness(which){return state.connected&&state.subscribed&&state[which].at>0&&Date.now()-state[which].at<10000;}
// Conexao do dispositivo: telemetria recente prevalece; senao usa o status retido/LWT mais novo.
function deviceConnection({brokerOk,status,statusAt=0,at=0,now=Date.now()}){
 if(!brokerOk)return {label:'broker desconectado',kind:''};
 const fresh=at>0&&now-at<10000,st=String(status||'').trim().toLowerCase();
 if(st==='offline'&&statusAt>=at)return {label:'desconectado',kind:'error'};
 if(fresh)return {label:'conectado',kind:'live'};
 if(st==='offline')return {label:'desconectado',kind:'error'};
 if(st==='online')return {label:at?'online · sem dados há mais de 10 s':'online · aguardando dados',kind:'wait'};
 return {label:at?'sem dados há mais de 10 s':'sem sinal',kind:at?'error':''};
}
function renderDevice(id,which,name){
 const s=state[which],info=deviceConnection({brokerOk:state.connected&&state.subscribed,status:s.status,statusAt:s.statusAt,at:s.at});
 const demo=info.kind==='live'&&s.sample?.demo?' · SIMULADO':'';
 text(id,`${name} · ${info.label}${demo}`);$(id).className=`source ${info.kind}`.trim();
 $(id).title=s.at?`Última telemetria: ${new Date(s.at).toLocaleTimeString('pt-BR')}`:'Nenhuma telemetria recebida';
}
function valueFor(metric){const source=state[metric.source];return freshness(metric.source)&&source.sample?source.sample[metric.key]:null;}
function updateControl(){
 const active=freshness('command');const s=state.command.sample;
 if(!window.iotmotorLocalControls) $('startBtn').disabled=true; // Local controller owns this button.
 if(!window.iotmotorLocalControls) $('stopBtn').disabled=true; // Never override local stop.
 const relays=active&&Array.isArray(s?.relays)?s.relays:null;
 $('motorValue').replaceChildren(...[0,1,2,3].map(i=>{
  const on=relays?.[i],chip=document.createElement('span');
  chip.className=`cnt ${on===undefined?'':on?'on':'off'}`.trim();
  chip.textContent=`CNT ${i+1} · ${on===undefined?'—':on?'ligado':'desligado'}`;
  return chip;
 }));
 text('modeValue',active&&s.phase?s.phase:'—');
}
function svg(tag,attrs={},content){const n=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const [key,v]of Object.entries(attrs))n.setAttribute(key,String(v));if(content!==undefined)n.textContent=String(content);return n;}
function drawChart(target,metric){
 const values=state.series[metric.key].map(entry=>entry.v);
 target.replaceChildren();
 if(!values.length){target.append(svg('text',{x:320,y:105,'text-anchor':'middle',class:'empty'},'Sem leitura disponível'));return;}
 let min=Math.min(...values),max=Math.max(...values);const pad=Math.max((max-min)*.12,Math.abs(max)*.01,.01);min-=pad;max+=pad;
 for(let i=0;i<4;i++){const y=20+160*i/3;target.append(svg('line',{x1:53,x2:633,y1:y,y2:y,class:'gridline'}));target.append(svg('text',{x:45,y:y+4,'text-anchor':'end'},(max-(max-min)*i/3).toFixed(metric.digits>2?2:metric.digits)));}
 const points=values.map((v,i)=>`${(56+(values.length===1?280:570*i/(values.length-1))).toFixed(1)},${(180-(v-min)/(max-min)*160).toFixed(1)}`).join(' ');
 target.append(svg('polyline',{points,stroke:metric.color}));target.append(svg('text',{x:56,y:209},'Mais antigo'));target.append(svg('text',{x:631,y:209,'text-anchor':'end'},'Mais recente'));
}
function renderCharts(){const root=$('plots');root.replaceChildren();for(const metric of METRICS.filter(m=>state.group==='todos'||m.group===state.group)){
 const article=document.createElement('article');article.className='panel chart-card';
 const heading=document.createElement('h3');heading.textContent=`${metric.label}${metric.unit?' ('+metric.unit+')':''}`;
 const graphic=svg('svg',{viewBox:'0 0 650 215',class:'chart',role:'img','aria-label':`Gráfico de ${metric.label}`});
 drawChart(graphic,metric);article.append(heading,graphic);root.append(article);
}}
function buildCards(){const root=$('metrics');for(const m of METRICS){
 const item=document.createElement('article');item.className='panel metric';
 const label=document.createElement('div');label.className='metric-label';label.textContent=m.label;
 const value=document.createElement('div');value.className='metric-value';
 const number=document.createElement('span');number.id=`value-${m.key}`;number.textContent='—';
 const unit=document.createElement('span');unit.className='unit';unit.textContent=m.unit;value.append(number,unit);
 const detail=document.createElement('small');detail.id=`hint-${m.key}`;detail.textContent='Sem leitura';item.append(label,value,detail);root.append(item);
}}
function render(){
 for(const m of METRICS){const value=valueFor(m),source=state[m.source];text(`value-${m.key}`,value===null?'—':value.toFixed(m.digits));
 text(`hint-${m.key}`,value===null?'':source.sample.demo?'Simulado — não é medição':m.source==='command'?'ESP32 PZEM-004T':'ESP32-S3 sensores');}
 renderDevice('pzemState','command',`${state.config.commandDevice} (PZEM e contatores)`);
 renderDevice('sensorState','sensor',`${state.config.sensorDevice} (S3 sensores)`);
 text('commandAge',state.command.at?new Date(state.command.at).toLocaleTimeString('pt-BR'):'—');
 text('sensorAge',state.sensor.at?new Date(state.sensor.at).toLocaleTimeString('pt-BR'):'—');
 $('exportBtn').disabled=!state.records.length;updateControl();renderCharts();
}
function reset(){state.command={sample:null,at:0,count:0,status:'—',statusAt:0};state.sensor={sample:null,at:0,count:0,status:'—',statusAt:0};
 state.series=Object.fromEntries(METRICS.map(m=>[m.key,[]]));state.records=[];state.pending=null;state.subscribed=false;
 text('commandFeedback','Nenhum comando enviado.');render();}
function disconnect(){const old=state.client;state.generation++;state.client=null;state.connected=false;state.subscribed=false;if(old)old.end(true);
 window.iotmotorRemoteControls?.disconnect?.();  // Botoes Ligar/Desligar param junto.
 window.iotmotorWifi?.disconnect?.();  // Aba Wi-Fi tambem.
 window.iotmotorAlarme?.disconnect?.();window.iotmotorPerfis?.disconnect?.();
 reset();pill('Desconectado');diag('Desconectado.');}
function ingest(which,raw,packet){
 if(packet?.retain===true){diag(`Telemetria retida antiga de ${which==='command'?'ESP32 PZEM':'ESP32-S3'} ignorada.`);return false;}
 let json;try{json=JSON.parse(raw);}catch{diag('Mensagem MQTT recebida, mas JSON inválido.');return false;}
 const expected=which==='command'?state.config.commandDevice:state.config.sensorDevice;
 const sample=parseTelemetry(json);if(!sample||sample.deviceId!==expected){diag('Mensagem descartada: device_id diferente do tópico.');return false;}
 const hasFields=METRICS.some(m=>m.source===which&&sample[m.key]!==null);
 if(which==='command'&&!hasFields&&sample.motorOn===null&&!sample.relays){diag('Mensagem do módulo de comandos sem grandezas nem estado válido.');return false;}
 state[which].sample=sample;state[which].at=Date.now();state[which].count++;
 for(const m of METRICS.filter(m=>m.source===which)){
  if(sample[m.key]!==null){const arr=state.series[m.key];arr.push({t:state[which].at,v:sample[m.key]});if(arr.length>120)arr.shift();}
 }
 state.records.push({at:new Date(state[which].at).toISOString(),deviceId:expected,...sample});if(state.records.length>500)state.records.shift();
 if(which==='command'&&state.pending&&state.command.at>=state.pending.at&&sample.motorOn===state.pending.target){
  text('commandFeedback',`ESP32 informou saída ${sample.motorOn?'ligada':'desligada'}; não confirma contatores ou motor físico.`);state.pending=null;
 }
 diag(`Recebendo ${which==='command'?'dados do PZEM / comandos':'vibração e temperatura do S3'} · seq ${sample.seq??'—'}.`);render();return true;
}
function connect(automatico){

 let config;try{config=validateConfig({broker:$('broker').value,prefix:$('prefix').value,commandDevice:$('commandDevice').value,sensorDevice:$('sensorDevice').value});}
 catch(e){diag(e.message);return;}
 if(!window.mqtt||typeof window.mqtt.connect!=='function'){pill('MQTT.js indisponível','error');diag('Biblioteca MQTT.js não carregou; confira o acesso ao CDN.');return;}
 if(state.client)disconnect();state.config=config;
 try{localStorage.setItem(STORE,JSON.stringify(config));}catch{}
 const generation=++state.generation;let client;
 try{client=window.mqtt.connect(config.broker,{clientId:`iotmotor_dual_${Math.random().toString(36).slice(2,11)}`,clean:true,protocolVersion:4,reconnectPeriod:4000,connectTimeout:10000,keepalive:30,resubscribe:true});}
 catch(e){pill('Falha MQTT','error');diag(e.message);return;}
 state.client=client;reset();pill('Conectando…','wait');diag(`Conectando ${config.broker}; dispositivos ${config.commandDevice} e ${config.sensorDevice}.`);
 if(!automatico){window.iotmotorRemoteControls?.connect?.();window.iotmotorWifi?.connect?.();window.iotmotorAlarme?.connect?.();window.iotmotorPerfis?.connect?.();}
 const active=()=>state.client===client&&state.generation===generation;
 client.on('connect',()=>{
  if(!active())return;state.connected=true;pill('Broker conectado','live');
  const topics=[topic(config.commandDevice,'telemetry'),topic(config.commandDevice,'status'),topic(config.sensorDevice,'telemetry'),topic(config.sensorDevice,'status')];
  client.subscribe(topics,{qos:0},err=>{
   if(!active())return;state.subscribed=!err;diag(err?`Conectado, erro de assinatura: ${err.message}`:`Broker conectado. Aguardando ${topics[0]} e ${topics[2]}.`);updateControl();
  });
 });
 client.on('message',(destination,payload,packet)=>{
  if(!active())return;
  const which=destination.startsWith(`${config.prefix}/${config.commandDevice}/`)?'command':destination.startsWith(`${config.prefix}/${config.sensorDevice}/`)?'sensor':null;
  if(!which)return;
  if(destination===topic(config[which==='command'?'commandDevice':'sensorDevice'],'status')){
   state[which].status=payload.toString('utf8').slice(0,80);state[which].statusAt=Date.now();render();return;
  }
  if(destination===topic(config[which==='command'?'commandDevice':'sensorDevice'],'telemetry'))ingest(which,payload.toString('utf8'),packet);
 });
 client.on('reconnect',()=>{if(!active())return;state.connected=false;state.subscribed=false;pill('Reconectando…','wait');render();});
 client.on('offline',()=>{if(!active())return;state.connected=false;state.subscribed=false;pill('Broker indisponível','error');diag('Falha WSS: verifique rede, broker e porta 8081.');render();});
 client.on('error',err=>{if(active())diag(`MQTT: ${String(err.message||err).slice(0,140)}`);});
 client.on('close',()=>{if(!active())return;state.connected=false;state.subscribed=false;pill('Conexão encerrada','error');render();});
}
function command(kind,mode){ /* Retired GPIO2 prototype: never publish control on a public broker. */ }
function exportCsv(){
 if(!state.records.length)return;
 const keys=METRICS.map(m=>m.key);
 const lines=[['received_at','device_id','demo','motor_on','bench_armed',...keys].join(',')];
 for(const row of state.records)lines.push([row.at,row.deviceId,row.demo,row.motorOn??'',row.benchArmed,...keys.map(k=>row[k]??'')].join(','));
 const blob=new Blob(['\ufeff'+lines.join('\r\n')],{type:'text/csv;charset=utf-8'});
 const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=`iotmotor-2-modulos-${new Date().toISOString().slice(0,10)}.csv`;a.click();
 setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function init(){
 try{const saved=JSON.parse(localStorage.getItem(STORE)||'null');if(saved)state.config=validateConfig(saved);}catch{}
 $('broker').value=state.config.broker;$('prefix').value=state.config.prefix;
 $('commandDevice').value=state.config.commandDevice;$('sensorDevice').value=state.config.sensorDevice;
 buildCards();render();
 $('connectBtn').addEventListener('click',()=>state.client?disconnect():connect());
 // A pagina abre desconectada: telemetria e comandos so comecam no botao Conectar.
 $('connectionForm').addEventListener('submit',event=>{event.preventDefault();connect();});
 // Original startBtn and stopBtn are wired only by local-controls.js.
 $('exportBtn').addEventListener('click',exportCsv);
 for(const button of document.querySelectorAll('[data-group]'))button.addEventListener('click',()=>{
  state.group=button.dataset.group;for(const b of document.querySelectorAll('[data-group]'))b.setAttribute('aria-pressed',String(button===b));renderCharts();
 });
 setInterval(()=>{
  if(state.pending&&Date.now()-state.pending.at>6500){text('commandFeedback','Sem confirmação do ESP32. Não pressuponha que a saída esteja desligada.');state.pending=null;}
  if(state.connected&&state.subscribed&&(!freshness('command')||!freshness('sensor')))
   diag(`Broker conectado; ${!freshness('command')?'sem dados recentes do PZEM/comandos':''}${!freshness('command')&&!freshness('sensor')?' e ':''}${!freshness('sensor')?'sem dados recentes do ESP32-S3':''}.`);
  render();
 },1500);
}
if(typeof document!=='undefined')init();
if(typeof module!=='undefined'&&module.exports)module.exports={parseTelemetry,validateConfig,deviceConnection,METRICS};
