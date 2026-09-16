'use strict';
/* A mesma tela funciona no Cloudflare (monitoramento) e servida pelo ESP32 (controle LAN).
 * Nunca publica comandos num broker MQTT público nem faz HTTP misto a partir de HTTPS. */
(() => {
  const $=id=>document.getElementById(id);
  const control=document.querySelector('.control');
  if (!control) return;
  for (const id of ['startBtn','starBtn','stopBtn']) { const node=$(id); if(node) node.hidden=true; }
  const onLan=location.protocol==='http:' && (/^(?:10|192\.168|172\.(?:1[6-9]|2\d|3[01]))\./.test(location.hostname)||location.hostname==='modulo1.local');
  const box=document.createElement('section');
  box.style.cssText='border:1px solid #50778a;border-radius:12px;padding:16px;background:#0a2936;margin:12px 0';
  box.innerHTML=`<h3 style="font-size:18px">Partida e seleção de relés · K1–K4</h3>
    <p class="muted" id="controlHint">Controle local do ESP32. As saídas são estados lógicos, não confirmação de contatores.</p>
    <div class="field"><label for="startMode">Tipo de partida</label><select id="startMode" style="padding:9px;background:#102e3b;color:white;border:1px solid #608697;border-radius:8px"><option value="direct">Direta · relés selecionados</option><option value="sequence">Sequência de bancada · principal, estrela e triângulo</option></select></div>
    <div id="directSelect" style="margin:12px 0"><span class="muted">Relés acionados na partida direta:</span><div id="directChannels" class="buttons"></div></div>
    <div id="sequenceSelect" hidden style="margin:12px 0"><p class="muted">Sequência apenas para testes com relés desconectados de motor/contatores. Não substitui intertravamento físico.</p><div class="fields" style="display:flex;flex-wrap:wrap"><label>Principal <select id="mainRelay"></select></label><label>Estrela <select id="starRelay"></select></label><label>Triângulo <select id="deltaRelay"></select></label><label>Tempo estrela (s) <input id="starSeconds" type="number" min="2" max="30" step="1" value="5" style="width:70px"></label></div></div>
    <div class="buttons"><button id="profileStart" class="btn" type="button" disabled>▶ Ligar / Iniciar</button><button id="profileStop" class="btn danger" type="button" disabled>■ Desligar todos</button></div>
    <p id="profileStatus" class="feedback" aria-live="polite">Aguardando estado do ESP32.</p>
    <div class="muted" id="relayStatuses">K1 GPIO19 · K2 GPIO18 · K3 GPIO23 · K4 GPIO27</div>
    <pre id="physicalLcd" style="white-space:pre;font:14px/1.4 monospace;max-width:100%;overflow:auto;background:#051b26;padding:12px;border:1px solid #466878;border-radius:9px;margin:12px 0">LCD 20×4 · aguardando dados</pre>
    <div id="remoteEntry" hidden><label class="muted" for="localIp">IP informado na primeira linha do LCD físico</label><div class="buttons"><input id="localIp" inputmode="decimal" placeholder="192.168.1.100" style="background:#051b26;border:1px solid #466878;color:#fff;padding:9px;border-radius:8px"><button id="sameTab" class="btn secondary" type="button">Abrir esta tela no ESP32 (mesma aba)</button></div><p class="muted">No endereço HTTPS do Cloudflare os comandos locais não podem ser executados. O mesmo dashboard, servido pelo IP do ESP32, controla os relés sem abrir outra aba.</p></div>`;
  control.append(box);
  const pins=[19,18,23,27];let busy=false, snapshot=null, lastAt=0, mqtt=null;
  const privateIp=value=>{if(typeof value!=='string'||!/^\d{1,3}(?:\.\d{1,3}){3}$/.test(value))return null;const p=value.split('.').map(Number);if(p.some(x=>x>255))return null;return (p[0]===10||p[0]===192&&p[1]===168||p[0]===172&&p[1]>=16&&p[1]<=31)?p.join('.'):null;};
  const direct=$('directChannels');
  pins.forEach((pin,i)=>{const label=document.createElement('label');label.style.cssText='display:inline-flex;align-items:center;gap:5px';const input=document.createElement('input');input.type='checkbox';input.value=String(i+1);input.checked=i===0;input.className='directRelay';label.append(input,document.createTextNode(`K${i+1} · GPIO${pin}`));direct.append(label);});
  for(const id of ['mainRelay','starRelay','deltaRelay']){const select=$(id);pins.forEach((pin,i)=>select.add(new Option(`K${i+1} · GPIO${pin}`,String(i+1))));}
  $('mainRelay').value='1';$('starRelay').value='2';$('deltaRelay').value='3';
  $('startMode').addEventListener('change',()=>{const seq=$('startMode').value==='sequence';$('directSelect').hidden=seq;$('sequenceSelect').hidden=!seq;});
  function show(data){snapshot=data;lastAt=Date.now();const relays=data.reles||data.relays;const valid=Array.isArray(relays)&&relays.length===4;
    $('relayStatuses').textContent=valid?relays.map((on,i)=>`K${i+1} GPIO${pins[i]}: ${on?'LIGADO':'desligado'}`).join(' · '):'Sem estados válidos dos relés';
    const rows=data.lcd||data.lcd_lines;if(Array.isArray(rows)&&rows.length===4)$('physicalLcd').textContent=rows.map(x=>String(x).slice(0,20).padEnd(20)).join('\n');
    if(onLan){$('profileStatus').textContent=`${data.partida_etapa||'Parado'} · ${data.armado?'habilitação física presente':'GPIO32 sem jumper: partida bloqueada'}`;
      $('profileStart').disabled=busy||!valid||!data.armado||relays.some(Boolean);
      $('profileStop').disabled=busy||!valid;
    }
  }
  async function poll(){if(!onLan||busy)return;try{const res=await fetch('/dados',{cache:'no-store'});if(!res.ok)throw Error('HTTP '+res.status);show(await res.json());}catch(e){$('profileStart').disabled=true;$('profileStop').disabled=true;$('profileStatus').textContent='ESP32 não respondeu: '+e.message;}}
  async function post(path,params){if(busy)return;busy=true;$('profileStart').disabled=true;$('profileStop').disabled=true;$('profileStatus').textContent='Pedido enviado; aguardando resposta e estado dos pinos…';try{const res=await fetch(path,{method:'POST',body:new URLSearchParams(params),cache:'no-store'});const message=await res.text();if(!res.ok)throw Error(`${res.status}: ${message}`);$('profileStatus').textContent='Comando recebido pelo ESP32; conferindo saídas…';}catch(e){$('profileStatus').textContent='Falha: '+e.message;}finally{busy=false;await poll();}}
  $('profileStart').addEventListener('click',()=>{if(!onLan||!snapshot?.armado)return;const mode=$('startMode').value;let args={modo:mode};if(mode==='direct'){let mask=0;document.querySelectorAll('.directRelay:checked').forEach(x=>mask|=1<<(Number(x.value)-1));if(!mask){$('profileStatus').textContent='Selecione pelo menos um relé.';return;}args.mascara=String(mask);}else{const chosen=[$('mainRelay').value,$('starRelay').value,$('deltaRelay').value];if(new Set(chosen).size!==3){$('profileStatus').textContent='Principal, estrela e triângulo devem ser relés distintos.';return;}Object.assign(args,{principal:chosen[0],estrela:chosen[1],triangulo:chosen[2],tempo:$('starSeconds').value});}if(window.confirm('TESTE EM BANCADA SEM MOTOR NEM CONTATORES: confirmar partida dos relés selecionados?'))post('/partida',args);});
  $('profileStop').addEventListener('click',()=>onLan&&post('/parar',{}));
  if(onLan){$('controlHint').textContent='Controle na mesma página, servido pelo ESP32 na rede local. Jumper GPIO32–GND obrigatório para energizar; desligamento sempre disponível.';poll();setInterval(poll,1200);return;}
  $('remoteEntry').hidden=false;$('profileStatus').textContent='Monitoramento remoto: controle somente na mesma tela servida pelo ESP32 na rede local.';
  $('sameTab').addEventListener('click',()=>{const ip=privateIp($('localIp').value.trim());if(!ip){$('profileStatus').textContent='Informe um IPv4 privado válido conferido no LCD.';return;}if(window.confirm(`Abrir http://${ip}/ nesta mesma aba? Confirme o IP exibido no LCD do ESP32.`))location.assign(`http://${ip}/`);});
  if(!window.mqtt?.connect)return;
  let config={};try{config=JSON.parse(localStorage.getItem('iotmotor_dashboard_dual_v1')||'{}')||{};}catch{}
  let broker;try{broker=new URL(config.broker||'wss://test.mosquitto.org:8081');}catch{return;}
  if(broker.protocol!=='wss:'||broker.username||broker.password)return;
  const prefix=String(config.prefix||'iotmotor'),device=String(config.commandDevice||'esp32-01');
  if(!/^[\w-]+(?:\/[\w-]+)*$/.test(prefix)||!/^[\w-]+$/.test(device))return;
  const telemetryTopic=`${prefix}/${device}/telemetry`;
  mqtt=window.mqtt.connect(broker.toString(),{clientId:`iotmotor_local_${Math.random().toString(36).slice(2,11)}`,clean:true,reconnectPeriod:4000});
  mqtt.on('connect',()=>mqtt.subscribe(telemetryTopic));
  mqtt.on('message',(topic,buffer,packet)=>{if(topic!==telemetryTopic||packet?.retain)return;let d;try{d=JSON.parse(buffer.toString());}catch{return;}if(d?.device_id!==device||!Array.isArray(d.relay_pins)||d.relay_pins.join(',')!=='19,18,23,27')return;const ip=privateIp(d.wifi_ip)||privateIp((String(d.lcd?.[0]||'').match(/IP:\s*(\d{1,3}(?:\.\d{1,3}){3})/)||[])[1]);if(ip&&!$('localIp').value)$('localIp').value=ip;show({reles:d.relays,lcd:d.lcd});$('profileStatus').textContent='Monitoramento disponível. Confirme o IP físico e abra esta mesma tela na rede local para comandar.';});
})();
