#!/usr/bin/env python3
"""Expose the existing ESP32 LAN controls from the Cloudflare dashboard.

No remote MQTT start is introduced: the current four-relay v6 firmware publishes
telemetry only; it does not subscribe to command topics. The HTTPS dashboard
navigates to the ESP32 HTTP panel in a separate tab on the local network.
"""
from pathlib import Path

site = Path('dashboard-cloudflare/index.html')
html = site.read_text(encoding='utf-8')
anchor = '<script src="./dual-dashboard.js" defer></script>'
script = '<script src="./local-controls.js" defer></script>'
if html.count(anchor) != 1:
    raise SystemExit('Could not identify the active dashboard script; unchanged.')
if script not in html:
    html = html.replace(anchor, anchor + '\n' + script, 1)
    site.write_text(html, encoding='utf-8')
assert html.count(script) == 1
assert 'id="startBtn"' in html and 'id="stopBtn"' in html
print('Main dashboard now links to the existing ESP32 local on/off panel.')
