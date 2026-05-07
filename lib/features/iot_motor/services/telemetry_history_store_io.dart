import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/telemetry_history_entry.dart';
import '../models/telemetry_sample.dart';

const String _historyFileName = 'telemetry_history_v1.json';
const String _jsonVersionKey = 'version';
const String _jsonEntriesKey = 'entries';
const int _storageVersion = 1;

Future<List<TelemetryHistoryEntry>> loadPersistedTelemetryHistory() async {
  final File file = await _resolveHistoryFile();
  if (!await file.exists()) {
    return const <TelemetryHistoryEntry>[];
  }

  try {
    final String rawContent = await file.readAsString();
    if (rawContent.trim().isEmpty) {
      return const <TelemetryHistoryEntry>[];
    }
    final dynamic decoded = jsonDecode(rawContent);
    final dynamic rawEntries =
        decoded is List
            ? decoded
            : (decoded is Map ? decoded[_jsonEntriesKey] : null);
    if (rawEntries is! List) {
      return const <TelemetryHistoryEntry>[];
    }

    final List<TelemetryHistoryEntry> entries = <TelemetryHistoryEntry>[];
    for (final dynamic rawEntry in rawEntries) {
      if (rawEntry is! Map) {
        continue;
      }
      final String deviceId = '${rawEntry['device_id'] ?? ''}'.trim();
      if (deviceId.isEmpty) {
        continue;
      }
      final dynamic rawSample = rawEntry['sample'];
      final Map<String, dynamic> sampleMap =
          rawSample is Map
              ? Map<String, dynamic>.from(rawSample)
              : Map<String, dynamic>.from(rawEntry);
      final TelemetrySample? sample = TelemetrySample.fromStoredMap(sampleMap);
      if (sample == null) {
        continue;
      }
      entries.add(TelemetryHistoryEntry(deviceId: deviceId, sample: sample));
    }
    entries.sort(
      (TelemetryHistoryEntry a, TelemetryHistoryEntry b) =>
          a.sample.timestamp.compareTo(b.sample.timestamp),
    );
    return entries;
  } catch (_) {
    return const <TelemetryHistoryEntry>[];
  }
}

Future<void> savePersistedTelemetryHistory(
  List<TelemetryHistoryEntry> entries,
) async {
  final File file = await _resolveHistoryFile();
  final String payload = jsonEncode(<String, dynamic>{
    _jsonVersionKey: _storageVersion,
    _jsonEntriesKey: entries
        .map(
          (TelemetryHistoryEntry entry) => <String, dynamic>{
            'device_id': entry.deviceId,
            'sample': entry.sample.toStoredMap(),
          },
        )
        .toList(growable: false),
  });
  await file.writeAsString(payload, flush: true);
}

Future<void> clearPersistedTelemetryHistory() async {
  final File file = await _resolveHistoryFile();
  if (await file.exists()) {
    await file.delete();
  }
}

Future<File> _resolveHistoryFile() async {
  final Directory directory = await getApplicationSupportDirectory();
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return File('${directory.path}${Platform.pathSeparator}$_historyFileName');
}
