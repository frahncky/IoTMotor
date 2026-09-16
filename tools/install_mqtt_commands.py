#!/usr/bin/env python3
"""One-time, idempotent wiring for signed MQTT controls on the existing dashboard.

The secret is generated/stored ONLY in the ESP32 NVS, not in this repository.
A public broker is never trusted as an authorization mechanism.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
fw = root / 'esp32/iotmotor_esp32/iotmotor_esp32_comandos/iotmotor_esp32_comandos.ino'
site = root / 'dashboard-cloudflare/index.html'
builder = root / 'tools/rebuild_esp32_site.py'
text = fw.read_text(encoding='utf-8')
html = site.read_text(encoding='utf-8')
rebuild = builder.read_text(encoding='utf-8')


def add_once(source, old, new, description):
    if new in source:
        return source
    if source.count(old) != 1:
        raise SystemExit(f'Unexpected source while installing {description}: {source.count(old)} matches')
    return source.replace(old, new, 1)

text = add_once(text,
    '#include "iotmotor_profiles.h"',
    '#include "iotmotor_profiles.h"\n#include "iotmotor_mqtt_control.h"', 'signed command handler')
text = add_once(text,
    'char topicoTelemetria[80], topicoStatus[80], topicoCapacidades[80];',
    'char topicoTelemetria[80], topicoStatus[80], topicoCapacidades[80];\nchar topicoComandos[80], topicoResposta[80];',
    'command and acknowledgement topics')
text = add_once(text,
    '  doc["firmware_version"] = "v6-lan-profiles-1.0";',
    '  doc["firmware_version"] = "v7-signed-mqtt-bench";',
    'version')
text = add_once(text,
    '  doc["accepts_direct_command"] = false;',
    '  doc["accepts_direct_command"] = controleMqttConfigurado;',
    'capability flag')
text = add_once(text,
    '  doc["accepts_command_request"] = false;',
    '  doc["accepts_command_request"] = false;\n  doc["command_auth"] = "hmac-sha256";',
    'command authentication capability')
text = add_once(text,
    '  doc["seq"] = ++sequenciaMqtt;',
    '  doc["seq"] = ++sequenciaMqtt;\n  doc["boot"] = sessaoControle;\n  doc["remote_control_ready"] = controleMqttConfigurado;',
    'telemetry boot nonce')
text = add_once(text,
    '    publicarCapacidades();',
    '    if (controleMqttConfigurado && !mqttClient.subscribe(topicoComandos, 1))\n      Serial.println("[MQTT] falha assinando topico de comandos");\n    publicarCapacidades();',
    'subscribe to command topic')
text = add_once(text,
    '  // Configura publicacao MQTT em topicos exclusivos deste modulo.',
    '  iniciarControleMqtt();\n  // Configura publicacao MQTT em topicos exclusivos deste modulo.',
    'physical provisioning of device key')
text = add_once(text,
    '  snprintf(topicoCapacidades, sizeof(topicoCapacidades), "iotmotor/%s/capabilities", DEVICE_ID);',
    '  snprintf(topicoCapacidades, sizeof(topicoCapacidades), "iotmotor/%s/capabilities", DEVICE_ID);\n'
    '  snprintf(topicoComandos, sizeof(topicoComandos), "iotmotor/%s/command", DEVICE_ID);\n'
    '  snprintf(topicoResposta, sizeof(topicoResposta), "iotmotor/%s/command_ack", DEVICE_ID);',
    'define device specific command topics')
text = add_once(text,
    '  mqttClient.setBufferSize(1536);',
    '  mqttClient.setBufferSize(1536);\n  mqttClient.setCallback(receberComandoMqtt);',
    'MQTT callback')
text = add_once(text,
    'void tratarLocalJs() {\n  adicionarCabecalhosComuns();\n  server.send_P(200,"application/javascript; charset=utf-8",IOTMOTOR_LOCAL_JS);\n}',
    'void tratarLocalJs() {\n  adicionarCabecalhosComuns();\n  server.send_P(200,"application/javascript; charset=utf-8",IOTMOTOR_LOCAL_JS);\n}\n'
    'void tratarRemoteJs() {\n  adicionarCabecalhosComuns();\n  server.send_P(200,"application/javascript; charset=utf-8",IOTMOTOR_REMOTE_JS);\n}',
    'serve remote JS from ESP32')
text = add_once(text,
    '  server.on("/local-controls.js", HTTP_GET, tratarLocalJs);',
    '  server.on("/local-controls.js", HTTP_GET, tratarLocalJs);\n'
    '  server.on("/remote-controls.js", HTTP_GET, tratarRemoteJs);',
    'remote javascript route')

html = add_once(html,
    '<script src="./local-controls.js" defer></script>',
    '<script src="./local-controls.js" defer></script>\n<script src="./remote-controls.js" defer></script>',
    'load remote controls on existing dashboard')
rebuild = add_once(rebuild,
    "local=(SITE/'local-controls.js').read_text(encoding='utf-8')",
    "local=(SITE/'local-controls.js').read_text(encoding='utf-8')\nremote=(SITE/'remote-controls.js').read_text(encoding='utf-8')",
    'read remote JS asset')
rebuild = add_once(rebuild,
    "assert html.count('local-controls.js')==1 and html.count('dual-dashboard.js')==1",
    "assert html.count('local-controls.js')==1 and html.count('dual-dashboard.js')==1 and html.count('remote-controls.js')==1",
    'verify script references')
rebuild = add_once(rebuild,
    "(local,')IOTLOCAL\"')]:",
    "(local,')IOTLOCAL\"'),(remote,')IOTREMOTE\"')]:",
    'check raw C++ string delimiters')
rebuild = add_once(rebuild,
    "const char IOTMOTOR_LOCAL_JS[] PROGMEM = R\"IOTLOCAL('''+local+''')IOTLOCAL\";\n''',encoding='utf-8')",
    "const char IOTMOTOR_LOCAL_JS[] PROGMEM = R\"IOTLOCAL('''+local+''')IOTLOCAL\";\n"
    "const char IOTMOTOR_REMOTE_JS[] PROGMEM = R\"IOTREMOTE('''+remote+''')IOTREMOTE\";\n''',encoding='utf-8')",
    'embed remote javascript in ESP32 firmware')

assert 'mqttClient.subscribe(topicoComandos, 1)' in text
assert 'mqttClient.setCallback(receberComandoMqtt)' in text
assert text.count('iotmotor_mqtt_control.h') == 1
assert 'remote-controls.js' in html and 'IOTMOTOR_REMOTE_JS' in rebuild
fw.write_text(text, encoding='utf-8')
site.write_text(html, encoding='utf-8')
builder.write_text(rebuild, encoding='utf-8')
print('Installed signed MQTT remote commands and existing-button UI; key remains on device.')
