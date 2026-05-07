import '../models/telemetry_alert.dart';

Future<List<TelemetryAlert>> loadPersistedTelemetryAlerts() async {
  return const <TelemetryAlert>[];
}

Future<void> savePersistedTelemetryAlerts(List<TelemetryAlert> alerts) async {}

Future<void> clearPersistedTelemetryAlerts() async {}
