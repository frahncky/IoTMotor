#!/usr/bin/env python3
"""Explain precisely why existing MQTT start/stop controls are disabled.

Safe to rerun. Does not weaken command signatures or hardware interlocks.
"""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
remote_path = root / 'dashboard-cloudflare/remote-controls.js'
index_path = root / 'dashboard-cloudflare/index.html'
s = remote_path.read_text(encoding='utf-8')
if 'function blockedReason()' not in s:
    old = "  let latestStatus = 'Aguardando conexao MQTT e chave da placa.';"
    new = old + "\n  let legacyAt = 0; // ESP32 enviou telemetria sem identificador de firmware remoto."
    assert s.count(old) == 1
    s = s.replace(old, new, 1)
    old = "  function refresh() {\n"
    new = """  function blockedReason() {
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
"""
    assert s.count(old) == 1
    s = s.replace(old, new, 1)
    old = '    if (!pendingSeq && status) status.textContent = latestStatus;'
    new = "    if (!pendingSeq && status) status.textContent = [latestStatus, blockedReason()].filter(Boolean).join(' · ');"
    assert s.count(old) == 1
    s = s.replace(old, new, 1)
    old = "    connected=false; boot=''; lastAt=0; currentRelays=null; pendingSeq='';"
    new = "    connected=false; boot=''; lastAt=0; legacyAt=0; currentRelays=null; pendingSeq='';"
    assert s.count(old) == 1
    s = s.replace(old, new, 1)
    old = "      if(topic!==`${prefix}/${device}/telemetry` || !/^[0-9a-f]{16}$/i.test(String(data.boot||'')) ||"
    new = """      if (topic===`${prefix}/${device}/telemetry` && !/^[0-9a-f]{16}$/i.test(String(data.boot||''))) {
        legacyAt=Date.now(); latestStatus='Recebendo telemetria de uma versão sem controle MQTT remoto.'; refresh(); return;
      }
      if(topic!==`${prefix}/${device}/telemetry` || !/^[0-9a-f]{16}$/i.test(String(data.boot||'')) ||"""
    assert s.count(old) == 1
    s = s.replace(old, new, 1)
    remote_path.write_text(s, encoding='utf-8')
html = index_path.read_text(encoding='utf-8')
if 'CONTROLE MQTT REMOTO' not in html:
    new_notice = ('<div class="notice"><strong>CONTROLE MQTT REMOTO.</strong> Na própria página, selecione o modo de partida e os relés e use os botões Ligar/Desligar. '
                  'Para habilitar: grave o firmware atual no ESP32-01, conecte ao MQTT, informe no campo de controle a chave exibida no Monitor Serial e mantenha a habilitação física GPIO32–GND. '
                  'Se os botões estiverem cinza, o diagnóstico abaixo informa exatamente o que falta. '
                  'Faça ensaios apenas com relés desconectados do motor e dos contatores; intertravamentos físicos e parada local são indispensáveis para operação real.</div>')
    html, n = re.subn(r'<div class="notice">.*?</div>', lambda _: new_notice, html, count=1, flags=re.S)
    assert n == 1
    index_path.write_text(html, encoding='utf-8')
assert 'function blockedReason()' in remote_path.read_text(encoding='utf-8')
assert 'CONTROLE MQTT REMOTO' in index_path.read_text(encoding='utf-8')
print('Diagnóstico de desabilitação e aviso da página atualizados; política de segurança mantida.')
