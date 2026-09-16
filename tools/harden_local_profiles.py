#!/usr/bin/env python3
"""One-time security hardening for ESP32 LAN relay endpoints.

Physical jumper GPIO32 remains mandatory. Cross-origin browser POSTs must not
energize relays, even on an open institutional Wi-Fi network.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
fw=root/'esp32/iotmotor_esp32/iotmotor_esp32_comandos/iotmotor_esp32_comandos.ino'
prof=fw.with_name('iotmotor_profiles.h')
s=fw.read_text(encoding='utf-8')
p=prof.read_text(encoding='utf-8')
if 'server.collectHeaders(headerNames, 1);' not in s:
    needle='  // Servidor web\n  server.on("/", HTTP_GET, tratarIndex);'
    assert s.count(needle)==1
    s=s.replace(needle,'  // Inspecionar Origin em POSTs de energizacao, sem abrir CORS.\n  const char* headerNames[] = {"Origin"};\n  server.collectHeaders(headerNames, 1);\n'+needle,1)
s=s.replace('  server.sendHeader("Access-Control-Allow-Origin", "*");','  server.sendHeader("X-Frame-Options", "DENY");')
if 'bool origemControleLocal()' not in p:
    needle='void tratarPararBancada() {'
    assert p.count(needle)==1
    p=p.replace(needle,'''bool origemControleLocal() {
  // Browser fetch POST envia Origin. Nenhuma chave e exposta no codigo publico.
  const String origin=server.header("Origin");
  if (WiFi.status()!=WL_CONNECTED || !origin.length()) return false;
  return origin==String("http://")+WiFi.localIP().toString() ||
         origin=="http://modulo1.local";
}
'''+needle,1)
    needle='void tratarPartidaBancada() {\n'
    assert p.count(needle)==1
    p=p.replace(needle,needle+'''  if (!origemControleLocal()) { server.send(403,"text/plain","Origem local nao autorizada");return; }
''',1)
    needle='void tratarCanalBancada() {\n'
    assert p.count(needle)==1
    p=p.replace(needle,needle+'''  if (!origemControleLocal()) { server.send(403,"text/plain","Origem local nao autorizada");return; }
''',1)
fw.write_text(s,encoding='utf-8')
prof.write_text(p,encoding='utf-8')
assert 'server.collectHeaders(headerNames, 1);' in s
assert p.count('if (!origemControleLocal())')==2
assert 'Access-Control-Allow-Origin' not in s
print('Energization requires same-origin POST + GPIO32 physical jumper; stop remains available.')
