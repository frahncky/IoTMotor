import 'dart:convert';

/// Um alarme da lista gravada na placa de sensores.
///
/// A mesma lista que o painel edita (`alarm_list.h` no firmware): diz qual
/// grandeza vigiar, de onde ela vem, se dispara acima ou abaixo e o limite.
class BoardAlarm {
  const BoardAlarm({
    required this.id,
    required this.field,
    required this.fromCommandBoard,
    required this.above,
    required this.limit,
    this.enabled = true,
    this.firing = false,
  });

  final String id;

  /// `voltage`, `current`, `power`, `vibration_peak`, `temperature`...
  final String field;

  /// `true` quando a grandeza vem do quadro de comando, não dos sensores.
  final bool fromCommandBoard;

  /// `true` dispara acima do limite; `false`, abaixo.
  final bool above;
  final double limit;
  final bool enabled;

  /// Estado publicado pela placa: só existe enquanto ela informa.
  final bool firing;

  static BoardAlarm? fromMap(Map<String, dynamic> raw) {
    final String id = (raw['id'] ?? '').toString();
    final String field = (raw['field'] ?? '').toString();
    final double? limit = (raw['limit'] as num?)?.toDouble();
    if (id.isEmpty || field.isEmpty || limit == null || !limit.isFinite) {
      return null;
    }
    return BoardAlarm(
      id: id,
      field: field,
      fromCommandBoard: raw['board'] == 'command',
      above: raw['above'] != false,
      limit: limit,
      enabled: raw['on'] != false,
      firing: raw['firing'] == true,
    );
  }

  Map<String, dynamic> toBoard() => <String, dynamic>{
    'id': id,
    'field': field,
    'board': fromCommandBoard ? 'command' : 'sensors',
    'above': above,
    'limit': limit,
    'on': enabled,
  };

  BoardAlarm copyWith({double? limit, bool? enabled, bool? above, bool? firing}) {
    return BoardAlarm(
      id: id,
      field: field,
      fromCommandBoard: fromCommandBoard,
      above: above ?? this.above,
      limit: limit ?? this.limit,
      enabled: enabled ?? this.enabled,
      firing: firing ?? this.firing,
    );
  }

  /// Lista publicada em `<prefixo>/<placa>/alarms`.
  static List<BoardAlarm> listFromPayload(String payload) {
    try {
      final Object? raw = jsonDecode(payload);
      if (raw is! Map<String, dynamic> || raw['alarms'] is! List<dynamic>) {
        return const <BoardAlarm>[];
      }
      return <BoardAlarm>[
        for (final Object? item in raw['alarms'] as List<dynamic>)
          if (item is Map<String, dynamic> && fromMap(item) != null)
            fromMap(item)!,
      ];
    } catch (_) {
      return const <BoardAlarm>[];
    }
  }

  static int maxFromPayload(String payload, {int fallback = 8}) {
    try {
      final Object? raw = jsonDecode(payload);
      if (raw is Map<String, dynamic> && raw['max'] is num) {
        final int max = (raw['max'] as num).toInt();
        if (max > 0) return max;
      }
    } catch (_) {
      // Lista ilegível: mantém o limite conhecido.
    }
    return fallback;
  }
}

/// Grandezas que o app oferece ao criar um alarme, com a placa de origem.
class AlarmQuantity {
  const AlarmQuantity({
    required this.field,
    required this.label,
    required this.unit,
    required this.fromCommandBoard,
    required this.min,
    required this.max,
  });

  final String field;
  final String label;
  final String unit;
  final bool fromCommandBoard;
  final double min;
  final double max;

  String get labelWithUnit => unit.isEmpty ? label : '$label ($unit)';
}

const List<AlarmQuantity> kAlarmQuantities = <AlarmQuantity>[
  AlarmQuantity(
    field: 'vibration_peak',
    label: 'Vibração (pico)',
    unit: 'g',
    fromCommandBoard: false,
    min: 0.02,
    max: 8,
  ),
  AlarmQuantity(
    field: 'vibration',
    label: 'Vibração (RMS)',
    unit: 'g',
    fromCommandBoard: false,
    min: 0.01,
    max: 8,
  ),
  AlarmQuantity(
    field: 'temperature',
    label: 'Temperatura',
    unit: '°C',
    fromCommandBoard: false,
    min: 1,
    max: 125,
  ),
  AlarmQuantity(
    field: 'battery',
    label: 'Tensão da bateria',
    unit: 'V',
    fromCommandBoard: false,
    min: 2.5,
    max: 4.3,
  ),
  AlarmQuantity(
    field: 'voltage',
    label: 'Tensão',
    unit: 'V',
    fromCommandBoard: true,
    min: 0,
    max: 600,
  ),
  AlarmQuantity(
    field: 'current',
    label: 'Corrente',
    unit: 'A',
    fromCommandBoard: true,
    min: 0,
    max: 200,
  ),
  AlarmQuantity(
    field: 'power',
    label: 'Potência',
    unit: 'W',
    fromCommandBoard: true,
    min: 0,
    max: 50000,
  ),
  AlarmQuantity(
    field: 'frequency',
    label: 'Frequência',
    unit: 'Hz',
    fromCommandBoard: true,
    min: 0,
    max: 120,
  ),
  AlarmQuantity(
    field: 'pf',
    label: 'Fator de potência',
    unit: '',
    fromCommandBoard: true,
    min: 0,
    max: 1,
  ),
];

AlarmQuantity? alarmQuantityFor(String field) {
  for (final AlarmQuantity q in kAlarmQuantities) {
    if (q.field == field) return q;
  }
  return null;
}

/// Rótulo de um alarme para as telas: "Corrente (A) acima de 12.5".
String describeAlarm(BoardAlarm alarm) {
  final AlarmQuantity? q = alarmQuantityFor(alarm.field);
  final String nome = q?.labelWithUnit ?? alarm.field;
  final String lado = alarm.above ? 'acima de' : 'abaixo de';
  return '$nome $lado ${alarm.limit}';
}
