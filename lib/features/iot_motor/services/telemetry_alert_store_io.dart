import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/telemetry_alert.dart';

const String _alertsFileName = 'telemetry_alerts_v1.json';
const String _jsonVersionKey = 'version';
const String _jsonAlertsKey = 'alerts';
const int _storageVersion = 1;

Future<List<TelemetryAlert>> loadPersistedTelemetryAlerts() async {
  final File file = await _resolveAlertsFile();
  if (!await file.exists()) {
    return const <TelemetryAlert>[];
  }

  try {
    final String rawContent = await file.readAsString();
    if (rawContent.trim().isEmpty) {
      return const <TelemetryAlert>[];
    }
    final dynamic decoded = jsonDecode(rawContent);
    final dynamic rawAlerts =
        decoded is List
            ? decoded
            : (decoded is Map ? decoded[_jsonAlertsKey] : null);
    if (rawAlerts is! List) {
      return const <TelemetryAlert>[];
    }

    final List<TelemetryAlert> alerts = <TelemetryAlert>[];
    for (final dynamic rawAlert in rawAlerts) {
      if (rawAlert is! Map) {
        continue;
      }
      final TelemetryAlert? alert = TelemetryAlert.fromStoredMap(
        Map<String, dynamic>.from(rawAlert),
      );
      if (alert != null) {
        alerts.add(alert);
      }
    }
    alerts.sort(
      (TelemetryAlert a, TelemetryAlert b) =>
          b.createdAt.compareTo(a.createdAt),
    );
    return alerts;
  } catch (_) {
    return const <TelemetryAlert>[];
  }
}

Future<void> savePersistedTelemetryAlerts(List<TelemetryAlert> alerts) async {
  final File file = await _resolveAlertsFile();
  final String payload = jsonEncode(<String, dynamic>{
    _jsonVersionKey: _storageVersion,
    _jsonAlertsKey: alerts
        .map((TelemetryAlert alert) => alert.toStoredMap())
        .toList(growable: false),
  });
  await file.writeAsString(payload, flush: true);
}

Future<void> clearPersistedTelemetryAlerts() async {
  final File file = await _resolveAlertsFile();
  if (await file.exists()) {
    await file.delete();
  }
}

Future<File> _resolveAlertsFile() async {
  final Directory directory = await getApplicationSupportDirectory();
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return File('${directory.path}${Platform.pathSeparator}$_alertsFileName');
}
