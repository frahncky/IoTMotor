const test=require('node:test');
const assert=require('node:assert/strict');
const {parseTelemetry,validateConfig,deviceConnection,motorVisualState,motorWarnings,motorHeat,temperatureLimit,alarmParts,registrosValidos,METRICS}=require('./dual-dashboard.js');

test('indicador de conexao combina telemetria recente e status online/offline',()=>{
 const now=100000;
 assert.equal(deviceConnection({brokerOk:false,status:'online',at:now,now}).label,'broker desconectado');
 assert.equal(deviceConnection({brokerOk:true,status:'—',now}).kind,'');
 assert.equal(deviceConnection({brokerOk:true,status:'online',statusAt:now-500,now}).kind,'wait');
 assert.equal(deviceConnection({brokerOk:true,status:'online',statusAt:now-60000,at:now-2000,now}).kind,'live');
 // LWT offline mais novo que a ultima telemetria derruba o indicador na hora.
 assert.equal(deviceConnection({brokerOk:true,status:'offline',statusAt:now-1000,at:now-3000,now}).kind,'error');
 // Offline retido antigo nao esconde telemetria nova.
 assert.equal(deviceConnection({brokerOk:true,status:'offline',statusAt:now-9000,at:now-1000,now}).kind,'live');
 // A ausencia individual da placa e detectada em cerca de 6 s.
 assert.equal(deviceConnection({brokerOk:true,status:'—',at:now-5000,now}).kind,'live');
 assert.equal(deviceConnection({brokerOk:true,status:'—',at:now-7000,now}).kind,'error');
});

test('animação do diagnóstico segue o estado do motor sem exibir sentido de rotação',()=>{
 assert.deepEqual(motorVisualState({brokerReady:false,commandFresh:false,motorOn:null}),{state:'offline',label:'Desconectado',badge:'SEM DADOS'});
 assert.equal(motorVisualState({brokerReady:true,commandFresh:false,motorOn:null}).state,'waiting');
 assert.equal(motorVisualState({brokerReady:true,commandFresh:true,motorOn:false}).state,'stopped');
 const ligado=motorVisualState({brokerReady:true,commandFresh:true,motorOn:true});
 assert.equal(ligado.state,'running');
 assert.equal(ligado.label,'Motor ligado');
 assert.equal(JSON.stringify(ligado).toLowerCase().includes('horário'),false);
 assert.equal(JSON.stringify(ligado).toLowerCase().includes('anti'),false);
});

test('o historico guardado no navegador descarta o velho e o invalido',()=>{
 const agora=Date.now();
 const linha=(minutosAtras)=>({at:new Date(agora-minutosAtras*60000).toISOString(),voltage:220});
 const guardado=[linha(30*60),linha(25*60),linha(10),linha(1),null,{at:'ontem'},{voltage:1}];
 const mantidos=registrosValidos(guardado);
 // 30 e 25 horas atras saem; o resto fica, na ordem.
 assert.equal(mantidos.length,2);
 assert.equal(mantidos[0].at,linha(10).at);
 assert.equal(mantidos[1].at,linha(1).at);
 assert.deepEqual(registrosValidos('nao e lista'),[]);
 // Fila cheia: fica so o final, que e o mais novo.
 const muitos=Array.from({length:3200},(_,i)=>linha(i%50/60));
 assert.equal(registrosValidos(muitos).length,3000);
});

test('a hora da placa (ts) vale mais que a hora de chegada',()=>{
 // A placa carimba em segundos UTC; so vale depois que o NTP responde.
 const com=parseTelemetry({device_id:'esp32-01',ts:1789920000,voltage:220});
 assert.equal(com.measuredAt,1789920000000);
 assert.equal(new Date(com.measuredAt).toISOString(),'2026-09-20T16:00:00.000Z');
 assert.equal(parseTelemetry({device_id:'esp32-01',voltage:220}).measuredAt,null);
 // Relogio nao sincronizado (segundos desde o boot) nao vira data de 1970.
 assert.equal(parseTelemetry({device_id:'esp32-01',ts:1200}).measuredAt,null);
 assert.equal(parseTelemetry({device_id:'esp32-01',ts:'agora'}).measuredAt,null);
});

test('PZEM: calcula potencias derivadas apenas quando ha dados validos',()=>{
 const x=parseTelemetry({device_id:'esp32-01',data_source:'pzem004t',voltage:220,current:5,power:880,pf:0.8,frequency:60,energy:1.25,motor_on:false,bench_armed:false,seq:12});
 assert.equal(x.deviceId,'esp32-01');
 assert.equal(x.apparent,1100);
 assert.equal(x.reactive,660);
 assert.equal(x.temperature,null);
 assert.equal(x.vibration,null);
 assert.equal(x.demo,false);
});

test('firmware atual deriva motor ligado a partir dos relés quando motor_on não existe',()=>{
 const ligado=parseTelemetry({device_id:'esp32-01',relays:[true,false,false,false],voltage:220});
 const desligado=parseTelemetry({device_id:'esp32-01',relays:[false,false,false,false],voltage:220});
 assert.equal(ligado.motorOn,true);
 assert.equal(desligado.motorOn,false);
 assert.deepEqual(ligado.relays,[true,false,false,false]);
 // Se motor_on vier explicitamente, ele continua tendo prioridade.
 assert.equal(parseTelemetry({device_id:'esp32-01',motor_on:false,relays:[true,false,false,false],voltage:220}).motorOn,false);
});

test('ESP32-S3: vibração/temperatura nao viram dados eletricos inventados',()=>{
 const x=parseTelemetry({device_id:'esp32-02',data_source:'mpu6050_ds18b20',vibration:0.23,vibration_peak:0.7,temperature:37.2});
 assert.equal(x.temperature,37.2);
 assert.equal(x.vibration,0.23);
 assert.equal(x.voltage,null);
 assert.equal(x.current,null);
 assert.equal(x.power,null);
 assert.equal(x.apparent,null);
 assert.equal(x.reactive,null);
 assert.equal(x.motorOn,null);
});

test('valores ausentes nao se tornam zero e modo de demonstracao fica marcado',()=>{
 const x=parseTelemetry({device_id:'esp32-01',demo:true,voltage:null,current:'',power:undefined});
 assert.equal(x.demo,true);
 assert.equal(x.voltage,null);
 assert.equal(x.current,null);
 assert.equal(x.apparent,null);
});

test('dez metricas e IDs distintos com WSS obrigatorio',()=>{
 assert.equal(METRICS.length,10);
 assert.equal(METRICS.filter(m=>m.source==='sensor').length,2);
 assert.equal(validateConfig({broker:'wss://test.mosquitto.org:8081',prefix:'iotmotor',commandDevice:'esp32-01',sensorDevice:'esp32-02'}).broker,'wss://test.mosquitto.org:8081/');
 assert.throws(()=>validateConfig({broker:'ws://test.mosquitto.org:8080',prefix:'iotmotor',commandDevice:'esp32-01',sensorDevice:'esp32-02'}),/wss/);
 assert.throws(()=>validateConfig({broker:'wss://test.mosquitto.org:8081',prefix:'iotmotor',commandDevice:'esp32-01',sensorDevice:'esp32-01'}),/distintos/);
});

test('carcaça do motor esquenta de 30 °C até o limite do alarme de temperatura',()=>{
 assert.equal(motorHeat(null,60),null);
 assert.equal(motorHeat(25,60),0);
 assert.equal(motorHeat(45,60),0.5);
 assert.equal(motorHeat(60,60),1);
 assert.equal(motorHeat(90,60),1);
 // Limite baixo: a escala começa 10 °C abaixo dele.
 assert.equal(motorHeat(30,35),0.5);
 assert.equal(temperatureLimit(null),60);
 assert.equal(temperatureLimit([
  {id:'a',field:'temperature',above:true,limit:70,on:true},
  {id:'b',field:'temperature',above:true,limit:50,on:false},
  {id:'c',field:'temperature',above:false,limit:5,on:true},
  {id:'d',field:'temperature',limit:65}]),65);
});

test('alarmes disparados indicam a parte do motor afetada',()=>{
 assert.deepEqual([...alarmParts([],null)],[]);
 // Sem a lista retida, os ids padrão da placa ainda são reconhecidos.
 assert.deepEqual([...alarmParts(['temp','vib'],null)].sort(),['temperature','vibration']);
 const lista=[{id:'quente',field:'temperature'},{id:'rms',field:'vibration'},{id:'tensao',field:'voltage'}];
 assert.deepEqual([...alarmParts(['quente'],lista)],['temperature']);
 assert.deepEqual([...alarmParts(['rms'],lista)],['vibration']);
 assert.deepEqual([...alarmParts(['tensao','desconhecido'],lista)],['other']);
 const s=parseTelemetry({device_id:'esp32-02',alarm_enabled:true,alarms_firing:['temp',3,'']});
 assert.equal(s.alarmEnabled,true);
 assert.deepEqual(s.alarmsFiring,['temp']);
 assert.deepEqual(parseTelemetry({device_id:'esp32-02'}).alarmsFiring,[]);
});

test('avisos do motor: grandezas sem leitura e valores perto ou além do limite',()=>{
 const textos=a=>a.map(w=>`${w.level}|${w.text}`);
 const cmd={voltage:220,current:3.9,power:800,pf:0.9,frequency:60,energy:1.2};
 assert.deepEqual(motorWarnings({brokerReady:false,command:null,sensor:null,alarms:null}),[]);
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:null,sensor:null,alarms:null})),
  ['warn|Sensores do motor sem dados','warn|Quadro de comando sem dados']);
 // Placa de sensores enviando, mas sem temperatura.
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:cmd,sensor:{vibration:0.02,temperature:null,vibrationPeak:0.05},alarms:null})),
  ['warn|Temperatura sem leitura']);
 // Quadro sem nenhuma medição do PZEM vira um único aviso.
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:{voltage:null,current:null},sensor:{vibration:0.02,temperature:30},alarms:null})),
  ['warn|Medições elétricas (PZEM) sem leitura']);
 // Limites de fábrica: 90% avisa, no limite vira alarme.
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:cmd,sensor:{vibration:0.1,temperature:55,vibrationPeak:0.6},alarms:null})),
  ['alarm|Vibração (pico) alta: 0.60 g (limite 0.5 g)','warn|Temperatura alta: 55.0 °C (limite 60 °C)']);
 // Lista da placa: limites próprios, alarmes desligados ignorados, "abaixo de" também.
 const alarms=[{id:'t',field:'temperature',above:true,limit:40,on:true},{id:'i',field:'current',above:true,limit:4,on:false},
  {id:'v',field:'voltage',above:false,limit:200,on:true}];
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:{...cmd,voltage:210},sensor:{vibration:0.1,temperature:41},alarms})),
  ['alarm|Temperatura alta: 41.0 °C (limite 40 °C)','warn|Tensão baixa: 210.0 V (limite 200 V)']);
});
