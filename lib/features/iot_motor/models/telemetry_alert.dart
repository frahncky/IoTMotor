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
}
