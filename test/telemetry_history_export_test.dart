import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/models/telemetry_history_entry.dart';
import 'package:iotmotor/features/iot_motor/models/telemetry_sample.dart';
import 'package:iotmotor/features/iot_motor/services/telemetry_history_export.dart';

void main() {
  test('a hora da placa (ts) vale mais que a hora de chegada', () {
    final DateTime chegada = DateTime(2020);
    // ts em segundos UTC: 2026-09-20 16:00 UTC.
    final TelemetrySample? comHora = TelemetrySample.tryParsePayload(
      '{"device_id":"esp32-01","voltage":220.5,"ts":1789920000}',
      timestamp: chegada,
    );
    expect(comHora, isNotNull);
    expect(comHora!.measuredByBoard, isTrue);
    expect(
      comHora.timestamp.toUtc(),
      DateTime.utc(2026, 9, 20, 16),
    );

    // Sem relogio sincronizado a placa nao manda ts: vale a hora de chegada.
    final TelemetrySample? semHora = TelemetrySample.tryParsePayload(
      '{"device_id":"esp32-01","voltage":220.5}',
      timestamp: chegada,
    );
    expect(semHora!.measuredByBoard, isFalse);
    expect(semHora.timestamp, chegada);

    // Segundos desde o boot nao viram uma data de 1970.
    final TelemetrySample? boot = TelemetrySample.tryParsePayload(
      '{"device_id":"esp32-01","voltage":220.5,"ts":1200}',
      timestamp: chegada,
    );
    expect(boot!.measuredByBoard, isFalse);
    expect(boot.timestamp, chegada);
  });


  test('TelemetrySample serializa e restaura leituras persistidas', () {
    final TelemetrySample original = TelemetrySample(
      timestamp: DateTime(2026, 5, 7, 9),
      voltage: 220.1,
      current: 3.2,
      power: 704.3,
      powerFactor: 0.97,
      frequency: 60.0,
      energy: 1.234,
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
    expect(restored.power, 704.3);
    expect(restored.powerFactor, 0.97);
    expect(restored.frequency, 60.0);
    expect(restored.energy, 1.234);
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
          power: 704.3,
          powerFactor: 0.97,
          frequency: 60,
          energy: 1.234,
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
    expect(lines[1], contains('704.3'));
    expect(lines[1], contains('0.97'));
    expect(lines[1], contains('60.00'));
    expect(lines[1], contains('1.234'));
    expect(lines[2], contains('esp-2'));
    expect(lines[2], contains('3.46'));
  });
}
