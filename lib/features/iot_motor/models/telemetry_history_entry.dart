import 'telemetry_sample.dart';

class TelemetryHistoryEntry {
  const TelemetryHistoryEntry({required this.deviceId, required this.sample});

  final String deviceId;
  final TelemetrySample sample;
}
