enum TelemetryAlertSeverity { info, warning, critical }

class TelemetryAlert {
  const TelemetryAlert({
    required this.id,
    required this.deviceId,
    required this.title,
    required this.message,
    required this.metric,
    required this.severity,
    required this.createdAt,
    this.acknowledged = false,
  });

  final String id;
  final String deviceId;
  final String title;
  final String message;
  final String metric;
  final TelemetryAlertSeverity severity;
  final DateTime createdAt;
  final bool acknowledged;

  static TelemetryAlert? fromStoredMap(Map<String, dynamic> map) {
    final String id = '${map['id'] ?? ''}'.trim();
    final String deviceId = '${map['device_id'] ?? ''}'.trim();
    final String title = '${map['title'] ?? ''}'.trim();
    final String message = '${map['message'] ?? ''}'.trim();
    final String metric = '${map['metric'] ?? ''}'.trim();
    final DateTime? createdAt = DateTime.tryParse(
      '${map['created_at'] ?? ''}'.trim(),
    );

    if (id.isEmpty ||
        deviceId.isEmpty ||
        title.isEmpty ||
        message.isEmpty ||
        metric.isEmpty ||
        createdAt == null) {
      return null;
    }

    return TelemetryAlert(
      id: id,
      deviceId: deviceId,
      title: title,
      message: message,
      metric: metric,
      severity: _readSeverity(map['severity']),
      createdAt: createdAt,
      acknowledged: map['acknowledged'] == true,
    );
  }

  Map<String, dynamic> toStoredMap() {
    return <String, dynamic>{
      'id': id,
      'device_id': deviceId,
      'title': title,
      'message': message,
      'metric': metric,
      'severity': severity.name,
      'created_at': createdAt.toIso8601String(),
      'acknowledged': acknowledged,
    };
  }

  TelemetryAlert copyWith({bool? acknowledged}) {
    return TelemetryAlert(
      id: id,
      deviceId: deviceId,
      title: title,
      message: message,
      metric: metric,
      severity: severity,
      createdAt: createdAt,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }

  static TelemetryAlertSeverity _readSeverity(Object? raw) {
    final String value = '$raw'.trim();
    for (final TelemetryAlertSeverity severity
        in TelemetryAlertSeverity.values) {
      if (severity.name == value) {
        return severity;
      }
    }
    return TelemetryAlertSeverity.warning;
  }
}
