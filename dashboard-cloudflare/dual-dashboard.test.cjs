const test=require('node:test');
const assert=require('node:assert/strict');
const {parseTelemetry,validateConfig,deviceConnection,METRICS}=require('./dual-dashboard.js');

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
 assert.equal(deviceConnection({brokerOk:true,status:'—',at:now-15000,now}).kind,'error');
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
