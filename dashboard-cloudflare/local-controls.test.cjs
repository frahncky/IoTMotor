const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {EventEmitter}=require('node:events');
const source=fs.readFileSync(path.join(__dirname,'local-controls.js'),'utf8');
function setup(){
 const nodes=[];
 const host={insertAdjacentElement(_where,node){this.wrapper=node;}};
 const form={addEventListener(){}};
 const document={
  querySelector(selector){return selector==='.control .buttons'?host:null;},
  getElementById(id){return id==='connectionForm'?form:null;},
  createElement(tag){const n={tag,children:[],style:{},attrs:{},append(...children){this.children.push(...children);},setAttribute(k,v){this.attrs[k]=v;},removeAttribute(k){delete this.attrs[k];}};nodes.push(n);return n;}
 };
 let client;
 const context={document,window:{mqtt:{connect(){client=new EventEmitter();client.connected=false;client.subscribe=(topic)=>{client.topic=topic;};client.end=()=>{};return client;}}},localStorage:{getItem(){return null;}},URL,Math,Date,JSON,setInterval(){}};
 vm.runInNewContext(source,context);
 client.connected=true;client.emit('connect');
 return {client,link:host.wrapper.children[2],notice:host.wrapper.children[3]};
}
function send(client,extra={},retained=false){
 const data={device_id:'esp32-01',relay_pins:[19,18,23,27],relays:[false,false,false,false],lcd:['IP:192.168.4.10      ','','',''],...extra};
 client.emit('message',client.topic,Buffer.from(JSON.stringify(data)),{retain:retained});
}
test('opens only the existing local panel when fresh four-relay telemetry provides private IP',()=>{
 const {client,link,notice}=setup();
 assert.equal(link.attrs['aria-disabled'],'true');
 assert.equal(client.publish,undefined);
 send(client);
 assert.equal(link.href,'http://192.168.4.10/');
 assert.equal(link.target,'_blank');
 assert.equal(link.rel,'noopener noreferrer');
 assert.equal(link.attrs['aria-disabled'],undefined);
 assert.match(notice.textContent,/192\.168\.4\.10/);
});
test('rejects retained data, public address, mismatched device and wrong pins',()=>{
 const {client,link}=setup();
 send(client,{},true);
 assert.equal(link.href,undefined);
 send(client,{lcd:['IP:8.8.8.8','','','']});
 assert.equal(link.href,undefined);
 send(client,{device_id:'other'});
 assert.equal(link.href,undefined);
 send(client,{relay_pins:[2,18,23,27]});
 assert.equal(link.href,undefined);
 send(client,{wifi_ip:'10.2.3.4',lcd:['Sem IP','','','']});
 assert.equal(link.href,'http://10.2.3.4/');
});
