import '../models/telemetry_history_entry.dart';
import 'telemetry_history_store_stub.dart'
    if (dart.library.io) 'telemetry_history_store_io.dart'
    as impl;

Future<List<TelemetryHistoryEntry>> loadPersistedTelemetryHistory() {
  return impl.loadPersistedTelemetryHistory();
}

Future<void> savePersistedTelemetryHistory(
  List<TelemetryHistoryEntry> entries,
) {
  return impl.savePersistedTelemetryHistory(entries);
}

Future<void> clearPersistedTelemetryHistory() {
  return impl.clearPersistedTelemetryHistory();
}
