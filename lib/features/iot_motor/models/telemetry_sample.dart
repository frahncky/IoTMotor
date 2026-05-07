import 'dart:convert';

class TelemetrySample {
  const TelemetrySample({
    required this.timestamp,
    this.voltage,
    this.current,
    this.vibration,
    this.temperature,
    this.motorOn,
    this.mode,
  });

  final DateTime timestamp;
  final double? voltage;
  final double? current;
  final double? vibration;
  final double? temperature;
  final bool? motorOn;
  final String? mode;

  static TelemetrySample? tryParsePayload(
    String payload, {
    DateTime? timestamp,
  }) {
    try {
      final dynamic decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return fromDynamicMap(decoded, timestamp: timestamp ?? DateTime.now());
    } catch (_) {
      return null;
    }
  }

  static TelemetrySample? fromDynamicMap(
    Map<String, dynamic> input, {
    required DateTime timestamp,
  }) {
    final dynamic nested = input['data'];
    final Map<String, dynamic> source =
        nested is Map<String, dynamic> ? nested : input;

    final double? voltage = _readDouble(source, const <String>[
      'voltage',
      'tensao',
      'v',
    ]);
    final double? current = _readDouble(source, const <String>[
      'current',
      'corrente',
      'i',
    ]);
    final double? vibration = _readDouble(source, const <String>[
      'vibration',
      'vibracao',
      'vib',
    ]);
    final double? temperature = _readDouble(source, const <String>[
      'temperature',
      'temperatura',
      'temp',
    ]);
    final bool? motorOn = _readBool(source, const <String>[
      'motor_on',
      'motorOn',
      'ligado',
      'is_on',
    ]);
    final String? mode = _readString(source, const <String>[
      'mode',
      'modo',
      'connection_type',
    ]);

    if (voltage == null &&
        current == null &&
        vibration == null &&
        temperature == null &&
        motorOn == null &&
        mode == null) {
      return null;
    }

    return TelemetrySample(
      timestamp: timestamp,
      voltage: voltage,
      current: current,
      vibration: vibration,
      temperature: temperature,
      motorOn: motorOn,
      mode: mode,
    );
  }

  static TelemetrySample? fromStoredMap(Map<String, dynamic> input) {
    final String timestampText = '${input['timestamp'] ?? ''}'.trim();
    final DateTime? timestamp = DateTime.tryParse(timestampText);
    if (timestamp == null) {
      return null;
    }
    return fromDynamicMap(input, timestamp: timestamp);
  }

  Map<String, dynamic> toStoredMap() {
    return <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      if (voltage != null) 'voltage': voltage,
      if (current != null) 'current': current,
      if (vibration != null) 'vibration': vibration,
      if (temperature != null) 'temperature': temperature,
      if (motorOn != null) 'motor_on': motorOn,
      if (mode != null && mode!.trim().isNotEmpty) 'mode': mode,
    };
  }

  static double? _readDouble(Map<String, dynamic> source, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = source[key];
      if (value == null) {
        continue;
      }
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        final String normalized = value.replaceAll(',', '.');
        final double? parsed = double.tryParse(normalized);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  static bool? _readBool(Map<String, dynamic> source, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = source[key];
      if (value == null) {
        continue;
      }
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value != 0;
      }
      if (value is String) {
        final String normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1' || normalized == 'on') {
          return true;
        }
        if (normalized == 'false' || normalized == '0' || normalized == 'off') {
          return false;
        }
      }
    }
    return null;
  }

  static String? _readString(Map<String, dynamic> source, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = source[key];
      if (value == null) {
        continue;
      }
      final String text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }
}
