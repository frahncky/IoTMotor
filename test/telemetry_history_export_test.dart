import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/models/telemetry_history_entry.dart';
import 'package:iotmotor/features/iot_motor/models/telemetry_sample.dart';
import 'package:iotmotor/features/iot_motor/services/telemetry_history_export.dart';

void main() {
  test('TelemetrySample serializa e restaura leituras persistidas', () {
    final TelemetrySample original = TelemetrySample(
      timestamp: DateTime(2026, 5, 7, 9),
      voltage: 220.1,
      current: 3.2,
      motorOn: true,
      mode: 'direct',
    );

    final TelemetrySample? restored = TelemetrySample.fromStoredMap(
      original.toStoredMap(),
    );

    expect(restored, isNotNull);
    expect(restored!.timestamp, original.timestamp);
    expect(restored.voltage, 220.1);
    expect(restored.current, 3.2);
    expect(restored.motorOn, isTrue);
    expect(restored.mode, 'direct');
  });

  test('buildTelemetryHistoryCsv ordena leituras e inclui dispositivo', () {
    final DateTime newer = DateTime(2026, 5, 7, 10, 1);
    final DateTime older = DateTime(2026, 5, 7, 10);

    final String csv = buildTelemetryHistoryCsv(<TelemetryHistoryEntry>[
      TelemetryHistoryEntry(
        deviceId: 'esp-2',
        sample: TelemetrySample(timestamp: newer, current: 3.456),
      ),
      TelemetryHistoryEntry(
        deviceId: 'esp-1',
        sample: TelemetrySample(
          timestamp: older,
          voltage: 220.46,
          motorOn: true,
          mode: 'direct',
        ),
      ),
    ]);

    final List<String> lines = csv.split('\n');
    expect(lines.first, contains('Dispositivo'));
    expect(lines[1], contains('esp-1'));
    expect(lines[1], contains('Ligado'));
    expect(lines[1], contains('220.5'));
    expect(lines[2], contains('esp-2'));
    expect(lines[2], contains('3.46'));
  });
}
