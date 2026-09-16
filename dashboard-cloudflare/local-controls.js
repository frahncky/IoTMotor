'use strict';
/* Os botões ORIGINAIS Ligar/Desligar comandam o ESP32 na própria tela local.
 * Cloudflare HTTPS exibe estados; nunca envia partida via MQTT público ou HTTP misto. */
(() => {
  const $ = id => document.getElementById(id);
  const control = document.querySelector('.control');
  const startBtn = $('startBtn'), stopBtn = $('stopBtn'), starBtn = $('starBtn');
  if (!control || !startBtn || !stopBtn) return;
  window.iotmotorLocalControls = true; // Dual dashboard não deve desabilitar os botões locais.
  const onLan = location.protocol === 'http:' &&
    (/^(?:10|192\.168|172\.(?:1[6-9]|2\d|3[01]))\./.test(location.hostname) || location.hostname === 'modulo1.local');
  startBtn.hidden = false;
  startBtn.textContent = '▶ Ligar · partida selecionada';
  stopBtn.hidden = false;
  stopBtn.textContent = '■ Desligar todos';
  startBtn.disabled = true;
  stopBtn.disabled = !onLan;
  if (starBtn) starBtn.hidden = true; // A escolha da sequência fica no seletor de partida.
  const oldInfo = $('armValue');
  if (oldInfo) oldInfo.textContent = onLan ? 'Conferindo jumper físico GPIO32–GND…' : 'Comandos disponíveis somente no painel local do ESP32';
  const box = document.createElement('section');
  box.style.cssText = 'border:1px solid #50778a;border-radius:12px;padding:16px;background:#0a2936;margin:12px 0';
  box.innerHTML = `<h3 style="font-size:18px">Configuração da partida e das saídas</h3>
    <p class="muted" id="controlHint">Os botões Ligar e Desligar acima usam a configuração escolhida aqui. As saídas mostram estados lógicos, não confirmação física dos contatores.</p>
    <div class="field"><label for="startMode">Tipo de partida</label><select id="startMode" style="padding:9px;background:#102e3b;color:white;border:1px solid #608697;border-radius:8px"><option value="direct">Direta · relés selecionados</option><option value="sequence">Sequência temporizada de bancada · principal, estrela e triângulo</option></select></div>
    <div id="directSelect" style="margin:12px 0"><span class="muted">Relés acionados pelo botão Ligar:</span><div id="directChannels" class="buttons"></div></div>
    <div id="sequenceSelect" hidden style="margin:12px 0"><p class="muted">Sequência apenas para bancada SEM motor nem contatores. Exige intertravamentos e proteções independentes antes de qualquer uso em potência.</p><div class="fields" style="display:flex;flex-wrap:wrap"><label>Principal <select id="mainRelay"></select></label><label>Estrela <select id="starRelay"></select></label><label>Triângulo <select id="deltaRelay"></select></label><label>Tempo estrela (s) <input id="starSeconds" type="number" min="2" max="30" step="1" value="5" style="width:70px"></label></div></div>
    <p id="profileStatus" class="feedback" aria-live="polite">Aguardando estado do ESP32.</p>
    <div class="muted" id="relayStatuses">K1 GPIO19 · K2 GPIO18 · K3 GPIO23 · K4 GPIO27</div>
    <pre id="physicalLcd" style="white-space:pre;font:14px/1.4 monospace;max-width:100%;overflow:auto;background:#051b26;padding:12px;border:1px solid #466878;border-radius:9px;margin:12px 0">LCD 20×4 · aguardando dados</pre>
    <p id="localInstruction" class="muted" hidden>Este endereço HTTPS recebe telemetria, mas não tem um canal autenticado para comandar os relés. Para utilizar os mesmos botões nesta tela, abra o endereço IP mostrado no LCD físico do ESP32, na mesma rede Wi-Fi. Não é necessário abrir outra aba.</p>`;
  // Mantém os botões originais no lugar; somente o seletor fica imediatamente abaixo.
  control.append(box);
  const pins = [19,18,23,27];
  let busy = false, snapshot = null;
  pins.forEach((pin,i) => {
    const label = document.createElement('label');
    label.style.cssText = 'display:inline-flex;align-items:center;gap:5px';
    const input = document.createElement('input');
    input.type = 'checkbox'; input.value = String(i+1); input.checked = i===0; input.className = 'directRelay';
    label.append(input, document.createTextNode(`K${i+1} · GPIO${pin}`));
    $('directChannels').append(label);
  });
  for (const id of ['mainRelay','starRelay','deltaRelay']) {
    const select = $(id);
    pins.forEach((pin,i) => select.add(new Option(`K${i+1} · GPIO${pin}`,String(i+1))));
  }
  $('mainRelay').value = '1'; $('starRelay').value = '2'; $('deltaRelay').value = '3';
  $('startMode').addEventListener('change', () => {
    const sequence = $('startMode').value === 'sequence';
    $('directSelect').hidden = sequence; $('sequenceSelect').hidden = !sequence;
  });
  function show(data) {
    snapshot = data;
    const relays = data.reles || data.relays;
    const valid = Array.isArray(relays) && relays.length===4 && relays.every(v => typeof v==='boolean');
    $('relayStatuses').textContent = valid
      ? relays.map((on,i) => `K${i+1} GPIO${pins[i]}: ${on?'LIGADO':'desligado'}`).join(' · ')
      : 'Sem estados válidos dos relés';
    const rows = data.lcd || data.lcd_lines;
    if (Array.isArray(rows) && rows.length===4) $('physicalLcd').textContent = rows.map(v => String(v).slice(0,20).padEnd(20)).join('\n');
    if (onLan) {
      $('profileStatus').textContent = `${data.partida_etapa || 'Parado'} · ${data.armado?'jumper físico presente':'sem jumper GPIO32–GND: partida bloqueada'}`;
      if ($('armValue')) $('armValue').textContent = data.armado?'Jumper GPIO32–GND presente':'Jumper GPIO32–GND ausente';
      startBtn.disabled = busy || !valid || !data.armado || relays.some(Boolean) || data.partida_etapa==='Aguardando tempo de seguranca';
      stopBtn.disabled = busy;
    }
  }
  async function poll() {
    if (!onLan || busy) return;
    try {
      const res = await fetch('/dados',{cache:'no-store'});
      if (!res.ok) throw Error('HTTP '+res.status);
      show(await res.json());
    } catch(e) {
      startBtn.disabled = true;
      // O botão de parada permanece acionável mesmo que a leitura /dados falhe.
      stopBtn.disabled = false;
      $('profileStatus').textContent = 'Não foi possível ler o estado: '+e.message;
    }
  }
  async function post(path,params) {
    if (busy || !onLan) return;
    busy=true;startBtn.disabled=true;stopBtn.disabled=true;
    $('profileStatus').textContent='Pedido enviado; aguardando resposta do ESP32…';
    try {
      const res=await fetch(path,{method:'POST',body:new URLSearchParams(params),cache:'no-store'});
      const message=await res.text();
      if (!res.ok) throw Error(`${res.status}: ${message}`);
      $('profileStatus').textContent='ESP32 recebeu o comando; verificando os estados lógicos…';
    } catch(e) {
      $('profileStatus').textContent='Falha no comando: '+e.message;
    } finally { busy=false;await poll(); }
  }
  startBtn.addEventListener('click', () => {
    if (!onLan || !snapshot?.armado || busy) return;
    const mode=$('startMode').value;
    const args={modo:mode};
    if (mode==='direct') {
      let mask=0;
      document.querySelectorAll('.directRelay:checked').forEach(el => {mask |= 1<<(Number(el.value)-1);});
      if (!mask) {$('profileStatus').textContent='Selecione pelo menos um relé.';return;}
      args.mascara=String(mask);
    } else {
      const chosen=[$('mainRelay').value,$('starRelay').value,$('deltaRelay').value];
      if (new Set(chosen).size!==3) {$('profileStatus').textContent='Principal, estrela e triângulo devem ser relés distintos.';return;}
      Object.assign(args,{principal:chosen[0],estrela:chosen[1],triangulo:chosen[2],tempo:$('starSeconds').value});
    }
    if (window.confirm('Somente ENSAIO SEM MOTOR NEM CONTATORES. Confirmar acionamento dos relés escolhidos?')) post('/partida',args);
  });
  stopBtn.addEventListener('click', () => {if(onLan) post('/parar',{});});
  if (onLan) {
    $('controlHint').textContent='Os botões originais acima controlam esta placa diretamente, nesta mesma tela. Jumper GPIO32–GND para ligar; Desligar todos permanece acessível.';
    poll();setInterval(poll,1200);return;
  }
  $('localInstruction').hidden=false;
  $('profileStatus').textContent='Monitoramento remoto ativo quando houver telemetria; Ligar/Desligar não disponíveis no broker público.';
})();
