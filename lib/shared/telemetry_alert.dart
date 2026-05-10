class TelemetryAlert {
  final String id;
  final String message;
  final DateTime timestamp;
  final String type;

  TelemetryAlert({
    required this.id,
    required this.message,
    required this.timestamp,
    required this.type,
  });

  factory TelemetryAlert.fromJson(Map<String, dynamic> json) => TelemetryAlert(
        id: json['id'] as String,
        message: json['message'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        type: json['type'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
        'type': type,
      };
}
