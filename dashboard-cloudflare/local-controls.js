'use strict';
// Apenas a interface dos perfis; os comandos saem por remote-controls.js via MQTT.
(() => {
  const $ = id => document.getElementById(id);
  const panel = document.querySelector('.control');
  const start = $('startBtn'), stop = $('stopBtn');
  if (!panel || !start || !stop) return;
  window.iotmotorLocalControls = true; // Os graficos nao controlam o estado destes botoes.
  start.disabled = true;
  stop.disabled = true;
  const box = document.createElement('section');
  box.style.cssText = 'border:1px solid #50778a;border-radius:12px;padding:16px;background:#0a2936;margin:14px 0 4px';
  box.innerHTML = `<div class="field"><label for="startMode">Tipo de partida</label><select id="startMode" style="padding:9px;background:#102e3b;color:white;border:1px solid #608697;border-radius:8px"><option value="direct">Direta</option><option value="sequence">Estrela-triângulo</option></select></div>
    <div id="directSelect" style="margin:12px 0 0"><span class="muted">Contatores acionados:</span><div id="directChannels" class="buttons" style="margin:8px 0 0"></div></div>
    <div id="sequenceSelect" hidden style="margin:12px 0 0"><div class="fields" style="display:flex;flex-wrap:wrap"><label>Principal <select id="mainRelay"></select></label><label>Estrela <select id="starRelay"></select></label><label>Triângulo <select id="deltaRelay"></select></label><label>Tempo estrela (s) <input id="starSeconds" type="number" min="2" max="30" step="1" value="5" style="width:70px"></label></div></div>`;
  panel.querySelector('.buttons').before(box);
  for (let i = 0; i < 4; i++) {
    const label = document.createElement('label');
    label.style.cssText = 'display:inline-flex;align-items:center;gap:5px';
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.value = String(i + 1);
    input.checked = i === 0;
    input.className = 'directRelay';
    label.append(input, document.createTextNode(`CNT ${i + 1}`));
    $('directChannels').append(label);
  }
  for (const id of ['mainRelay', 'starRelay', 'deltaRelay']) {
    const select = $(id);
    for (let i = 0; i < 4; i++) select.add(new Option(`CNT ${i + 1}`, String(i + 1)));
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
