import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/motor_app_settings.dart';

const String _settingsFileName = 'motor_settings_v1.json';
const String _jsonVersionKey = 'version';
const String _jsonSettingsKey = 'settings';
const int _storageVersion = 1;

Future<MotorAppSettings?> loadPersistedMotorSettings() async {
  final File file = await _resolveSettingsFile();
  if (!await file.exists()) {
    return null;
  }

  try {
    final String rawContent = await file.readAsString();
    if (rawContent.trim().isEmpty) {
      return null;
    }
    final dynamic decoded = jsonDecode(rawContent);
    final dynamic rawSettings =
        decoded is Map ? decoded[_jsonSettingsKey] ?? decoded : null;
    if (rawSettings is! Map) {
      return null;
    }
    return MotorAppSettings.fromMap(Map<String, dynamic>.from(rawSettings));
  } catch (_) {
    return null;
  }
}

Future<void> savePersistedMotorSettings(MotorAppSettings settings) async {
  final File file = await _resolveSettingsFile();
  final String payload = jsonEncode(<String, dynamic>{
    _jsonVersionKey: _storageVersion,
    _jsonSettingsKey: settings.toMap(),
  });
  await file.writeAsString(payload, flush: true);
}

Future<File> _resolveSettingsFile() async {
  final Directory directory = await getApplicationSupportDirectory();
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return File('${directory.path}${Platform.pathSeparator}$_settingsFileName');
}
