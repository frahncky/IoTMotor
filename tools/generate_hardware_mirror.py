#!/usr/bin/env python3
"""Generate a four-relay/LCD monitoring sketch without changing actuation logic.

Source is the existing, working four-relay sketch on the focused-ptolemy branch.
The generated copy adds only *read-only* MQTT fields reflecting commanded relay
states and the exact four strings last written to the LCD. It does not verify
physical contacts or pixels and must never be treated as a safety instrument.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess

BRANCH = 'origin/claude/focused-ptolemy-o0h29l'
SOURCE = 'esp32/iotmotor_modulo1_acionamento/iotmotor_modulo1_acionamento.ino'


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f'Expected one source anchor, found {count}: {old[:85]!r}')
    return text.replace(old, new, 1)


def generate(source: str) -> str:
    if not all(x in source for x in ('PINOS_RELES[NUM_RELES] = {19, 18, 23, 27}',
                                    'lcdCache[LCD_LINHAS][LCD_COLUNAS + 1]',
                                    'void publicarTelemetria(')):
        raise ValueError('Different firmware revision or missing 4-relay LCD hardware')
    result = source
    # Public repository: do not copy original Wi-Fi password into a new artifact.
    result, n = re.subn(r'(static const char\* WIFI_SSID\s*=\s*)"[^"]*";',
                        r'\1"IFMA_IOT";', result, count=1)
    if n != 1:
        raise ValueError('Wi-Fi SSID definition not found')
    result, n = re.subn(r'(static const char\* WIFI_PASSWORD\s*=\s*)"[^"]*";',
                        r'\1"";', result, count=1)
    if n != 1:
        raise ValueError('Wi-Fi password definition not found')
    # A placeholder OTA key must not be copied as though it were secret.
    result, n = re.subn(r'(static const char\* OTA_KEY\s*=\s*)"[^"]*";',
                        r'\1"";', result, count=1)
    if n != 1:
        raise ValueError('OTA key definition not found')
    result = replace_once(result, 'static const char* FIRMWARE_VERSION = "1.1.0";',
                          'static const char* FIRMWARE_VERSION = "1.1.1-lcd-mirror";')
    result = replace_once(result, '  StaticJsonDocument<448> doc;\n  doc["device_id"] = DEVICE_ID;',
                          '  StaticJsonDocument<1024> doc;\n  doc["device_id"] = DEVICE_ID;')
    result = replace_once(result,
        '  doc["seq"] = sequenciaTelemetria;\n',
        '''  doc["seq"] = sequenciaTelemetria;
  // Somente monitoramento: estados LOGICOS solicitados, sem feedback de contatos.
  doc["relay_commanded_only"] = true;
  JsonArray relayPins = doc.createNestedArray("relay_pins");
  JsonArray relays = doc.createNestedArray("relays");
  for (uint8_t i = 0; i < NUM_RELES; ++i) {
    relayPins.add(PINOS_RELES[i]);
    relays.add(estadoReles[i]);
  }
  // lcdCache armazena exatamente os caracteres enviados ao LCD 20x4.
  // Nao e leitura otica dos pixels, nem confirma integridade eletrica do I2C.
  JsonArray lcdLines = doc.createNestedArray("lcd");
  for (uint8_t i = 0; i < LCD_LINHAS; ++i) lcdLines.add(lcdCache[i]);
  if (WiFi.status() == WL_CONNECTED) doc["wifi_ip"] = WiFi.localIP().toString();
''')
    result = replace_once(result,
        '  char payload[448];\n  size_t n = serializeJson(doc, payload, sizeof(payload));',
        '  char payload[1024];\n  size_t n = serializeJson(doc, payload, sizeof(payload));')
    result = replace_once(result, '  mqttClient.setBufferSize(768);',
                          '  mqttClient.setBufferSize(1536);')
    # Refresh the physical LCD cache before taking its telemetry snapshot.
    result = replace_once(result,
        '''  if (agora - ultimaTelemetriaMs >= INTERVALO_TELEMETRIA_MS) {
    ultimaTelemetriaMs = agora;
    sequenciaTelemetria++;
    publicarTelemetria(JsonVariantConst(), "");
  }

  if (lcdPrecisaAtualizar || (agora - ultimaAtualizacaoLcd >= INTERVALO_LCD)) {
    ultimaAtualizacaoLcd = agora;
    atualizarLcd();
  }''',
        '''  if (lcdPrecisaAtualizar || (agora - ultimaAtualizacaoLcd >= INTERVALO_LCD)) {
    ultimaAtualizacaoLcd = agora;
    atualizarLcd();
  }

  if (agora - ultimaTelemetriaMs >= INTERVALO_TELEMETRIA_MS) {
    ultimaTelemetriaMs = agora;
    sequenciaTelemetria++;
    publicarTelemetria(JsonVariantConst(), "");
  }''')
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, help='Optional local copy of the original sketch')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.source:
        original = args.source.read_text(encoding='utf-8-sig')
    else:
        original = subprocess.check_output(['git', 'show', f'{BRANCH}:{SOURCE}'], text=True)
    result = generate(original)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(result, encoding='utf-8')
    assert '"IFMA_IOT"' in result and '"1.1.1-lcd-mirror"' in result
    print(f'Generated {args.output}: LCD buffer and relay commanded states mirrored; original source untouched.')

if __name__ == '__main__':
    main()
