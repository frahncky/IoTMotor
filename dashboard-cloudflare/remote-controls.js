'use strict';
/* Comandos MQTT autenticados no MESMO dashboard HTTPS. A chave nao e salva,
 * publicada em topicos, transmitida em texto puro nem embutida no repositorio.
 * Os botoes existentes sao usados; o firmware aplica habilitacao e timeout. */
(() => {
  if (location.protocol !== 'https:') return; // A interface HTTP local ja comanda diretamente.
  const $ = id => document.getElementById(id);
  const start = $('startBtn'), stop = $('stopBtn'), control = document.querySelector('.control');
  if (!start || !stop || !control) return;
  const box = document.createElement('div');
  box.style.cssText = 'margin:12px 0;padding:13px;border:1px solid #547f8d;border-radius:10px;background:#092633';
  box.innerHTML = `<label for="mqttControlKey" style="display:block;font-size:13px;margin-bottom:6px">Chave da placa (32 caracteres hexadecimais; Monitor Serial a 115200)</label>
    <input id="mqttControlKey" type="password" minlength="32" maxlength="32" pattern="[0-9a-fA-F]{32}" autocomplete="off" spellcheck="false" placeholder="Cole a chave exibida pelo ESP32" style="width:100%;background:#071d2a;border:1px solid #597d8c;color:#fff;border-radius:8px;padding:10px" />
    <p class="muted" style="margin:8px 0 0">A chave fica somente nesta pagina durante a sessao; nenhum login ou servidor adicional. Retire o jumper GPIO32 para interromper imediatamente as saidas.</p>`;
  control.append(box);
  const instruction = $('localInstruction');
  if (instruction) instruction.hidden = true;
  const status = $('profileStatus');
  let client = null, connected = false, device = '', prefix = '', boot = '', lastAt = 0;
  let currentRelays = null, armed = false, busy = false, pendingSeq = '', lastSeq = 0;
  let latestStatus = 'Aguardando conexao MQTT e chave da placa.';
  let legacyAt = 0; // ESP32 enviou telemetria sem identificador de firmware remoto.
  const keyInput = $('mqttControlKey');
  const signedTopic = () => `${prefix}/${device}/command`;
  const validKey = () => /^[a-f0-9]{32}$/i.test(keyInput.value.trim());
  const fresh = () => Boolean(boot && Date.now() - lastAt < 10000 && currentRelays);
  function blockedReason() {
    if (!window.crypto?.subtle) return 'Navegador sem Web Crypto: abra a página via HTTPS.';
    if (!connected) return 'Conexão MQTT indisponível: use Conectar ao MQTT e confira o broker WSS.';
    if (!boot && legacyAt && Date.now()-legacyAt < 10000)
      return 'O ESP32 envia dados, mas usa firmware antigo. Grave o firmware de comandos mais recente (com MQTT de comandos) na placa.';
    if (!fresh()) return 'Aguardando telemetria recente do ESP32-01 com boot e estados K1–K4; confira firmware, ID e conexão MQTT.';
    if (!validKey()) return 'Informe no campo acima a chave de 32 caracteres exibida no Monitor Serial do ESP32 atualizado.';
    if (!armed) return 'Ligar bloqueado: jumper físico GPIO32–GND ausente. Desligar permanece disponível.';
    if (currentRelays.some(Boolean)) return 'Relés já acionados; use Desligar antes de uma nova partida.';
    return '';
  }
  function refresh() {
    start.disabled = busy || !connected || !validKey() || !fresh() || !armed || currentRelays.some(Boolean) || !window.crypto?.subtle;
    stop.disabled = busy || !connected || !validKey() || !boot || !window.crypto?.subtle;
    if ($('armValue')) $('armValue').textContent = fresh() ? (armed ? 'Jumper GPIO32 presente' : 'Jumper GPIO32 ausente') : 'Sem telemetria recente do ESP32';
    if (!pendingSeq && status) status.textContent = [latestStatus, blockedReason()].filter(Boolean).join(' · ');
  }
  keyInput.addEventListener('input', refresh);
  const fromHex = hex => Uint8Array.from(hex.match(/../g).map(v => parseInt(v, 16)));
  const toHex = data => Array.from(new Uint8Array(data), v => v.toString(16).padStart(2, '0')).join('');
  function configuration() {
    const raw = String($('broker')?.value || 'wss://test.mosquitto.org:8081').trim();
    const url = new URL(raw);
    if (url.protocol !== 'wss:' || url.username || url.password) throw Error('Broker precisa usar WSS, sem senha na URL.');
    const p = String($('prefix')?.value || 'iotmotor').trim();
    const d = String($('commandDevice')?.value || 'esp32-01').trim();
    if (!/^[\w-]+(?:\/[\w-]+)*$/.test(p) || !/^[\w-]+$/.test(d)) throw Error('Prefixo ou ID MQTT invalido.');
    return {url: url.toString(), p, d};
  }
  function connectRemote() {
    if (!window.mqtt?.connect) { latestStatus='Biblioteca MQTT indisponivel.'; refresh(); return; }
    let conf;
    try {conf = configuration();} catch(e) { latestStatus=e.message; refresh(); return; }
    if (client) {client.end(true); client=null;}
    connected=false; boot=''; lastAt=0; legacyAt=0; currentRelays=null; pendingSeq='';
    prefix=conf.p;device=conf.d;latestStatus='Conectando MQTT para comandos assinados…';refresh();
    const active = window.mqtt.connect(conf.url, {clientId:`iotmotor_remote_${Math.random().toString(36).slice(2,12)}`,
      clean:true, reconnectPeriod:4000, connectTimeout:10000, protocolVersion:4, keepalive:30});
    client=active;
    active.on('connect',()=>{if(client!==active)return;connected=true;
      active.subscribe([`${prefix}/${device}/telemetry`,`${prefix}/${device}/command_ack`],{qos:0});
      latestStatus='Conectado. Aguardando ESP32 atualizado e chave no campo acima.';refresh();});
    active.on('message',(topic,payload,packet)=>{
      if(client!==active || packet?.retain) return;
      let data;try{data=JSON.parse(payload.toString('utf8'));}catch{return;}
      if (!data || data.device_id!==device) return;
      if(topic===`${prefix}/${device}/command_ack`){
        if(pendingSeq && data.seq===pendingSeq){
          pendingSeq='';busy=false;
          latestStatus=data.accepted?'ESP32 recebeu o comando; aguarde o estado dos relés.':'ESP32 recusou: '+String(data.reason||'verifique jumper e estado');
          refresh();
        }
        return;
      }
      if (topic===`${prefix}/${device}/telemetry` && !/^[0-9a-f]{16}$/i.test(String(data.boot||''))) {
        legacyAt=Date.now(); latestStatus='Recebendo telemetria de uma versão sem controle MQTT remoto.'; refresh(); return;
      }
      if(topic!==`${prefix}/${device}/telemetry` || !/^[0-9a-f]{16}$/i.test(String(data.boot||'')) ||
         !Array.isArray(data.relay_pins) || data.relay_pins.join(',')!=='19,18,23,27' ||
         !Array.isArray(data.relays) || data.relays.length!==4 || data.relays.some(v=>typeof v!=='boolean')) return;
      boot=data.boot;lastAt=Date.now();currentRelays=data.relays;armed=data.bench_armed===true;
      if ($('relayStatuses')) $('relayStatuses').textContent = data.relays.map((on,i)=>`K${i+1}: ${on?'LIGADO':'desligado'}`).join(' · ');
      if ($('motorValue')) $('motorValue').textContent = data.relays.map((on,i)=>`K${i+1}:${on?'L':'D'}`).join(' · ');
      if ($('modeValue')) $('modeValue').textContent = String(data.mode||'—');
      if ($('physicalLcd') && Array.isArray(data.lcd) && data.lcd.length===4)
        $('physicalLcd').textContent=data.lcd.map(line=>String(line).slice(0,20).padEnd(20)).join('\n');
      if (!pendingSeq) latestStatus=`ESP32 conectado por MQTT; ${armed?'jumper presente':'jumper ausente'}. Estado comandado, nao retorno fisico.`;
      refresh();
    });
    active.on('offline',()=>{if(client!==active)return;connected=false;latestStatus='Broker MQTT indisponivel.';refresh();});
    active.on('close',()=>{if(client!==active)return;connected=false;refresh();});
    active.on('error',e=>{if(client===active){latestStatus='Erro MQTT: '+String(e.message||e);refresh();}});
  }
  async function send(action) {
    if (busy || !client?.connected || !validKey() || !boot || !window.crypto?.subtle) return;
    if (action==='start' && (!fresh() || !armed || currentRelays.some(Boolean))) return;
    const options={mode:'none',mask:0,main:0,star:0,delta:0,seconds:0};
    if (action==='start') {
      options.mode=$('startMode').value;
      if(options.mode==='direct'){
        document.querySelectorAll('.directRelay:checked').forEach(item=>{options.mask|=1<<(Number(item.value)-1);});
        if (options.mask<1 || options.mask>15){latestStatus='Escolha ao menos um rele.';refresh();return;}
      } else if(options.mode==='sequence'){
        options.main=Number($('mainRelay').value);options.star=Number($('starRelay').value);
        options.delta=Number($('deltaRelay').value);options.seconds=Number($('starSeconds').value);
        if(new Set([options.main,options.star,options.delta]).size!==3 ||
           [options.main,options.star,options.delta].some(v=>!Number.isInteger(v)||v<1||v>4) ||
           !Number.isInteger(options.seconds)||options.seconds<2||options.seconds>30){
          latestStatus='Sequencia: escolha tres reles distintos e 2 a 30 segundos.';refresh();return;
        }
      } else {latestStatus='Modo de partida invalido.';refresh();return;}
      if (!window.confirm('Somente teste de reles SEM motor nem contatores. Confirmar partida?')) return;
    }
    busy=true;refresh();
    try{
      const key=fromHex(keyInput.value.trim());
      const seq=String(lastSeq=Math.max(Date.now()*1000+Math.floor(Math.random()*1000),lastSeq+1));
      const cmd={v:1,device_id:device,boot,seq,action,...options};
      const canonical=`iotmotor-v1|${device}|${boot}|${seq}|${action}|${options.mode}|${options.mask}|${options.main}|${options.star}|${options.delta}|${options.seconds}`;
      const cryptoKey=await crypto.subtle.importKey('raw',key,{name:'HMAC',hash:'SHA-256'},false,['sign']);
      cmd.sig=toHex(await crypto.subtle.sign('HMAC',cryptoKey,new TextEncoder().encode(canonical)));
      if (!client?.connected) throw Error('Conexao MQTT encerrada.');
      pendingSeq=seq;latestStatus='Comando enviado; aguardando resposta do ESP32.';
      client.publish(signedTopic(),JSON.stringify(cmd),{qos:1,retain:false},err=>{
        if(err && pendingSeq===seq){pendingSeq='';busy=false;latestStatus='Falha ao publicar: '+err.message;refresh();}
      });
      setTimeout(()=>{if(pendingSeq===seq){pendingSeq='';busy=false;latestStatus='Sem resposta do ESP32. Confira os estados e o Monitor Serial.';refresh();}},6500);
    }catch(e){pendingSeq='';busy=false;latestStatus='Falha ao assinar/enviar comando: '+e.message;refresh();}
  }
  start.addEventListener('click',()=>send('start'));
  stop.addEventListener('click',()=>send('stop'));
  $('connectionForm')?.addEventListener('submit',()=>setTimeout(connectRemote,0));
  connectRemote();setInterval(refresh,1000);
})();
