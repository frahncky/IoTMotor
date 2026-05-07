class MotorAppSettings {
  const MotorAppSettings({
    required this.broker,
    required this.port,
    required this.clientId,
    required this.topicPrefix,
    required this.username,
    required this.useTls,
    required this.telemetryAlertsEnabled,
    required this.voltageMin,
    required this.voltageMax,
    required this.currentMax,
    required this.vibrationMax,
    required this.temperatureMax,
  });

  final String broker;
  final String port;
  final String clientId;
  final String topicPrefix;
  final String username;
  final bool useTls;
  final bool telemetryAlertsEnabled;
  final String voltageMin;
  final String voltageMax;
  final String currentMax;
  final String vibrationMax;
  final String temperatureMax;

  static MotorAppSettings? fromMap(Map<String, dynamic> map) {
    final String broker = '${map['broker'] ?? ''}'.trim();
    final String port = '${map['port'] ?? ''}'.trim();
    final String clientId = '${map['client_id'] ?? ''}'.trim();
    final String topicPrefix = '${map['topic_prefix'] ?? ''}'.trim();
    if (broker.isEmpty ||
        port.isEmpty ||
        clientId.isEmpty ||
        topicPrefix.isEmpty) {
      return null;
    }

    return MotorAppSettings(
      broker: broker,
      port: port,
      clientId: clientId,
      topicPrefix: topicPrefix,
      username: '${map['username'] ?? ''}'.trim(),
      useTls: map['use_tls'] == true,
      telemetryAlertsEnabled: map['telemetry_alerts_enabled'] != false,
      voltageMin: '${map['voltage_min'] ?? '190'}'.trim(),
      voltageMax: '${map['voltage_max'] ?? '240'}'.trim(),
      currentMax: '${map['current_max'] ?? '10'}'.trim(),
      vibrationMax: '${map['vibration_max'] ?? '1.5'}'.trim(),
      temperatureMax: '${map['temperature_max'] ?? '70'}'.trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'broker': broker,
      'port': port,
      'client_id': clientId,
      'topic_prefix': topicPrefix,
      'username': username,
      'use_tls': useTls,
      'telemetry_alerts_enabled': telemetryAlertsEnabled,
      'voltage_min': voltageMin,
      'voltage_max': voltageMax,
      'current_max': currentMax,
      'vibration_max': vibrationMax,
      'temperature_max': temperatureMax,
    };
  }
}
