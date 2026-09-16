#!/usr/bin/env python3
"""Keep original dashboard Ligar/Desligar buttons controlled by local-controls.js.

The previous GPIO2/MQTT prototype is retired. The dual MQTT telemetry renderer
must never disable or attach obsolete handlers to the two real LAN buttons.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
path=root/'dashboard-cloudflare/dual-dashboard.js'
s=path.read_text(encoding='utf-8')
replacements={
    "$('startBtn').disabled=true; // Old single-relay prototype retired.":
        "if(!window.iotmotorLocalControls) $('startBtn').disabled=true; // Local controller owns this button.",
    "$('stopBtn').disabled=true; // LAN-only control lives in local-controls.js.":
        "if(!window.iotmotorLocalControls) $('stopBtn').disabled=true; // Never override local stop.",
    "text('armValue',active?(s.benchArmed?'Jumper local presente':'Sem jumper local'):'Sem telemetria elétrica recente');":
        "if(!window.iotmotorLocalControls) text('armValue',active?(s.benchArmed?'Jumper local presente':'Sem jumper local'):'Sem telemetria elétrica recente');",
    " $('startBtn').addEventListener('click',()=>command('start','direct'));\n $('stopBtn').addEventListener('click',()=>command('stop','manual_stop'));":
        " // Original startBtn and stopBtn are wired only by local-controls.js."
}
for old,new in replacements.items():
    if old in s:
        if s.count(old)!=1:raise RuntimeError('Ambiguous old button control')
        s=s.replace(old,new,1)
    elif new not in s:raise RuntimeError('Missing old or new button-control marker: '+old)
assert "mqttClient.subscribe(" not in s
path.write_text(s,encoding='utf-8')
print('Original Ligar/Desligar buttons exclusively owned by LAN controller.')
