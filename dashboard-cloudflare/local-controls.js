'use strict';
// Apenas a interface dos perfis; os comandos saem por remote-controls.js via MQTT.
(() => {
  const $ = id => document.getElementById(id);
  const panel = document.querySelector('.control');
  const start = $('startBtn'), stop = $('stopBtn'), old = $('starBtn');
  if (!panel || !start || !stop) return;
  window.iotmotorLocalControls = true; // Os graficos nao controlam o estado destes botoes.
  start.textContent = '▶ Ligar · partida selecionada';
  stop.textContent = '■ Desligar todos';
  start.disabled = true;
  stop.disabled = true;
  if (old) old.hidden = true;
  const armLabel = document.querySelector('.control-info span');
  if (armLabel) armLabel.textContent = 'Controle remoto';
  const box = document.createElement('section');
  box.style.cssText = 'border:1px solid #50778a;border-radius:12px;padding:16px;background:#0a2936;margin:12px 0';
  box.innerHTML = `<h3 style="font-size:18px">Configuração da partida e dos relés</h3>
    <p class="muted">Selecione o modo e os relés. Ligar e Desligar enviam comandos MQTT ao ESP32-01, sem chave, jumper ou página local.</p>
    <div class="field"><label for="startMode">Tipo de partida</label><select id="startMode" style="padding:9px;background:#102e3b;color:white;border:1px solid #608697;border-radius:8px"><option value="direct">Direta · relés selecionados</option><option value="sequence">Sequência temporizada de bancada · principal, estrela e triângulo</option></select></div>
    <div id="directSelect" style="margin:12px 0"><span class="muted">Relés acionados pelo botão Ligar:</span><div id="directChannels" class="buttons"></div></div>
    <div id="sequenceSelect" hidden style="margin:12px 0"><p class="muted">Ensaio apenas de relés, sem motor ou contatores conectados.</p><div class="fields" style="display:flex;flex-wrap:wrap"><label>Principal <select id="mainRelay"></select></label><label>Estrela <select id="starRelay"></select></label><label>Triângulo <select id="deltaRelay"></select></label><label>Tempo estrela (s) <input id="starSeconds" type="number" min="2" max="30" step="1" value="5" style="width:70px"></label></div></div>
    <p id="profileStatus" class="feedback" aria-live="polite">Conecte ao broker MQTT.</p>
    <div class="muted" id="relayStatuses">K1 GPIO19 · K2 GPIO18 · K3 GPIO23 · K4 GPIO27</div>
    <pre id="physicalLcd" style="white-space:pre;font:14px/1.4 monospace;max-width:100%;overflow:auto;background:#051b26;padding:12px;border:1px solid #466878;border-radius:9px;margin:12px 0">LCD 20×4 · aguardando dados</pre>`;
  panel.append(box);
  const pins = [19, 18, 23, 27];
  pins.forEach((pin, i) => {
    const label = document.createElement('label');
    label.style.cssText = 'display:inline-flex;align-items:center;gap:5px';
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.value = String(i + 1);
    input.checked = i === 0;
    input.className = 'directRelay';
    label.append(input, document.createTextNode(`K${i + 1} · GPIO${pin}`));
    $('directChannels').append(label);
  });
  for (const id of ['mainRelay', 'starRelay', 'deltaRelay']) {
    const select = $(id);
    pins.forEach((pin, i) => select.add(new Option(`K${i + 1} · GPIO${pin}`, String(i + 1))));
  }
  $('mainRelay').value = '1';
  $('starRelay').value = '2';
  $('deltaRelay').value = '3';
  $('startMode').addEventListener('change', () => {
    const sequence = $('startMode').value === 'sequence';
    $('directSelect').hidden = sequence;
    $('sequenceSelect').hidden = !sequence;
  });
})();
