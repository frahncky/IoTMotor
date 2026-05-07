import '../models/telemetry_alert.dart';
import 'telemetry_alert_store_stub.dart'
    if (dart.library.io) 'telemetry_alert_store_io.dart'
    as impl;

Future<List<TelemetryAlert>> loadPersistedTelemetryAlerts() {
  return impl.loadPersistedTelemetryAlerts();
}

Future<void> savePersistedTelemetryAlerts(List<TelemetryAlert> alerts) {
  return impl.savePersistedTelemetryAlerts(alerts);
}

Future<void> clearPersistedTelemetryAlerts() {
  return impl.clearPersistedTelemetryAlerts();
}
