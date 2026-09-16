const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {EventEmitter}=require('node:events');
const source=fs.readFileSync(path.join(__dirname,'hardware-mirror.js'),'utf8');
function browser(){
 const nodes=new Map(),clients=[];
 const get=id=>{
  if(!nodes.has(id))nodes.set(id,{id,value:'',textContent:'',className:'',listeners:{},addEventListener(type,cb){this.listeners[type]=cb;}});
  return nodes.get(id);
 };
 const document={getElementById:get};
 const ctx={document,URL,JSON,Number,String,Math,Date,setInterval(){},localStorage:{getItem(){return null;},setItem(){}},window:{mqtt:{connect(url){
  const c=new EventEmitter();c.url=url;c.subscribe=(topics,_opts,cb)=>{c.topics=topics;cb(null);};c.end=()=>{};clients.push(c);return c;
 }}}};
 vm.runInNewContext(source,ctx,{filename:'hardware-mirror.js'});
 get('configForm').listeners.submit({preventDefault(){}});
 const client=clients[0];client.emit('connect');
 return {get,client};
}
test('four-relay telemetry reproduces exact 20x4 LCD cache and outputs',()=>{
 const {get,client}=browser();
 assert.equal(client.url,'wss://test.mosquitto.org:8081/');
 assert.equal(client.publish,undefined,'monitor must never publish commands');
 assert.deepEqual([...client.topics],['iotmotor/esp32-01/telemetry','iotmotor/esp32-01/status']);
 const rows=['IP:192.168.1.25     ','V:220.1  I:  2.30A  ','P: 420W E: 0.12kWh ','ESTRELA 12-4 MQ     '];
 const message={device_id:'esp32-01',state:'estrela',mode:'star_delta',pzem_ok:true,relays:[true,true,false,true],lcd:rows,voltage:220.1,current:2.3,power:420,energy:.12};
 client.emit('message','iotmotor/esp32-01/telemetry',Buffer.from(JSON.stringify(message)),{retain:false});
 assert.equal(get('lcdText').textContent,rows.map(v=>v.slice(0,20).padEnd(20)).join('\n'));
 assert.equal(get('relayText0').textContent,'Comando LIGADO');
 assert.equal(get('relayText1').textContent,'Comando LIGADO');
 assert.equal(get('relayText2').textContent,'Comando DESLIGADO');
 assert.equal(get('relayText3').textContent,'Comando LIGADO');
 assert.match(get('lcdSource').textContent,/Espelho do buffer/);
 assert.match(get('relaySource').textContent,/sem feedback físico/);
});
test('old firmware is clearly marked as an approximation; retained telemetry ignored',()=>{
 const {get,client}=browser();
 const m={device_id:'esp32-01',state:'tempo_morto',mode:'star_delta',pzem_ok:true,voltage:220,current:3,power:600,energy:0.5};
 client.emit('message','iotmotor/esp32-01/telemetry',Buffer.from(JSON.stringify(m)),{retain:true});
 assert.equal(get('messageCount').textContent,'0');
 client.emit('message','iotmotor/esp32-01/telemetry',Buffer.from(JSON.stringify(m)),{retain:false});
 assert.equal(get('relayText0').textContent,'Comando LIGADO');
 assert.equal(get('relayText1').textContent,'Comando DESLIGADO');
 assert.equal(get('relayText2').textContent,'Comando DESLIGADO');
 assert.match(get('lcdSource').textContent,/Prévia calculada/);
 assert.match(get('relaySource').textContent,/Estados previstos/);
});
