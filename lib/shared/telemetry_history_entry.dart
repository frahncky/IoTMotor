class TelemetryHistoryEntry {
  final String id;
  final double value;
  final DateTime timestamp;

  TelemetryHistoryEntry({
    required this.id,
    required this.value,
    required this.timestamp,
  });

  factory TelemetryHistoryEntry.fromJson(Map<String, dynamic> json) => TelemetryHistoryEntry(
        id: json['id'] as String,
        value: (json['value'] as num).toDouble(),
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'value': value,
        'timestamp': timestamp.toIso8601String(),
      };
}
