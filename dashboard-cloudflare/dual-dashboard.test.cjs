const test=require('node:test');
const assert=require('node:assert/strict');
const {numeroBr,idadeLeitura,tripText,registroCsv,linhasCsv,celulaCsv,parseTelemetry,validateConfig,telemetryFresh,deviceConnection,motorVisualState,motorVisualAria,motorLoad,formatDuration,usageLine,commandPendingLabel,motorWarnings,maintenanceStatus,maintenanceText,vibrationZone,vibrationText,motorHeat,temperatureLimit,alarmParts,registrosValidos,chartBucketStart,upsertChartPoint,METRICS}=require('./dual-dashboard.js');

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
 // A ausencia individual da placa e detectada em 10 s.
 assert.equal(deviceConnection({brokerOk:true,status:'—',at:now-9000,now}).kind,'live');
 assert.equal(deviceConnection({brokerOk:true,status:'—',at:now-10000,now}).kind,'error');
});

test('estado ligado expira em 10 s e offline confirmado invalida imediatamente',()=>{
 const now=100000;
 assert.equal(telemetryFresh({brokerReady:true,status:'online',at:now-9999,now}),true);
 assert.equal(telemetryFresh({brokerReady:true,status:'online',at:now-10000,now}),false);
 assert.equal(telemetryFresh({brokerReady:true,status:'offline',statusAt:now-1000,at:now-2000,now}),false);
 assert.equal(telemetryFresh({brokerReady:true,status:'offline',statusAt:now-3000,at:now-1000,now}),true);
});

test('OTA tem prioridade visual sobre o estado normal das duas placas',()=>{
 const now=100000;
 assert.deepEqual(deviceConnection({brokerOk:true,status:'online',statusAt:now,at:now,now,firmwareState:'updating'}),
  {label:'atualizando firmware',kind:'wait'});
 assert.deepEqual(deviceConnection({brokerOk:true,status:'online',statusAt:now,at:now,now,firmwareState:'updated'}),
  {label:'atualizado · conectado',kind:'live'});
});

test('animação do diagnóstico segue o estado do motor sem exibir sentido de rotação',()=>{
 assert.deepEqual(motorVisualState({brokerReady:false,commandFresh:false,motorOn:null}),{state:'offline',label:'Desconectado'});
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
 const guardado=[linha(30*60),linha(61),linha(10),linha(1),null,{at:'ontem'},{voltage:1}];
 const mantidos=registrosValidos(guardado);
 // Mais de uma hora atras sai; o resto fica, na ordem.
 assert.equal(mantidos.length,2);
 assert.equal(mantidos[0].at,linha(10).at);
 assert.equal(mantidos[1].at,linha(1).at);
 assert.deepEqual(registrosValidos('nao e lista'),[]);
 // Fila cheia: fica so o final, que e o mais novo.
 const muitos=Array.from({length:7500},(_,i)=>linha(i%50/60));
 assert.equal(registrosValidos(muitos).length,7200);
});

test('a linha guardada junta as duas placas e só tem as colunas do CSV',()=>{
 const cmd=parseTelemetry({device_id:'esp32-01',ts:1790000000,voltage:220,current:5,relays:[true,false,false,false],
  motor_running:true,mode:'direct',profile:'direta',session_s:42,pzem_ok:true,lcd:['a','b'],wifi_ip:'10.0.0.1'});
 const sen=parseTelemetry({device_id:'esp32-02',ts:1790000001,vibration_mms:2.5,vibration_axis:'y',temperature:41.5,
  mpu_ok:true,temperature_ok:true,sample_count:998});
 const linha=registroCsv({command:cmd,sensor:sen,at:0,condicao:' desbalanceamento '});
 assert.equal(linha.at,new Date(1790000000*1000).toISOString());
 assert.equal(linha.clockSource,'placa');
 assert.equal(linha.condicao,'desbalanceamento');
 assert.equal(linha.voltage,220);
 assert.equal(linha.vibration_mms,2.5);
 assert.equal(linha.temperature,41.5);
 assert.equal(linha.motorOn,true);
 assert.deepEqual(linha.relays,[true,false,false,false]);
 assert.equal(linha.sessionS,42);
 assert.equal(linha.vibrationAxis,'y');
 assert.equal(linha.sampleCount,998);
 assert.equal('lcd' in linha||'wifiIp' in linha,false);
 // Só os sensores (quadro fora do ar): as colunas elétricas ficam vazias.
 const soSensor=registroCsv({sensor:sen,at:0});
 assert.equal(soSensor.at,new Date(1790000001*1000).toISOString());
 assert.equal('voltage' in soSensor||'motorOn' in soSensor,false);
});

test('CSV de treino: cabeçalho fixo, contatores em colunas e texto escapado',()=>{
 const cmd=parseTelemetry({device_id:'esp32-01',voltage:220,relays:[false,true,false,false],motor_running:true});
 const [cab,linha]=linhasCsv([registroCsv({command:cmd,at:Date.UTC(2026,8,30),condicao:'folga, base "solta"'})]);
 const colunas=cab.split(',');
 assert.deepEqual(colunas.slice(0,9),['measured_at','clock_source','demo','condition','motor_running','bench_armed','mode','profile','session_s']);
 assert.ok(colunas.includes('relay_4')&&colunas.includes('vibration_axis')&&colunas.at(-1)==='temperature');
 assert.match(linha,/^2026-09-30T00:00:00\.000Z,navegador,false,"folga, base ""solta""",true,/);
 assert.match(linha,/,false,true,false,false,/);
 assert.equal(celulaCsv(null),'');
 assert.equal(celulaCsv('a\nb'),'"a\nb"');
});

test('modo instrumentacao: motor_running vale como motor ligado sem rele',()=>{
 const girando=parseTelemetry({device_id:'esp32-01',relays:[false,false,false,false],motor_running:true,current:4});
 assert.equal(girando.motorOn,true);
 assert.equal(parseTelemetry({device_id:'esp32-01',relays:[false,false,false,false],motor_running:false}).motorOn,false);
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
 assert.equal(x.vibration_mms,null);
 assert.equal(x.demo,false);
});

test('firmware atual deriva motor ligado a partir dos relés quando motor_on não existe',()=>{
 const ligado=parseTelemetry({device_id:'esp32-01',relays:[true,false,false,false],profile:'estrela-triangulo',voltage:220});
 const desligado=parseTelemetry({device_id:'esp32-01',relays:[false,false,false,false],voltage:220});
 assert.equal(ligado.motorOn,true);
 assert.equal(desligado.motorOn,false);
 assert.deepEqual(ligado.relays,[true,false,false,false]);
 assert.equal(ligado.profile,'estrela-triangulo');
 // Se motor_on vier explicitamente, ele continua tendo prioridade.
 assert.equal(parseTelemetry({device_id:'esp32-01',motor_on:false,relays:[true,false,false,false],voltage:220}).motorOn,false);
});

test('ESP32-S3: vibração/temperatura nao viram dados eletricos inventados',()=>{
 const x=parseTelemetry({device_id:'esp32-02',data_source:'mpu6050_ds18b20',vibration_mms:2.3,temperature:37.2});
 assert.equal(x.temperature,37.2);
 assert.equal(x.vibration_mms,2.3);
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
 assert.equal(new Set(METRICS.map(m=>m.key)).size,10);
 assert.equal(METRICS.filter(m=>m.source==='sensor').length,2);
 assert.ok(!METRICS.some(m=>m.unit==='g'),'aceleração em g não é mostrada');
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
 const lista=[{id:'quente',field:'temperature'},{id:'rms',field:'vibration_mms'},{id:'tensao',field:'voltage'}];
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
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:cmd,sensor:{vibration_mms:0.3,temperature:null},alarms:null})),
  ['warn|Temperatura sem leitura']);
 // Quadro sem nenhuma medição do PZEM vira um único aviso.
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:{voltage:null,current:null},sensor:{vibration_mms:0.3,temperature:30},alarms:null})),
  ['warn|Medições elétricas (PZEM) sem leitura']);
 // Limites de fábrica: 90% avisa, no limite vira alarme.
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:cmd,sensor:{vibration_mms:5,temperature:55},alarms:null})),
  ['alarm|Vibração RMS alta: 5,00 mm/s (limite 4,5 mm/s)','warn|Temperatura alta: 55,0 °C (limite 60 °C)']);
 // Lista da placa: limites próprios, alarmes desligados ignorados, "abaixo de" também.
 const alarms=[{id:'t',field:'temperature',above:true,limit:40,on:true},{id:'i',field:'current',above:true,limit:4,on:false},
  {id:'v',field:'voltage',above:false,limit:200,on:true}];
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:{...cmd,voltage:210},sensor:{vibration_mms:1,temperature:41},alarms})),
  ['alarm|Temperatura alta: 41,0 °C (limite 40 °C)','warn|Tensão baixa: 210,0 V (limite 200 V)']);
});

test('avisos de limite seguem o firmware: estrito, o mais grave vale e nada com alarme desligado',()=>{
 const textos=a=>a.map(w=>`${w.level}|${w.text}`);
 const cmd={voltage:220,current:3.9,power:800,pf:0.9,frequency:60,energy:1.2};
 // Exatamente no limite: a placa não dispara (valor > limite), então é só aviso.
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:cmd,sensor:{vibration_mms:1,temperature:60},alarms:null})),
  ['warn|Temperatura alta: 60,0 °C (limite 60 °C)']);
 // Dois alarmes de temperatura: o de 60 °C disparou mesmo vindo depois do de 100 °C.
 const dois=[{id:'a',field:'temperature',above:true,limit:100,on:true},{id:'b',field:'temperature',above:true,limit:60,on:true}];
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:cmd,sensor:{vibration_mms:1,temperature:95},alarms:dois})),
  ['alarm|Temperatura alta: 95,0 °C (limite 60 °C)']);
 // Monitoramento desligado: sem avisos de limite, mas a falta de leitura continua.
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:cmd,sensor:{alarmEnabled:false,vibration_mms:null,temperature:95},alarms:dois})),
  ['warn|Vibração sem leitura']);
 // Só a vibração em mm/s conta: aceleração em g (firmware antigo) é falta de leitura.
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:cmd,sensor:{vibration_mms:1.2,temperature:30},alarms:[]})),[]);
 assert.deepEqual(textos(motorWarnings({brokerReady:true,command:cmd,sensor:parseTelemetry({device_id:'esp32-02',vibration:0.02,temperature:30}),alarms:[]})),
  ['warn|Vibração sem leitura']);
});

test('carga do motor usa a corrente nominal cadastrada e some sem ela',()=>{
 assert.equal(motorLoad(3.9,5),78);
 assert.equal(motorLoad(3.9,null),null);
 assert.equal(motorLoad(3.9,0),null);
 assert.equal(motorLoad(null,5),null);
});

test('linha de uso: sessão, horímetro e partidas do quadro de comando',()=>{
 assert.equal(formatDuration(42),'42 s');
 assert.equal(formatDuration(725),'12 min');
 assert.equal(formatDuration(3900),'1 h 05 min');
 assert.equal(usageLine({sessionS:725,runSTotal:124200,startsToday:3,startsTotal:120}),
  'Ligado há 12 min · Horímetro 34,5 h · 3 partidas hoje');
 // Sem relógio na placa não há "hoje": mostra o total.
 assert.equal(usageLine({sessionS:null,runSTotal:3600,startsToday:null,startsTotal:1}),'Horímetro 1,0 h · 1 partida no total');
 // Firmware antigo, sem os campos: nada a mostrar.
 assert.equal(usageLine({}),'');
 const s=parseTelemetry({device_id:'esp32-01',run_s_total:100,starts_total:4,starts_today:2,session_s:30});
 assert.deepEqual([s.runSTotal,s.startsTotal,s.startsToday,s.sessionS],[100,4,2,30]);
});

test('comando enviado mostra "aguardando o quadro" até o estado mudar',()=>{
 assert.equal(commandPendingLabel(null,false),null);
 assert.equal(commandPendingLabel({action:'start'},false),'Ligando…');
 assert.equal(commandPendingLabel({action:'start'},true),null);
 assert.equal(commandPendingLabel({action:'stop'},true),'Desligando…');
 assert.equal(commandPendingLabel({action:'stop'},false),null);
});

test('manutenção pelo horímetro: em dia, perto e vencida, com aviso em Alarmes ativos',()=>{
 const info={maint_interval_h:2000,maint_done_run_s:3600*100};
 assert.equal(maintenanceStatus({},3600),null,'sem intervalo cadastrado');
 assert.equal(maintenanceStatus(info,null),null,'sem horímetro');
 const emDia=maintenanceStatus(info,3600*600);
 assert.deepEqual([emDia.restanteH,emDia.vencida,emDia.perto],[1500,false,false]);
 const perto=maintenanceStatus(info,3600*1950);
 assert.equal(perto.perto,true);
 assert.equal(maintenanceText(perto),'Próxima manutenção em 150 h de uso (a cada 2000 h)');
 const vencida=maintenanceStatus(info,3600*2100+1800);
 assert.equal(vencida.vencida,true);
 assert.equal(maintenanceText(vencida),'Manutenção vencida há 0,5 h de uso (a cada 2000 h)');
 const cmd={voltage:220,current:1,power:null,pf:null,frequency:null,energy:null};
 const sensor={vibration_mms:0.3,temperature:30};
 const avisos=motorWarnings({brokerReady:true,command:cmd,sensor,alarms:[],maintenance:vencida});
 assert.deepEqual(avisos.map(a=>a.kind),['maintenance']);
 assert.equal(motorWarnings({brokerReady:true,command:cmd,sensor,alarms:[],maintenance:emDia}).length,0);
});

test('partidas na última hora: lidas da telemetria e avisadas perto do limite',()=>{
 const cmd=parseTelemetry({device_id:'esp32-01',voltage:220,current:1,starts_hour:6});
 assert.equal(cmd.startsHour,6);
 const sensor={vibration_mms:0.3,temperature:30};
 const alarmes=[{id:'partidas',field:'starts_hour',above:true,limit:6,on:true}];
 assert.deepEqual(motorWarnings({brokerReady:true,command:cmd,sensor,alarms:alarmes}).map(a=>a.text),
  ['Partidas na última hora alta: 6 (limite 6)']);
});

test('vibração medida em mm/s pela placa: zona direta, sem precisar da rotação',()=>{
 assert.equal(vibrationZone(0.5,null).label,'Boa');       // Sem potência: máquina pequena.
 assert.equal(vibrationZone(2.3,5).label,'Alerta');
 assert.equal(vibrationZone(2.3,50).label,'Aceitável');
 assert.equal(vibrationZone(12,500).label,'Crítica');
 assert.equal(vibrationZone(NaN,5),null);
 // O cartão prefere a medida em mm/s; classifica só com o motor girando.
 assert.deepEqual(vibrationText({vibration:0.2,vibration_mms:1.234},true,{power_cv:5}),
  {texto:'Vibração 1,23 mm/s · Aceitável',iso:{mmS:1.234,zona:1,label:'Aceitável'}});
 assert.equal(vibrationText({vibration:0.2,vibration_mms:1.234},false,null).texto,'Vibração 1,23 mm/s');
 // Só aceleração em g (firmware antigo): não é mostrada.
 assert.equal(vibrationText({vibration:0.01},true,{rpm:1800,power_cv:5}),null);
 assert.equal(vibrationText({},true,null),null);
 assert.equal(parseTelemetry({device_id:'esp32-02',vibration:0.1,vibration_mms:2.5}).vibration_mms,2.5);
});

test('desarme: o cartão diz qual alarme desligou o motor, só com ele parado',()=>{
 const x=parseTelemetry({device_id:'esp32-01',relays:[false,false,false,false],trip_alarm:'temp',trip_field:'temperature'});
 assert.equal(x.tripField,'temperature');
 assert.equal(tripText(x.tripField,x.motorOn),'Desligado pelo alarme de temperatura');
 assert.equal(tripText('current',true),'');
 assert.equal(tripText('vibration_mms',false),'Desligado pelo alarme de vibração');
 assert.equal(parseTelemetry({device_id:'esp32-01',relays:[false,false,false,false]}).tripField,'');
});


test('grafico usa janelas temporais exatas e consolida pela media',()=>{
 const serie=[];
 assert.equal(chartBucketStart(12001,5000),10000);
 assert.equal(chartBucketStart(14999,5000),10000);
 assert.equal(chartBucketStart(15000,5000),15000);

 upsertChartPoint(serie,12001,220,5000);
 upsertChartPoint(serie,14999,230,5000);
 upsertChartPoint(serie,16000,240,5000);

 assert.equal(serie.length,2);
 assert.equal(serie[0].t,10000);
 assert.equal(serie[0].v,225);
 assert.equal(serie[1].t,15000);
 assert.equal(serie[1].v,240);
});
test('desenho do motor tem texto para leitor de tela com os alarmes',()=>{
 assert.equal(motorVisualAria('Motor ligado',new Set()),'Desenho do motor: Motor ligado');
 assert.equal(motorVisualAria('Motor ligado',new Set(['temperature','vibration'])),'Desenho do motor: Motor ligado, alarme de temperatura, alarme de vibração');
 assert.equal(motorVisualAria('Desconectado',null),'Desenho do motor: Desconectado');
});
test('números da tela usam vírgula decimal', () => {
 assert.equal(numeroBr(220.15,1), '220,2');
 assert.equal(numeroBr(8.7,2), '8,70');
 assert.equal(numeroBr(3022,0), '3022');
});
test('última leitura aparece como idade, não como horário', () => {
 const agora=1_000_000_000;
 assert.equal(idadeLeitura(0,agora), '—');
 assert.equal(idadeLeitura(agora-2400,agora), 'há 2 s');
 assert.equal(idadeLeitura(agora-125000,agora), 'há 2 min');
 assert.equal(idadeLeitura(agora-2*3600e3,agora), 'há 2 h');
 assert.equal(idadeLeitura(agora+500,agora), 'há 0 s');  // relógio do navegador adiantado
});
