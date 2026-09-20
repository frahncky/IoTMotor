import 'dart:convert';

class TelemetrySample {
  const TelemetrySample({
    required this.timestamp,
    this.measuredByBoard = false,
    this.voltage,
    this.current,
    this.power,
    this.powerFactor,
    this.frequency,
    this.energy,
    this.vibration,
    this.temperature,
    this.motorOn,
    this.mode,
  });

  final DateTime timestamp;

  /// `true` quando o instante veio do relógio da placa, não do aparelho.
  final bool measuredByBoard;
  final double? voltage;
  final double? current;
  final double? power;
  final double? powerFactor;
  final double? frequency;
  final double? energy;
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
    final double? power = _readDouble(source, const <String>[
      'power',
      'potencia',
      'w',
    ]);
    final double? powerFactor = _readDouble(source, const <String>[
      'pf',
      'power_factor',
      'fator_potencia',
      'fp',
    ]);
    final double? frequency = _readDouble(source, const <String>[
      'frequency',
      'frequencia',
      'hz',
    ]);
    final double? energy = _readDouble(source, const <String>[
      'energy',
      'energy_kwh',
      'energia',
      'kwh',
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
        power == null &&
        powerFactor == null &&
        frequency == null &&
        energy == null &&
        vibration == null &&
        temperature == null &&
        motorOn == null &&
        mode == null) {
      return null;
    }

    // Hora da placa (campo ts, segundos UTC) vale mais que a hora de chegada:
    // um CSV exportado depois nao fica com o relogio de quem exportou.
    final double? carimbo = _readDouble(source, const <String>['ts']);
    final DateTime instante =
        carimbo != null && carimbo > 1700000000
            ? DateTime.fromMillisecondsSinceEpoch(
              (carimbo * 1000).round(),
              isUtc: true,
            ).toLocal()
            : timestamp;

    return TelemetrySample(
      timestamp: instante,
      measuredByBoard: carimbo != null && carimbo > 1700000000,
      voltage: voltage,
      current: current,
      power: power,
      powerFactor: powerFactor,
      frequency: frequency,
      energy: energy,
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
      if (power != null) 'power': power,
      if (powerFactor != null) 'pf': powerFactor,
      if (frequency != null) 'frequency': frequency,
      if (energy != null) 'energy': energy,
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
