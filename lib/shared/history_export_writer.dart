class HistoryExportWriter {
  static String exportCsv(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return '';
    final headers = data.first.keys.toList();
    final buffer = StringBuffer();
    buffer.writeln(headers.join(','));
    for (final row in data) {
      buffer.writeln(headers.map((h) => row[h]).join(','));
    }
    return buffer.toString();
  }
}
