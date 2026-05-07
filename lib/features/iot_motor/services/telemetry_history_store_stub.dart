import '../models/telemetry_history_entry.dart';

Future<List<TelemetryHistoryEntry>> loadPersistedTelemetryHistory() async {
  return const <TelemetryHistoryEntry>[];
}

Future<void> savePersistedTelemetryHistory(
  List<TelemetryHistoryEntry> entries,
) async {}

Future<void> clearPersistedTelemetryHistory() async {}
