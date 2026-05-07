import '../models/telemetry_history_entry.dart';
import '../models/telemetry_sample.dart';
import 'history_export_writer.dart';

Future<String> exportTelemetryHistoryCsv(
  List<TelemetryHistoryEntry> entries,
) async {
  final String csv = buildTelemetryHistoryCsv(entries);
  final DateTime now = DateTime.now();
  final String fileName = 'iotmotor_historico_${_fileTimestamp(now)}.csv';
  return writeHistoryCsv(csv, fileName);
}

String buildTelemetryHistoryCsv(List<TelemetryHistoryEntry> entries) {
  final List<TelemetryHistoryEntry> sorted = entries.toList(growable: false)
    ..sort(
      (TelemetryHistoryEntry a, TelemetryHistoryEntry b) =>
          a.sample.timestamp.compareTo(b.sample.timestamp),
    );

  final List<List<Object?>> rows = <List<Object?>>[
    <Object?>[
      'Data/Hora',
      'Dispositivo',
      'Motor',
      'Modo',
      'Tensao (V)',
      'Corrente (A)',
      'Vibracao (g)',
      'Temperatura (C)',
    ],
    for (final TelemetryHistoryEntry entry in sorted)
      _rowFor(entry.deviceId, entry.sample),
  ];

  return rows.map(_csvRow).join('\n');
}

List<Object?> _rowFor(String deviceId, TelemetrySample sample) {
  return <Object?>[
    sample.timestamp.toIso8601String(),
    deviceId,
    _motorStateLabel(sample.motorOn),
    sample.mode ?? '',
    _formatNumber(sample.voltage, 1),
    _formatNumber(sample.current, 2),
    _formatNumber(sample.vibration, 3),
    _formatNumber(sample.temperature, 1),
  ];
}

String _csvRow(List<Object?> values) {
  return values.map(_csvCell).join(',');
}

String _csvCell(Object? value) {
  final String text = value?.toString() ?? '';
  final bool mustQuote =
      text.contains(',') ||
      text.contains('"') ||
      text.contains('\n') ||
      text.contains('\r');
  if (!mustQuote) {
    return text;
  }
  return '"${text.replaceAll('"', '""')}"';
}

String _formatNumber(double? value, int digits) {
  if (value == null) {
    return '';
  }
  return value.toStringAsFixed(digits);
}

String _motorStateLabel(bool? motorOn) {
  if (motorOn == true) {
    return 'Ligado';
  }
  if (motorOn == false) {
    return 'Desligado';
  }
  return '';
}

String _fileTimestamp(DateTime value) {
  final String year = value.year.toString();
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  final String hour = value.hour.toString().padLeft(2, '0');
  final String minute = value.minute.toString().padLeft(2, '0');
  final String second = value.second.toString().padLeft(2, '0');
  return '$year$month${day}_$hour$minute$second';
}
