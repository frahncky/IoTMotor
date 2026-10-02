'use strict';
// IoTMotor: esp32-01 PZEM + comandos; esp32-02 MPU6050/DS18B20 (somente leitura).
const $=id=>document.getElementById(id);
const STORE='iotmotor_dashboard_dual_v1';
// Historico das amostras neste navegador: sobrevive a fechar a aba, mas nao
// sai deste computador. A ultima hora, guardada so com as colunas do CSV:
// as duas placas a 1 Hz dao 7200 linhas (~1,9 MB). Antes eram 3000 linhas
// completas (~25 min), e o CSV oferecia 1 h e 24 h que nunca existiam. O
// historico longo fica na placa de sensores (7 dias, por hora).
// v3: uma linha por instante com as duas placas (antes, uma linha por placa).
const REGISTROS='iotmotor_registros_v3',REGISTROS_ANTIGOS='iotmotor_registros_v2';
const MAX_REGISTROS=7200,MAX_IDADE_MS=60*60*1000;
// Condição do ensaio (rótulo das linhas do CSV, para treinar a classificação).
const CONDICAO='iotmotor_condicao_v1',MAX_CONDICAO=40;
// Leitura da outra placa entra na linha se tiver chegado há até 3 s.
const JUNTAR_MS=3000;
const GRAVAR_REGISTROS_MS=15000;
let gravarRegistrosTimer=null;
// Endereço padrão: a ponte servida pela própria Cloudflare (functions/mqtt.js),
// na porta 443. Redes que bloqueiam as portas do broker não bloqueiam essa,
// senão derrubariam a internet inteira. Aberta fora da Cloudflare, cai no
// broker público direto.
const PONTE=typeof location!=='undefined'&&location.protocol==='https:'
 ?`wss://${location.host}/mqtt`:'wss://test.mosquitto.org:8081';
const DEFAULT={broker:PONTE,prefix:'iotmotor',commandDevice:'esp32-01',sensorDevice:'esp32-02'};
const TELEMETRY_STALE_MS=10000;
// Quem já usava o broker direto passa para a ponte uma vez, sem perder nada.
const BROKER_ANTIGO=['wss://test.mosquitto.org:8081','wss://test.mosquitto.org:8081/'];
const METRICS=[
 {key:'voltage',label:'Tensão',unit:'V',digits:1,group:'eletrica',color:'#65c7e8',source:'command'},
 {key:'current',label:'Corrente',unit:'A',digits:2,group:'eletrica',color:'#ffc46a',source:'command'},
 {key:'power',label:'Potência ativa',unit:'W',digits:1,group:'eletrica',color:'#e6a179',source:'command'},
 {key:'apparent',label:'Potência aparente',unit:'VA',digits:1,group:'eletrica',color:'#69d3b7',source:'command'},
 {key:'reactive',label:'Potência reativa',unit:'VAr',digits:1,group:'eletrica',color:'#a2adf4',source:'command'},
 {key:'pf',label:'Fator de potência',unit:'',digits:2,group:'eletrica',color:'#83d8a2',source:'command'},
 {key:'frequency',label:'Frequência',unit:'Hz',digits:2,group:'eletrica',color:'#95c8ff',source:'command'},
 {key:'energy',label:'Energia',unit:'kWh',digits:3,group:'eletrica',color:'#d4cf87',source:'command'},
 // Vibração pelo padrão de máquinas elétricas (ISO 10816-3): velocidade RMS.
 {key:'vibration_mms',label:'Vibração RMS',unit:'mm/s',digits:2,group:'mecanica',color:'#e6b2d4',source:'sensor'},
 {key:'temperature',label:'Temperatura',unit:'°C',digits:1,group:'mecanica',color:'#f69d84',source:'sensor'}
];
// Nomes mostrados na tela; o identificador tecnico fica na dica do selo.
const NOMES={command:'Quadro de comando',sensor:'Sensores do motor'};
const alias={voltage:['voltage','tensao','v'],current:['current','corrente','i'],power:['power','potencia','w'],pf:['pf','power_factor','fator_potencia','fp'],frequency:['frequency','frequencia','hz'],energy:['energy','energy_kwh','energia','kwh'],vibration_mms:['vibration_mms'],temperature:['temperature','temperatura','temp']};
const ACQ_DEFAULT={revision:0,pzem_read_ms:1000,publish_ms:1000,chart_ms:1000,record_ms:1000,vibration_hz:1000,vibration_window_ms:1000,history_bucket_s:3600,history_retention_days:7};
const ACQ_PRESETS={realtime:{pzem_read_ms:1000,publish_ms:1000,chart_ms:1000,record_ms:1000},monitoring:{pzem_read_ms:1000,publish_ms:2000,chart_ms:2000,record_ms:5000},economic:{pzem_read_ms:5000,publish_ms:5000,chart_ms:5000,record_ms:30000}};
const state={config:{...DEFAULT},client:null,generation:0,connected:false,subscribed:false,group:'todos',
 command:{sample:null,at:0,count:0,status:'—'},sensor:{sample:null,at:0,count:0,status:'—'},
 acquisition:{...ACQ_DEFAULT},lastRecord:{},series:Object.fromEntries(METRICS.map(m=>[m.key,[]])),records:[],pending:null,condicao:'',condicaoPendente:false};
let commandWasFresh=false;
function numeric(v){if(v===null||v===undefined||v==='')return null;const n=Number(typeof v==='string'?v.replace(',','.'):v);return Number.isFinite(n)?n:null;}
// Números na tela sempre com vírgula decimal (pt-BR); o CSV continua com ponto.
function numeroBr(v,casas){return v.toFixed(casas).replace('.',',');}
// Idade de uma leitura ("há 3 s"): diz na hora se o dado está atual.
function idadeLeitura(at,now=Date.now()){
 if(!at)return '—';
 const s=Math.max(0,Math.round((now-at)/1000));
 return s<60?`há ${s} s`:s<3600?`há ${Math.floor(s/60)} min`:`há ${Math.floor(s/3600)} h`;
}
// Diagnóstico da vibração por eixo (s3-sensors-1.23 em diante): estatísticas
// da aceleração e espectro da velocidade em 17 faixas de 10 Hz (20 a 180 Hz).
const VIB_EIXOS=['x','y','z'],VIB_FAIXAS_HZ=Array.from({length:17},(_,i)=>20+10*i);
const VIB_CAMPOS=[['mms','mms','mms'],['acc_rms','aRms','a_rms'],['acc_peak','aPeak','a_peak'],['crest','crest','crest'],
 ['kurtosis','kurt','kurt'],['peak_hz','pkHz','pk_hz'],['peak_mms','pkMms','pk_mms']];  // [coluna, chave, JSON]
function lerVib(v){
 if(!v||typeof v!=='object'||Array.isArray(v))return null;
 const out={};
 for(const e of VIB_EIXOS){
  const x=v[e];if(!x||typeof x!=='object'||Array.isArray(x))continue;
  out[e]=Object.fromEntries(VIB_CAMPOS.map(([,k,json])=>[k,numeric(x[json])]));
  out[e].bands=Array.isArray(x.bands)&&x.bands.length===VIB_FAIXAS_HZ.length?x.bands.map(numeric):null;
 }
 return Object.keys(out).length?out:null;
}
function field(source,keys){for(const key of keys){const n=numeric(source[key]);if(n!==null)return n;}return null;}
function parseTelemetry(json){
 if(!json||typeof json!=='object'||Array.isArray(json))return null;
 const source=json.data&&typeof json.data==='object'&&!Array.isArray(json.data)?json.data:json;
 const relays=Array.isArray(source.relays)&&source.relays.length===4&&source.relays.every(v=>typeof v==='boolean')?source.relays:null;
 // motor_running (quadro): girando pela regra do horímetro, que inclui o modo
 // instrumentação (motor comandado por fora, sem contator da placa).
 const motorOn=typeof source.motor_on==='boolean'?source.motor_on:
  typeof source.motor_running==='boolean'?source.motor_running:relays?relays.some(Boolean):null;
 const result={deviceId:String(json.device_id||source.device_id||''),demo:json.demo===true||source.demo===true||source.data_source==='simulated',
  dataSource:String(json.data_source||source.data_source||'não informada'),seq:numeric(source.seq),
  measuredAt:Number.isFinite(source.ts)&&source.ts>1700000000?source.ts*1000:null,
  benchArmed:source.bench_armed===true,motorOn,
  mode:typeof source.mode==='string'?source.mode:'—',
  profile:typeof source.profile==='string'?source.profile:'',
  relays,alarmEnabled:typeof source.alarm_enabled==='boolean'?source.alarm_enabled:null,
  runSTotal:numeric(source.run_s_total),startsTotal:numeric(source.starts_total),
  startsToday:numeric(source.starts_today),sessionS:numeric(source.session_s),startsHour:numeric(source.starts_hour),
  alarmsFiring:Array.isArray(source.alarms_firing)?source.alarms_firing.filter(id=>typeof id==='string'&&id):[],
  // Desarme: o quadro parou o motor por um alarme (vale até a próxima partida).
  tripField:typeof source.trip_field==='string'&&source.trip_field?source.trip_field:'',
  // Saúde dos sensores e eixo da vibração: contexto das linhas do CSV.
  pzemOk:typeof source.pzem_ok==='boolean'?source.pzem_ok:null,
  mpuOk:typeof source.mpu_ok==='boolean'?source.mpu_ok:null,
  temperatureOk:typeof source.temperature_ok==='boolean'?source.temperature_ok:null,
  sampleCount:numeric(source.sample_count),
  vibrationAxis:/^[xyz]$/.test(source.vibration_axis)?source.vibration_axis:'',
  vib:lerVib(source.vib)};
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
function telemetryFresh({brokerReady,status,statusAt=0,at=0,now=Date.now()}){
 if(!brokerReady||at<=0||now-at>=TELEMETRY_STALE_MS)return false;
 const st=String(status||'').trim().toLowerCase();
 return !(st==='offline'&&statusAt>=at);
}
function freshness(which){const s=state[which];return telemetryFresh({
 brokerReady:state.connected&&state.subscribed,status:s.status,statusAt:s.statusAt,at:s.at
});}
// Conexao do dispositivo: telemetria recente prevalece; senao usa o status retido/LWT mais novo.
function deviceConnection({brokerOk,status,statusAt=0,at=0,now=Date.now(),firmwareState=''}) {
 if(firmwareState==='updating')return {label:'atualizando firmware',kind:'wait'};
 if(firmwareState==='updated')return {label:'atualizado · conectado',kind:'live'};
 if(!brokerOk)return {label:'broker desconectado',kind:''};
 const fresh=telemetryFresh({brokerReady:brokerOk,status,statusAt,at,now}),st=String(status||'').trim().toLowerCase();
 if(st==='offline'&&statusAt>=at)return {label:'desconectado',kind:'error'};
 if(fresh)return {label:'conectado',kind:'live'};
 if(st==='offline')return {label:'desconectado',kind:'error'};
 if(st==='online')return {label:at?'online · sem dados há mais de 10 s':'online · aguardando dados',kind:'wait'};
 return {label:at?'sem dados há mais de 10 s':'sem sinal',kind:at?'error':''};
}
function renderDevice(id,which,name){
 const s=state[which];
 const ident=which==='command'?state.config.commandDevice:state.config.sensorDevice;
 const firmware=window.iotmotorFirmwareStatus?.(ident)||null;
 const info=deviceConnection({
  brokerOk:state.connected&&state.subscribed,
  status:s.status,statusAt:s.statusAt,at:s.at,
  firmwareState:firmware?.state||''
 });
 const demo=info.kind==='live'&&s.sample?.demo&&!firmware?' · SIMULADO':'';
 text(id,`${name} · ${info.label}${demo}`);$(id).className=`source ${info.kind}`.trim();
 const ota=firmware?.phase?` · OTA: ${firmware.phase}`:'';
 $(id).title=`${ident} · ${s.at?`última telemetria ${new Date(s.at).toLocaleTimeString('pt-BR')}`:'nenhuma telemetria recebida'}${ota}`;
}
function valueFor(metric){const source=state[metric.source];return freshness(metric.source)&&source.sample?source.sample[metric.key]:null;}
function motorVisualState({brokerReady,commandFresh,motorOn}){
 if(!brokerReady)return {state:'offline',label:'Desconectado'};
 if(!commandFresh)return {state:'waiting',label:'Aguardando quadro de comando'};
 if(motorOn===true)return {state:'running',label:'Motor ligado'};
 if(motorOn===false)return {state:'stopped',label:'Motor desligado'};
 return {state:'waiting',label:'Estado do motor não informado'};
}
// Texto do desenho do motor para leitores de tela: estado e alarmes na peça.
function motorVisualAria(label,parts){
 const extras=[parts?.has?.('temperature')&&'alarme de temperatura',parts?.has?.('vibration')&&'alarme de vibração'].filter(Boolean);
 return `Desenho do motor: ${[label,...extras].join(', ')}`;
}
// Aquecimento da carcaça de 0 (frio) a 1 (no limite do alarme de temperatura).
function motorHeat(temperature,limit){
 if(!Number.isFinite(temperature))return null;
 const top=Number.isFinite(limit)&&limit>0?limit:60,base=Math.min(30,top-10);
 return Math.min(1,Math.max(0,(temperature-base)/(top-base)));
}
// Menor limite "acima de" dos alarmes de temperatura ligados; 60 °C sem lista.
function temperatureLimit(alarms){
 const limits=(alarms||[]).filter(a=>a.field==='temperature'&&a.above!==false&&a.on!==false&&Number.isFinite(a.limit)).map(a=>a.limit);
 return limits.length?Math.min(...limits):60;
}
// Partes do motor em alarme. Sem a lista, usa os ids padrão da placa.
function alarmParts(firing,alarms){
 const parts=new Set();
 for(const id of firing||[]){
  const field=(alarms||[]).find(a=>a.id===id)?.field??(id==='temp'?'temperature':id==='vib'?'vibration_mms':'');
  parts.add(field==='temperature'?'temperature':field.startsWith('vibration')?'vibration':'other');
 }
 return parts;
}
// Laranja morno até vermelho conforme o aquecimento.
function heatColor(heat){
 const from=[245,165,36],to=[229,72,77];
 return `rgb(${from.map((c,i)=>Math.round(c+(to[i]-c)*heat)).join(',')})`;
}
// Limites de fábrica da placa de sensores, usados enquanto a lista não chega.
const LIMITES_PADRAO=[{field:'vibration_mms',above:true,limit:4.5},{field:'temperature',above:true,limit:60}];
const GRANDEZA_AVISO={starts_hour:{label:'Partidas na última hora',unit:'',digits:0,source:'command',read:s=>s.startsHour}};
// Avisos de leitura e de limite, mostrados em "Alarmes ativos" (alarm-controls.js).
// kind: no-data (placa sem dados), missing (grandeza sem leitura), near (a partir
// de 90% do limite), over (limite ultrapassado) ou maintenance (manutenção
// vencida ou a menos de 10% do intervalo).
function motorWarnings({brokerReady,command,sensor,alarms,maintenance}){
 if(!brokerReady)return [];
 const out=[];
 if(!sensor)out.push({kind:'no-data',field:'sensor',level:'warn',text:'Sensores do motor sem dados'});
 else for(const [key,texto] of [['vibration_mms','Vibração'],['temperature','Temperatura']])
  if(sensor[key]===null||sensor[key]===undefined)
   out.push({kind:'missing',field:key,level:'warn',text:`${texto} sem leitura`});
 if(!command)out.push({kind:'no-data',field:'command',level:'warn',text:'Quadro de comando sem dados'});
 else if(METRICS.filter(m=>m.source==='command'&&!['apparent','reactive'].includes(m.key)).every(m=>command[m.key]===null||command[m.key]===undefined))
  out.push({kind:'missing',field:'pzem',level:'warn',text:'Medições elétricas (PZEM) sem leitura'});
 if(maintenance&&(maintenance.vencida||maintenance.perto))
  out.push({kind:'maintenance',field:'maintenance',level:'warn',text:maintenanceText(maintenance)});
 // Com o monitoramento desligado a placa não alarma; aqui também só ficam os avisos de leitura.
 if(sensor?.alarmEnabled===false)return out;
 // Vários alarmes para a mesma grandeza e sentido: vale o mais grave.
 const porGrandeza=new Map();
 for(const a of (alarms||LIMITES_PADRAO)){
  if(a.on===false||!Number.isFinite(a.limit))continue;
  const metric=METRICS.find(m=>m.key===a.field),extra=GRANDEZA_AVISO[a.field];
  if(!metric&&!extra)continue;
  const sample=(metric?.source??extra?.source??'sensor')==='command'?command:sensor;
  const value=sample?(extra?extra.read(sample):sample[a.field]):null;
  if(!Number.isFinite(value))continue;
  // Mesma comparação estrita do firmware (alarm_list.h); 90% do limite já avisa.
  const above=a.above!==false,passou=above?value>a.limit:value<a.limit;
  const perto=above?value>=a.limit*0.9:value<=a.limit*1.1;
  if(!passou&&!perto)continue;
  const chave=`${a.field}:${above}`,anterior=porGrandeza.get(chave);
  if(anterior&&(anterior.passou||!passou))continue;
  const label=extra?.label??metric.label,unit=extra?.unit??metric.unit,digits=extra?.digits??metric.digits;
  porGrandeza.set(chave,{passou,kind:passou?'over':'near',field:a.field,level:passou?'alarm':'warn',text:`${label} ${above?'alta':'baixa'}: ${numeroBr(value,digits)}${unit?` ${unit}`:''} (limite ${String(a.limit).replace('.',',')}${unit?` ${unit}`:''})`});
 }
 for(const {kind,field,level,text} of porGrandeza.values())out.push({kind,field,level,text});
 return out;
}
// Avisos atuais para a lista de "Alarmes ativos".
function avisosAtuais(){
 const command=freshness('command')?state.command.sample:null;
 return motorWarnings({brokerReady:state.connected&&state.subscribed,command,
  sensor:freshness('sensor')?state.sensor.sample:null,alarms:window.iotmotorAlarme?.lista?.()||null,
  maintenance:maintenanceStatus(window.iotmotorMotorInfo?.dados?.(),command?.runSTotal)});
}
if(typeof window!=='undefined')window.iotmotorPainel={avisos:avisosAtuais,atualizarMotor:()=>renderMotorVisual()};
// Carga do motor em % da corrente nominal da placa; null sem cadastro.
function motorLoad(current,nominal){
 if(!Number.isFinite(current)||!Number.isFinite(nominal)||nominal<=0)return null;
 return Math.round(current/nominal*100);
}
function formatDuration(segundos){
 const s=Math.max(0,Math.floor(segundos));
 if(s<60)return `${s} s`;
 const m=Math.floor(s/60);
 if(m<60)return `${m} min`;
 return `${Math.floor(m/60)} h ${String(m%60).padStart(2,'0')} min`;
}
// Linha de uso do motor (horímetro e partidas) vinda do quadro de comando.
function usageLine({sessionS,runSTotal,startsToday,startsTotal}){
 const partes=[];
 if(Number.isFinite(sessionS))partes.push(`Ligado há ${formatDuration(sessionS)}`);
 if(Number.isFinite(runSTotal))partes.push(`Horímetro ${(runSTotal/3600).toFixed(1).replace('.',',')} h`);
 if(Number.isFinite(startsToday))partes.push(`${startsToday} ${startsToday===1?'partida':'partidas'} hoje`);
 else if(Number.isFinite(startsTotal))partes.push(`${startsTotal} ${startsTotal===1?'partida':'partidas'} no total`);
 return partes.join(' · ');
}
// Severidade da vibração pela ISO 10816: zonas da velocidade RMS em mm/s.
// Classe pela potência: até 15 kW, até 75 kW e acima disso (base rígida); sem
// potência cadastrada vale a das máquinas pequenas.
const ISO10816=[{ateKw:15,zonas:[0.71,1.8,4.5]},{ateKw:75,zonas:[1.12,2.8,7.1]},{ateKw:Infinity,zonas:[1.8,4.5,11.2]}];
const ZONAS_VIBRACAO=['Boa','Aceitável','Alerta','Crítica'];
function vibrationZone(mmS,powerCv){
 if(!Number.isFinite(mmS)||mmS<0)return null;
 const kw=Number.isFinite(powerCv)&&powerCv>0?powerCv*0.7355:0;
 const classe=ISO10816.find(c=>kw<=c.ateKw);
 const indice=classe.zonas.findIndex(limite=>mmS<limite);
 const zona=indice<0?3:indice;
 return {mmS,zona,label:ZONAS_VIBRACAO[zona]};
}
// Texto da vibração no cartão do motor, em mm/s RMS; a zona ISO só com o
// motor girando (parado, a vibração é ruído do sensor).
function vibrationText(sensor,motorOn,info){
 const mms=sensor?.vibration_mms;
 if(!Number.isFinite(mms))return null;
 const iso=motorOn===true?vibrationZone(mms,info?.power_cv):null;
 return {texto:`Vibração ${mms.toFixed(2).replace('.',',')} mm/s${iso?` · ${iso.label}`:''}`,iso};
}
// Manutenção pelo horímetro: horas de uso desde a última manutenção contra o
// intervalo cadastrado em "Dados do motor". null sem intervalo ou sem horímetro.
function maintenanceStatus(info,runSTotal){
 const intervaloH=info?.maint_interval_h;
 if(!Number.isFinite(intervaloH)||intervaloH<=0||!Number.isFinite(runSTotal))return null;
 const feitaEm=Number.isFinite(info.maint_done_run_s)?info.maint_done_run_s:0;
 const restanteH=intervaloH-Math.max(0,runSTotal-feitaEm)/3600;
 return {intervaloH,restanteH,vencida:restanteH<=0,perto:restanteH>0&&restanteH<=intervaloH*0.1};
}
function horas(h){return (h>=10?Math.round(h).toString():h.toFixed(1).replace('.',','))+' h';}
function maintenanceText(m){
 return m.vencida?`Manutenção vencida há ${horas(-m.restanteH)} de uso (a cada ${m.intervaloH} h)`
  :`Próxima manutenção em ${horas(m.restanteH)} de uso (a cada ${m.intervaloH} h)`;
}
// "Desligado pelo alarme de temperatura": só com o motor parado.
function tripText(tripField,motorOn){
 if(!tripField||motorOn===true)return '';
 const nome=METRICS.find(m=>m.key===tripField)?.label??GRANDEZA_AVISO[tripField]?.label??tripField;
 return `Desligado pelo alarme de ${nome.toLowerCase().replace(/ rms$/,'')}`;
}
// Comando enviado e ainda não confirmado pelo quadro (null quando já refletiu).
function commandPendingLabel(pending,motorOn){
 if(!pending)return null;
 if(pending.action==='start'&&motorOn!==true)return 'Ligando…';
 if(pending.action==='stop'&&motorOn!==false)return 'Desligando…';
 return null;
}
function renderMotorVisual(){
 const root=$('motorVisual');if(!root)return;
 const commandFresh=freshness('command'),sensorFresh=freshness('sensor');
 if(commandWasFresh&&!commandFresh)window.iotmotorMotorSound?.stopForDisconnect?.();
 commandWasFresh=commandFresh;
 const cmd=commandFresh?state.command.sample:null,sensor=sensorFresh?state.sensor.sample:null;
 const visual=motorVisualState({brokerReady:state.connected&&state.subscribed,commandFresh,motorOn:cmd?.motorOn});
 const pendente=commandPendingLabel(window.iotmotorRemoteControls?.pendente?.()||null,cmd?.motorOn);
 root.dataset.state=visual.state;text('motorVisualStatus',pendente||visual.label);
 if(pendente)root.dataset.command='pending';else delete root.dataset.command;
 const info=window.iotmotorMotorInfo?.dados?.()||null;
 const perfilId=typeof cmd?.profile==='string'&&cmd.profile?cmd.profile:(window.iotmotorPartidaSelecionada?.()||'');
 const perfil=window.iotmotorPerfilVisual?.(perfilId)||null;
 if(Number.isFinite(info?.rpm)&&info.rpm>0)root.dataset.rpm=String(info.rpm);else delete root.dataset.rpm;
 if(perfilId)root.dataset.profile=perfilId;else delete root.dataset.profile;
 root.dataset.startKind=perfil?.kind||'direct';
 if(cmd?.motorOn===true&&Number.isFinite(sensor?.vibration_mms)&&sensor.vibration_mms>=0)
  root.dataset.vibration=String(sensor.vibration_mms);
 else root.dataset.vibration='0';
 const alarms=window.iotmotorAlarme?.lista?.()||null;
 const heat=motorHeat(sensor?.temperature,temperatureLimit(alarms));
 const heatLayer=root.querySelector('.motor-heat');
 if(heatLayer){heatLayer.style.fill=heat?heatColor(heat):'';heatLayer.style.opacity=heat?String(0.18+0.6*heat):'0';}
 const parts=sensor&&sensor.alarmEnabled!==false?alarmParts(sensor.alarmsFiring,alarms):new Set();
 root.dataset.alarm=parts.size?'on':'off';
 root.dataset.alarmTemp=parts.has('temperature')?'on':'off';
 root.dataset.alarmVib=parts.has('vibration')?'on':'off';
 $('motorVisualStage')?.setAttribute('aria-label',motorVisualAria(pendente||visual.label,parts));
 const dados=[];
 if(cmd?.current!==null&&cmd?.current!==undefined){
  const carga=cmd.motorOn===true?motorLoad(cmd.current,window.iotmotorMotorInfo?.dados?.()?.current_in_use_a):null;
  dados.push(`Corrente ${numeroBr(cmd.current,2)} A${carga!==null?` (carga ${carga}%)`:''}`);
 }
 // Classificação só com o motor girando: parado, a vibração é ruído do sensor.
 const vib=vibrationText(sensor,cmd?.motorOn,info);
 if(vib)dados.push(vib.texto);
 if(vib?.iso)root.dataset.vibZone=String(vib.iso.zona);else delete root.dataset.vibZone;
 if(sensor?.temperature!==null&&sensor?.temperature!==undefined)dados.push(`Temperatura ${numeroBr(sensor.temperature,1)} °C`);
 // Uma grandeza por linha (white-space:pre-line), ao lado do desenho.
 text('motorVisualMetrics',dados.length?dados.join('\n'):
  visual.state==='offline'?'Conecte ao MQTT para visualizar o estado do motor.':'Sem grandezas recentes para exibir.');
 const manutencao=maintenanceStatus(info,cmd?.runSTotal);
 const uso=[tripText(cmd?.tripField,cmd?.motorOn),cmd?usageLine(cmd):'',manutencao?.vencida?'Manutenção vencida':manutencao?.perto?`Manutenção em ${horas(manutencao.restanteH)}`:'']
  .filter(Boolean).join(' · ');
 const manutEl=$('motorInfoManutStatus');
 if(manutEl){
  const ultima=Number.isFinite(info?.maint_done_utc)?` Última registrada em ${new Date(info.maint_done_utc*1000).toLocaleDateString('pt-BR')}.`:'';
  manutEl.textContent=manutencao?`${maintenanceText(manutencao)}.${ultima}`
   :info?.maint_interval_h>0?`Aguardando o horímetro do quadro.${ultima}`:ultima.trim();
 }
 const usoEl=$('motorVisualUso');if(usoEl){usoEl.hidden=!uso;usoEl.textContent=uso;}
 const avisos=[parts.has('temperature')&&'alarme de temperatura',parts.has('vibration')&&'alarme de vibração',
  parts.has('other')&&'alarme ativo'].filter(Boolean);
 root.setAttribute('aria-label',`${pendente||visual.label}. ${dados.length?dados.join(', '):'Sem grandezas recentes.'}${uso?` ${uso}.`:''}${avisos.length?` Atenção: ${avisos.join(', ')}.`:''}`);
}
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
}
function svg(tag,attrs={},content){const n=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const [key,v]of Object.entries(attrs))n.setAttribute(key,String(v));if(content!==undefined)n.textContent=String(content);return n;}
function drawChart(target,metric){
 const entries=state.series[metric.key];
 const values=entries.map(entry=>entry.v);
 const hoverSalvo=Number(target.dataset.hoverRatio);
 target.replaceChildren();
 if(!values.length){
  delete target.dataset.hoverRatio;
  target.onpointermove=null;target.onpointerleave=null;
  target.append(svg('text',{x:320,y:105,'text-anchor':'middle',class:'empty'},'Sem leitura disponível'));
  return;
 }
 let min=Math.min(...values),max=Math.max(...values);const pad=Math.max((max-min)*.12,Math.abs(max)*.01,.01);min-=pad;max+=pad;
 for(let i=0;i<4;i++){const y=20+160*i/3;target.append(svg('line',{x1:53,x2:633,y1:y,y2:y,class:'gridline'}));target.append(svg('text',{x:45,y:y+4,'text-anchor':'end'},numeroBr(max-(max-min)*i/3,metric.digits>2?2:metric.digits)));}
 // Grade vertical: 5 faixas; nas linhas do meio, a hora da amostra ali.
 for(let k=0;k<=5;k++){
  const x=56+570*k/5;target.append(svg('line',{x1:x,x2:x,y1:20,y2:180,class:'gridline'}));
  const entry=entries[Math.round(k/5*(entries.length-1))];
  if(k>0&&k<5&&entries.length>1&&Number.isFinite(entry?.t))
   target.append(svg('text',{x,y:196,'text-anchor':'middle'},new Date(entry.t).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit',second:'2-digit'})));
 }
 const pontoX=i=>56+(values.length===1?280:570*i/(values.length-1));
 const pontoY=v=>180-(v-min)/(max-min)*160;
 const points=values.map((v,i)=>`${pontoX(i).toFixed(1)},${pontoY(v).toFixed(1)}`).join(' ');
 target.append(svg('polyline',{points,stroke:metric.color}));
 target.append(svg('text',{x:56,y:209},'Mais antigo'));
 target.append(svg('text',{x:631,y:209,'text-anchor':'end'},'Mais recente'));

 // Consulta do histórico pelo cursor. É independente do valor atual mostrado
 // no cabeçalho: aqui aparecem a hora e o valor do ponto passado mais próximo.
 const hover=svg('g',{class:'chart-hover',visibility:'hidden','pointer-events':'none'});
 const guia=svg('line',{y1:20,y2:180,class:'chart-hover-line'});
 const ponto=svg('circle',{r:4,fill:metric.color,class:'chart-hover-dot'});
 const caixa=svg('rect',{height:34,rx:7,ry:7,class:'chart-hover-box'});
 const textoHover=svg('text',{y:0,'text-anchor':'middle',class:'chart-hover-text'});
 hover.append(guia,ponto,caixa,textoHover);target.append(hover);

 const mostrarHover=ratio=>{
  const r=Math.max(0,Math.min(1,Number(ratio)||0));
  const indice=values.length===1?0:Math.round(r*(values.length-1));
  const entry=entries[indice];
  if(!entry||!Number.isFinite(entry.v))return;
  const px=pontoX(indice),py=pontoY(entry.v);
  const hora=Number.isFinite(entry.t)
   ?new Date(entry.t).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit',second:'2-digit'})
   :'—';
  const valor=`${numeroBr(entry.v,metric.digits)}${metric.unit?' '+metric.unit:''}`;
  const rotulo=`${hora} · ${valor}`;
  const largura=Math.max(132,Math.min(250,rotulo.length*7.8+22));
  const cx=Math.max(56+largura/2,Math.min(633-largura/2,px));
  const cy=py<64?py+40:py-24;
  guia.setAttribute('x1',px);guia.setAttribute('x2',px);
  ponto.setAttribute('cx',px);ponto.setAttribute('cy',py);
  caixa.setAttribute('x',cx-largura/2);caixa.setAttribute('y',cy-22);caixa.setAttribute('width',largura);
  textoHover.setAttribute('x',cx);textoHover.setAttribute('y',cy);textoHover.textContent=rotulo;
  hover.setAttribute('visibility','visible');
 };
 target.onpointermove=event=>{
  const rect=target.getBoundingClientRect();
  if(!rect.width)return;
  const xSvg=(event.clientX-rect.left)*650/rect.width;
  const ratio=Math.max(0,Math.min(1,(xSvg-56)/570));
  target.dataset.hoverRatio=String(ratio);
  mostrarHover(ratio);
 };
 target.onpointerleave=()=>{
  delete target.dataset.hoverRatio;
  hover.setAttribute('visibility','hidden');
 };
 if(Number.isFinite(hoverSalvo))mostrarHover(hoverSalvo);
}
function renderCharts(){
 const root=$('plots');
 const metrics=METRICS.filter(m=>state.group==='todos'||m.group===state.group);
 const assinatura=metrics.map(m=>m.key).join(',');
 if(root.dataset.metrics!==assinatura||root.children.length!==metrics.length){
  root.replaceChildren();
  for(const metric of metrics){
   const article=document.createElement('article');article.className='panel chart-card';article.dataset.metric=metric.key;
   const heading=document.createElement('h3');heading.className='chart-heading';
   const titulo=document.createElement('span');titulo.className='chart-title';titulo.textContent=`${metric.label}${metric.unit?' ('+metric.unit+')':''}`;
   const atual=document.createElement('span');atual.className='chart-current';
   heading.append(titulo,atual);
   const graphic=svg('svg',{viewBox:'0 0 650 215',class:'chart',role:'img','aria-label':`Gráfico de ${metric.label}`});
   article.append(heading,graphic);root.append(article);
  }
  root.dataset.metrics=assinatura;
 }
 metrics.forEach((metric,i)=>{
  const article=root.children[i];
  const atual=article.querySelector('.chart-current');
  const valor=valueFor(metric);
  atual.textContent=valor===null?'—':`${numeroBr(valor,metric.digits)}${metric.unit?' '+metric.unit:''}`;
  drawChart(article.querySelector('.chart'),metric);
 });
}
function buildCards(){const root=$('metrics');for(const m of METRICS){
 const item=document.createElement('article');item.className='panel metric';
 const label=document.createElement('div');label.className='metric-label';label.textContent=m.label;
 const value=document.createElement('div');value.className='metric-value';
 const number=document.createElement('span');number.id=`value-${m.key}`;number.textContent='—';
 const unit=document.createElement('span');unit.className='unit';unit.textContent=m.unit;value.append(number,unit);
 const detail=document.createElement('small');detail.id=`hint-${m.key}`;detail.textContent='Sem leitura';item.append(label,value,detail);root.append(item);
}}
function render(){
 for(const m of METRICS){const value=valueFor(m),source=state[m.source];text(`value-${m.key}`,value===null?'—':numeroBr(value,m.digits));
 text(`hint-${m.key}`,value===null?'':source.sample.demo?'Simulado — não é medição':m.source==='command'?'ESP32 PZEM-004T':'ESP32-S3 sensores');}
 renderDevice('pzemState','command',NOMES.command);
 renderDevice('sensorState','sensor',NOMES.sensor);
 for(const [id,which] of [['commandAge','command'],['sensorAge','sensor']]){
  const at=state[which].at;text(id,idadeLeitura(at));
  // Mesma regra do selo de conexão: passou de 10 s, o dado está velho.
  $(id).className=at&&!freshness(which)?'velha':'';
  $(id).title=at?new Date(at).toLocaleTimeString('pt-BR'):'';
 }
 $('exportBtn').disabled=!state.records.length;updateControl();renderMotorVisual();renderCharts();
}
function reset(){commandWasFresh=false;state.command={sample:null,at:0,count:0,status:'—',statusAt:0};state.sensor={sample:null,at:0,count:0,status:'—',statusAt:0};
 state.series=Object.fromEntries(METRICS.map(m=>[m.key,[]]));state.lastRecord={};state.pending=null;state.subscribed=false;
 render();}
function disconnect(){const old=state.client;state.generation++;state.client=null;state.connected=false;state.subscribed=false;if(old)old.end(true);
 window.iotmotorMotorSound?.stopForDisconnect?.();  // Pausa sem som de desligamento e permite retomar após reconectar.
 window.iotmotorRemoteControls?.disconnect?.();  // Botoes Ligar/Desligar param junto.
 window.iotmotorWifi?.disconnect?.();  // Aba Wi-Fi tambem.
 window.iotmotorAlarme?.disconnect?.();window.iotmotorPerfis?.disconnect?.();window.iotmotorMotorInfo?.disconnect?.();window.iotmotorHistorico?.disconnect?.();
 reset();pill('Desconectado');diag('Desconectado.');}
function chartBucketStart(at,intervalMs){
 const intervalo=Math.max(1,Number(intervalMs)||1);
 return Math.floor(Number(at)/intervalo)*intervalo;
}
function upsertChartPoint(arr,at,value,intervalMs,maxPoints=120){
 const numero=Number(value);
 if(!Array.isArray(arr)||!Number.isFinite(numero))return false;
 const t=chartBucketStart(at,intervalMs),last=arr[arr.length-1];
 // MQTT preserva ordem na sessao; um pacote atrasado nao deve reescrever
 // uma janela que ja foi fechada no grafico.
 if(last&&t<last.t)return false;
 if(last&&t===last.t){
  const quantidade=Number(last.n)||1;
  const soma=Number.isFinite(last.sum)?last.sum:last.v*quantidade;
  last.sum=soma+numero;last.n=quantidade+1;last.v=last.sum/last.n;
  return true;
 }
 arr.push({t,v:numero,sum:numero,n:1});
 if(arr.length>maxPoints)arr.shift();
 return true;
}
function ingest(which,raw,packet){
 if(packet?.retain===true){diag(`Telemetria retida antiga de ${which==='command'?'ESP32 PZEM':'ESP32-S3'} ignorada.`);return false;}
 let json;try{json=JSON.parse(raw);}catch{diag('Mensagem MQTT recebida, mas JSON inválido.');return false;}
 const expected=which==='command'?state.config.commandDevice:state.config.sensorDevice;
 const sample=parseTelemetry(json);if(!sample||sample.deviceId!==expected){diag('Mensagem descartada: device_id diferente do tópico.');return false;}
 const hasFields=METRICS.some(m=>m.source===which&&sample[m.key]!==null);
 if(which==='command'&&!hasFields&&sample.motorOn===null&&!sample.relays){diag('Mensagem do módulo de comandos sem grandezas nem estado válido.');return false;}
 state[which].sample=sample;state[which].at=Date.now();state[which].count++;
 if(which==='command')window.iotmotorMotorSound?.syncConfirmedState?.(sample.motorOn);
 const tempoDoGrafico=sample.measuredAt??state[which].at;
 for(const m of METRICS.filter(m=>m.source===which)){
  if(sample[m.key]!==null)upsertChartPoint(state.series[m.key],tempoDoGrafico,sample[m.key],state.acquisition.chart_ms);
 }
 registrar(which);
 if(which==='command'&&state.pending&&state.command.at>=state.pending.at&&sample.motorOn===state.pending.target)state.pending=null;
 diag(`Recebendo ${which==='command'?'medições do quadro de comando':'vibração e temperatura dos sensores'}.`);render();return true;
}
function connect(automatico){

 let config;try{config=validateConfig({broker:$('broker').value,prefix:$('prefix').value,commandDevice:$('commandDevice').value,sensorDevice:$('sensorDevice').value});}
 catch(e){diag(e.message);return;}
 if(!window.mqtt||typeof window.mqtt.connect!=='function'){pill('MQTT.js indisponível','error');diag('Biblioteca MQTT.js não carregou; recarregue a página.');return;}
 if(state.client)disconnect();state.config=config;
 try{localStorage.setItem(STORE,JSON.stringify(config));}catch{}
 const generation=++state.generation;let client;
 try{client=window.mqtt.connect(config.broker,{clientId:`iotmotor_dual_${Math.random().toString(36).slice(2,11)}`,clean:true,protocolVersion:4,reconnectPeriod:4000,connectTimeout:10000,keepalive:30,resubscribe:true});}
 catch(e){pill('Falha MQTT','error');diag(e.message);return;}
 state.client=client;reset();pill('Conectando…','wait');diag(`Conectando ${config.broker}; dispositivos ${config.commandDevice} e ${config.sensorDevice}.`);
 if(!automatico){window.iotmotorRemoteControls?.connect?.();window.iotmotorWifi?.connect?.();window.iotmotorAlarme?.connect?.();window.iotmotorPerfis?.connect?.();window.iotmotorMotorInfo?.connect?.();window.iotmotorHistorico?.connect?.();}
 const active=()=>state.client===client&&state.generation===generation;
 client.on('connect',()=>{
  if(!active())return;state.connected=true;pill('Broker conectado','live');
  const topics=[topic(config.commandDevice,'telemetry'),topic(config.commandDevice,'status'),topic(config.sensorDevice,'telemetry'),topic(config.sensorDevice,'status'),config.prefix+'/system/acquisition',config.prefix+'/system/condition'];
  client.subscribe(topics,{qos:0},err=>{
   if(!active())return;state.subscribed=!err;diag(err?`Conectado, erro de assinatura: ${err.message}`:`Broker conectado. Aguardando ${topics[0]} e ${topics[2]}.`);updateControl();
   if(!err)publicarCondicao();  // O que foi digitado desconectado vale agora.
  });
 });
 client.on('message',(destination,payload,packet)=>{
  if(!active())return;
  if(destination===config.prefix+'/system/acquisition'){aplicarConfiguracaoAquisicao(payload.toString('utf8'));return;}
  if(destination===config.prefix+'/system/condition'){receberCondicao(payload.toString('utf8'));return;}
  const which=destination.startsWith(`${config.prefix}/${config.commandDevice}/`)?'command':destination.startsWith(`${config.prefix}/${config.sensorDevice}/`)?'sensor':null;
  if(!which)return;
  if(destination===topic(config[which==='command'?'commandDevice':'sensorDevice'],'status')){
   state[which].status=payload.toString('utf8').slice(0,80);state[which].statusAt=Date.now();render();return;
  }
  if(destination===topic(config[which==='command'?'commandDevice':'sensorDevice'],'telemetry'))ingest(which,payload.toString('utf8'),packet);
 });
 const QUEDA_TOLERADA_MS=6000;let quedaTimer=null;
 const caiu=()=>{
  if(!active()||quedaTimer)return;
  pill('Reconectando…','wait');diag('Conexão instável; tentando reconectar ao broker.');
  quedaTimer=setTimeout(()=>{
   quedaTimer=null;
   if(!active()||client.connected)return;
   state.connected=false;state.subscribed=false;
   pill('Broker indisponível','error');diag('Falha WSS persistente; verifique rede e broker.');render();
  },QUEDA_TOLERADA_MS);
 };
 const voltou=()=>{if(quedaTimer){clearTimeout(quedaTimer);quedaTimer=null;}};
 client.on('reconnect',caiu);
 client.on('offline',caiu);
 client.on('error',err=>{if(active())diag(`MQTT: ${String(err.message||err).slice(0,140)}`);});
 client.on('close',caiu);
 client.on('connect',voltou);
}
// Linha guardada para o CSV: as duas placas no mesmo instante, com o contexto
// (partida, contatores, saúde dos sensores) e a condição do ensaio.
function registroCsv({command=null,sensor=null,at,condicao=''}){
 const base=command||sensor;
 const linha={at:new Date(base?.measuredAt??at).toISOString(),clockSource:base?.measuredAt?'placa':'navegador',
  demo:Boolean(command?.demo||sensor?.demo),condicao:String(condicao||'').trim().slice(0,MAX_CONDICAO)};
 if(command){
  Object.assign(linha,{motorOn:command.motorOn,benchArmed:command.benchArmed,
   mode:command.mode==='—'?'':command.mode,profile:command.profile,sessionS:command.sessionS,pzemOk:command.pzemOk});
  if(command.relays)linha.relays=command.relays.slice();
 }
 if(sensor)Object.assign(linha,{mpuOk:sensor.mpuOk,temperatureOk:sensor.temperatureOk,
  sampleCount:sensor.sampleCount,vibrationAxis:sensor.vibrationAxis});
 if(sensor?.vib)linha.vib=sensor.vib;
 for(const m of METRICS){
  const v=(m.source==='command'?command:sensor)?.[m.key];
  if(v!==null&&v!==undefined)linha[m.key]=v;
 }
 return linha;
}
// Uma linha por intervalo de registro. O quadro dita o ritmo; sem ele, os
// sensores. Folga de 10 %: a publicação a cada 1 s chega com atraso variável
// e, sem ela, metade das linhas de 1 s se perdia.
function registrar(which){
 const agora=state[which].at,recente=x=>state[x].sample&&agora-state[x].at<=JUNTAR_MS;
 if(which==='sensor'&&recente('command'))return;
 if(agora-(state.lastRecord.at||0)<state.acquisition.record_ms*0.9)return;
 state.lastRecord.at=agora;
 state.records.push(registroCsv({command:recente('command')?state.command.sample:null,
  sensor:recente('sensor')?state.sensor.sample:null,at:agora,condicao:state.condicao}));
 if(state.records.length>MAX_REGISTROS)state.records.shift();
 guardarRegistros();
}
// Condição do ensaio no tópico retido <prefixo>/system/condition: o coletor
// contínuo (tools/coletor) e outros painéis rotulam as linhas com ela.
// {"v":1,"condition":"..."} -> texto; null se inválido.
function lerCondicao(raw){
 let data;try{data=typeof raw==='string'?JSON.parse(raw):raw;}catch{return null;}
 if(!data||typeof data!=='object'||typeof data.condition!=='string')return null;
 return data.condition.trim().slice(0,MAX_CONDICAO);
}
function definirCondicao(texto){
 state.condicao=texto;
 try{localStorage.setItem(CONDICAO,texto);}catch{}
}
// Vinda do broker. Não apaga o que foi digitado aqui e ainda não foi publicado.
function receberCondicao(raw){
 const texto=lerCondicao(raw);
 if(texto===null||state.condicaoPendente)return;
 definirCondicao(texto);
 const campo=$('ensaioCondicao');
 if(campo&&document.activeElement!==campo)campo.value=texto;
}
function publicarCondicao(){
 if(!state.condicaoPendente||!state.client||!state.connected)return;
 state.client.publish(`${state.config.prefix}/system/condition`,
  JSON.stringify({v:1,condition:state.condicao,ts:Math.floor(Date.now()/1000)}),{qos:1,retain:true});
 state.condicaoPendente=false;
}
// Célula do CSV: texto com vírgula, aspas ou quebra de linha vai entre aspas.
function celulaCsv(v){
 if(v===null||v===undefined)return '';
 const s=String(v);
 return /[",\r\n]/.test(s)?`"${s.replace(/"/g,'""')}"`:s;
}
const CSV_COLUNAS=[
 ['measured_at',r=>r.at],['clock_source',r=>r.clockSource],['demo',r=>r.demo],['condition',r=>r.condicao],
 ['motor_running',r=>r.motorOn],['bench_armed',r=>r.benchArmed],['mode',r=>r.mode],['profile',r=>r.profile],
 ['session_s',r=>r.sessionS],
 ...[0,1,2,3].map(i=>[`relay_${i+1}`,r=>r.relays?.[i]]),
 ['pzem_ok',r=>r.pzemOk],['mpu_ok',r=>r.mpuOk],['temperature_ok',r=>r.temperatureOk],
 ['vibration_samples',r=>r.sampleCount],['vibration_axis',r=>r.vibrationAxis],
 ...METRICS.map(m=>[m.key,r=>r[m.key]]),
 // vib_x_mms ... vib_z_b180: por eixo, as estatísticas e depois as faixas.
 ...VIB_EIXOS.flatMap(e=>[
  ...VIB_CAMPOS.map(([nome,k])=>[`vib_${e}_${nome}`,r=>r.vib?.[e]?.[k]]),
  ...VIB_FAIXAS_HZ.map((hz,i)=>[`vib_${e}_b${String(hz).padStart(3,'0')}`,r=>r.vib?.[e]?.bands?.[i]])
 ])
];
function linhasCsv(registros){
 return [CSV_COLUNAS.map(c=>c[0]).join(','),...registros.map(r=>CSV_COLUNAS.map(c=>celulaCsv(c[1](r))).join(','))];
}
function registrosValidos(linhas){
 if(!Array.isArray(linhas))return [];
 const limite=Date.now()-MAX_IDADE_MS;
 return linhas.filter(linha=>linha&&typeof linha.at==='string'&&Date.parse(linha.at)>=limite)
  .slice(-MAX_REGISTROS);
}
function lerRegistros(){
 // Linhas do formato antigo (uma por placa) não cabem nas colunas novas.
 try{localStorage.removeItem(REGISTROS_ANTIGOS);}catch{}
 try{return registrosValidos(JSON.parse(localStorage.getItem(REGISTROS)||'[]'));}
 catch{return [];}
}
function guardarRegistros(){
 if(gravarRegistrosTimer)return;
 gravarRegistrosTimer=setTimeout(()=>{
  gravarRegistrosTimer=null;
  try{localStorage.setItem(REGISTROS,JSON.stringify(state.records));}
  catch{  // Espaco esgotado: fica so com a metade mais nova.
   state.records=state.records.slice(-Math.floor(MAX_REGISTROS/2));
   try{localStorage.setItem(REGISTROS,JSON.stringify(state.records));}catch{}
  }
 },GRAVAR_REGISTROS_MS);
}
function limparRegistros(){
 state.records=[];
 try{localStorage.removeItem(REGISTROS);}catch{}
 $('exportBtn').disabled=true;
 diag('Histórico apagado deste navegador.');
}
function exportCsv(){
 if(!state.records.length)return;
 const periodo=Number($('exportPeriodo')?.value||0);
 const desde=periodo?Date.now()-periodo*60000:0;
 const linhas=state.records.filter(row=>!desde||Date.parse(row.at)>=desde);
 if(!linhas.length){diag('Nenhuma leitura no período escolhido.');return;}
 const lines=linhasCsv(linhas);
 const blob=new Blob(['\ufeff'+lines.join('\r\n')],{type:'text/csv;charset=utf-8'});
 const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=`iotmotor-2-modulos-${new Date().toISOString().slice(0,10)}.csv`;a.click();
 setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function aplicarConfiguracaoAquisicao(raw){
 let data;try{data=typeof raw==='string'?JSON.parse(raw):raw;}catch{return false;}
 if(!data||typeof data!=='object')return false;
 const cfg={...ACQ_DEFAULT,...data};
 for(const k of ['pzem_read_ms','publish_ms','chart_ms','record_ms'])if(!Number.isInteger(Number(cfg[k])))return false;
 state.acquisition={...cfg,pzem_read_ms:Number(cfg.pzem_read_ms),publish_ms:Number(cfg.publish_ms),chart_ms:Number(cfg.chart_ms),record_ms:Number(cfg.record_ms)};
 renderAcquisitionConfig();return true;
}
function renderAcquisitionConfig(){
 const cfg=state.acquisition;
 for(const par of [['acqPzem','pzem_read_ms'],['acqPublish','publish_ms'],['acqChart','chart_ms'],['acqRecord','record_ms']]){
  const el=$(par[0]);if(el&&document.activeElement!==el)el.value=String(cfg[par[1]]/1000);
 }
 const preset=$('acqPreset');
 if(preset&&document.activeElement!==preset){
  let nome='custom';
  for(const [id,p] of Object.entries(ACQ_PRESETS)){
   if(p.pzem_read_ms===cfg.pzem_read_ms&&p.publish_ms===cfg.publish_ms&&
      p.chart_ms===cfg.chart_ms&&p.record_ms===cfg.record_ms){nome=id;break;}
  }
  preset.value=nome;
 }
 text('acqFixed','Vibração: '+cfg.vibration_hz+' Hz · janela RMS '+(cfg.vibration_window_ms/1000)+' s · histórico: '+(cfg.history_bucket_s/60)+' min / '+cfg.history_retention_days+' dias');
 text('acqRevision',cfg.revision?'Configuração carregada do ESP32-01 · revisão '+cfg.revision:'Aguardando configuração do ESP32-01.');
}
function lerConfiguracaoAquisicaoForm(){
 const seg=id=>Number($(id)?.value)*1000;
 const cfg={pzem_read_ms:seg('acqPzem'),publish_ms:seg('acqPublish'),chart_ms:seg('acqChart'),record_ms:seg('acqRecord')};
 if(!Object.values(cfg).every(Number.isInteger))throw Error('Use intervalos inteiros em segundos.');
 if(cfg.pzem_read_ms<1000||cfg.pzem_read_ms>10000)throw Error('Aquisição elétrica: 1 a 10 s.');
 if(cfg.publish_ms<1000||cfg.publish_ms>60000)throw Error('Publicação MQTT: 1 a 60 s.');
 if(cfg.pzem_read_ms>cfg.publish_ms)throw Error('A aquisição elétrica deve ser igual ou mais rápida que a publicação.');
 if(cfg.chart_ms<cfg.publish_ms||cfg.chart_ms>60000)throw Error('O gráfico deve ser igual ou mais lento que a publicação MQTT.');
 if(cfg.record_ms<cfg.publish_ms||cfg.record_ms>600000)throw Error('O registro deve ser igual ou mais lento que a publicação MQTT.');
 return cfg;
}
function init(){
 try{localStorage.removeItem('iotmotor_registros_v1');}catch{}  // Formato antigo, de ate 2 MB.
 try{
  const saved=JSON.parse(localStorage.getItem(STORE)||'null');
  if(saved){
   if(BROKER_ANTIGO.includes(String(saved.broker||'')))saved.broker=DEFAULT.broker;
   state.config=validateConfig(saved);
  }
 }catch{}
 // O que ja foi medido continua aqui depois de fechar e abrir o navegador.
 state.records=lerRegistros();
 // Condição do ensaio: vale para as linhas gravadas daqui em diante.
 try{state.condicao=String(localStorage.getItem(CONDICAO)||'').slice(0,MAX_CONDICAO);}catch{}
 if($('ensaioCondicao')){
  $('ensaioCondicao').value=state.condicao;
  // Publica quando para de digitar; desconectado, ao conectar.
  let publicarTimer=null;
  $('ensaioCondicao').addEventListener('input',()=>{
   definirCondicao($('ensaioCondicao').value.trim().slice(0,MAX_CONDICAO));
   state.condicaoPendente=true;
   clearTimeout(publicarTimer);publicarTimer=setTimeout(publicarCondicao,800);
  });
 }
 $('broker').value=state.config.broker;$('prefix').value=state.config.prefix;
 $('commandDevice').value=state.config.commandDevice;$('sensorDevice').value=state.config.sensorDevice;
 // O campo da senha de comando so aparece se alguma placa exigir selo.
 setInterval(()=>{
  const precisa=window.iotmotorSelo?.algumaExige?.()===true;
  for(const id of ['cmdCampo','cmdAviso'])if($(id))$(id).hidden=!precisa;
 },1000);
 if($('cmdSenha')){
  $('cmdSenha').value=window.iotmotorSelo?.senhaAtual?.()||'';
  $('cmdSenha').addEventListener('input',()=>window.iotmotorSelo?.definirSenha($('cmdSenha').value));
  $('cmdMostrar')?.addEventListener('click',()=>{
   const campo=$('cmdSenha'),mostrando=campo.type==='text';
   campo.type=mostrando?'password':'text';
   $('cmdMostrar').textContent=mostrando?'Mostrar':'Ocultar';
   $('cmdMostrar').setAttribute('aria-pressed',String(!mostrando));
  });
 }
 buildCards();render();renderAcquisitionConfig();
 $('acqPreset')?.addEventListener('change',()=>{const p=ACQ_PRESETS[$('acqPreset').value];if(!p)return;$('acqPzem').value=String(p.pzem_read_ms/1000);$('acqPublish').value=String(p.publish_ms/1000);$('acqChart').value=String(p.chart_ms/1000);$('acqRecord').value=String(p.record_ms/1000);});
 $('acqForm')?.addEventListener('submit',event=>{event.preventDefault();try{const cfg=lerConfiguracaoAquisicaoForm();if(!window.iotmotorRemoteControls?.raw){diag('Conecte ao MQTT antes de gravar a configuração.');return;}window.iotmotorRemoteControls.raw('acquisition_config_set',{config:cfg});diag('Enviando configuração de aquisição ao ESP32-01…');}catch(e){diag(e.message);}});
 $('connectBtn').addEventListener('click',()=>state.client?disconnect():connect());
 // A pagina abre desconectada: telemetria e comandos so comecam no botao Conectar.
 $('connectionForm').addEventListener('submit',event=>{event.preventDefault();connect();});
 // Original startBtn and stopBtn are wired only by local-controls.js.
 $('exportBtn').addEventListener('click',exportCsv);
 $('limparHistorico')?.addEventListener('click',()=>{
  if(state.records.length&&confirm('Apagar o histórico guardado neste navegador?'))limparRegistros();
 });
 for(const button of document.querySelectorAll('[data-group]'))button.addEventListener('click',()=>{
  state.group=button.dataset.group;for(const b of document.querySelectorAll('[data-group]'))b.setAttribute('aria-pressed',String(button===b));renderCharts();
 });
 setInterval(()=>{
  if(state.pending&&Date.now()-state.pending.at>6500)state.pending=null;
  if(state.connected&&state.subscribed&&(!freshness('command')||!freshness('sensor')))
   diag(`Broker conectado; ${!freshness('command')?'sem dados recentes do quadro de comando':''}${!freshness('command')&&!freshness('sensor')?' e ':''}${!freshness('sensor')?'sem dados recentes dos sensores':''}.`);
  render();
 },1500);
}
if(typeof document!=='undefined')init();
if(typeof module!=='undefined'&&module.exports)module.exports={numeroBr,idadeLeitura,tripText,registroCsv,linhasCsv,celulaCsv,lerCondicao,parseTelemetry,validateConfig,telemetryFresh,deviceConnection,motorVisualState,motorVisualAria,motorLoad,formatDuration,usageLine,maintenanceStatus,maintenanceText,vibrationZone,vibrationText,commandPendingLabel,motorWarnings,motorHeat,temperatureLimit,alarmParts,registrosValidos,chartBucketStart,upsertChartPoint,METRICS};
