import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/motor_command_type.dart';

const String _startTypesFileName = 'start_types_v1.json';
const String _jsonTypesKey = 'start_types';
const String _jsonVersionKey = 'version';
const int _storageVersion = 1;

Future<List<MotorCommandType>> loadPersistedStartTypes() async {
  final File file = await _resolveStartTypesFile();
  if (!await file.exists()) {
    return const <MotorCommandType>[];
  }

  try {
    final String rawContent = await file.readAsString();
    if (rawContent.trim().isEmpty) {
      return const <MotorCommandType>[];
    }

    final dynamic decoded = jsonDecode(rawContent);
    final dynamic rawTypes =
        decoded is List
            ? decoded
            : (decoded is Map ? decoded[_jsonTypesKey] : null);
    if (rawTypes is! List) {
      return const <MotorCommandType>[];
    }

    final List<MotorCommandType> parsed = <MotorCommandType>[];
    for (final dynamic entry in rawTypes) {
      if (entry is! Map) {
        continue;
      }

      final String id = '${entry['id'] ?? ''}'.trim();
      final String label = '${entry['label'] ?? ''}'.trim();
      final String mode = '${entry['mode'] ?? ''}'.trim();
      if (id.isEmpty || label.isEmpty || mode.isEmpty) {
        continue;
      }

      parsed.add(MotorCommandType.start(id: id, label: label, mode: mode));
    }
    return parsed;
  } catch (_) {
    return const <MotorCommandType>[];
  }
}

Future<void> savePersistedStartTypes(List<MotorCommandType> startTypes) async {
  final File file = await _resolveStartTypesFile();
  final List<Map<String, String>> serialized = startTypes
      .map(
        (MotorCommandType type) => <String, String>{
          'id': type.id,
          'label': type.label,
          'mode': type.mode,
        },
      )
      .toList(growable: false);

  final String payload = jsonEncode(<String, Object>{
    _jsonVersionKey: _storageVersion,
    _jsonTypesKey: serialized,
  });
  await file.writeAsString(payload, flush: true);
}

Future<File> _resolveStartTypesFile() async {
  final Directory directory = await getApplicationSupportDirectory();
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  return File('${directory.path}${Platform.pathSeparator}$_startTypesFileName');
}
