class MotorAppSettings {
  static const String dashboardTabMeasurements = 'measurements';
  static const String dashboardTabElectrical = 'electrical';
  static const String dashboardTabMechanical = 'mechanical';
  static const String defaultElectricalPlotAId = 'voltage';
  static const String defaultElectricalPlotBId = 'current';
  static const String defaultMechanicalPlotAId = 'vibration';
  static const String defaultMechanicalPlotBId = 'temperature';
  static const int defaultHistoryRetentionDays = 30;
  static const int defaultRemoteHistoryRetentionDays = 30;

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
    this.dashboardTab = dashboardTabMeasurements,
    this.electricalPlotAId = defaultElectricalPlotAId,
    this.electricalPlotBId = defaultElectricalPlotBId,
    this.mechanicalPlotAId = defaultMechanicalPlotAId,
    this.mechanicalPlotBId = defaultMechanicalPlotBId,
    this.historyRetentionDays = defaultHistoryRetentionDays,
    this.remoteHistoryRetentionDays = defaultRemoteHistoryRetentionDays,
  });

  factory MotorAppSettings.initial() {
    return const MotorAppSettings(
      broker: 'broker.hivemq.com',
      port: '1883',
      clientId: 'motor_app',
      topicPrefix: 'iotmotor',
      username: '',
      useTls: false,
      telemetryAlertsEnabled: true,
      voltageMin: '190',
      voltageMax: '240',
      currentMax: '10',
      vibrationMax: '1.5',
      temperatureMax: '70',
    );
  }

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
  final String dashboardTab;
  final String electricalPlotAId;
  final String electricalPlotBId;
  final String mechanicalPlotAId;
  final String mechanicalPlotBId;
  final int historyRetentionDays;
  final int remoteHistoryRetentionDays;

  MotorAppSettings copyWith({
    String? broker,
    String? port,
    String? clientId,
    String? topicPrefix,
    String? username,
    bool? useTls,
    bool? telemetryAlertsEnabled,
    String? voltageMin,
    String? voltageMax,
    String? currentMax,
    String? vibrationMax,
    String? temperatureMax,
    String? dashboardTab,
    String? electricalPlotAId,
    String? electricalPlotBId,
    String? mechanicalPlotAId,
    String? mechanicalPlotBId,
    int? historyRetentionDays,
    int? remoteHistoryRetentionDays,
  }) {
    return MotorAppSettings(
      broker: broker ?? this.broker,
      port: port ?? this.port,
      clientId: clientId ?? this.clientId,
      topicPrefix: topicPrefix ?? this.topicPrefix,
      username: username ?? this.username,
      useTls: useTls ?? this.useTls,
      telemetryAlertsEnabled:
          telemetryAlertsEnabled ?? this.telemetryAlertsEnabled,
      voltageMin: voltageMin ?? this.voltageMin,
      voltageMax: voltageMax ?? this.voltageMax,
      currentMax: currentMax ?? this.currentMax,
      vibrationMax: vibrationMax ?? this.vibrationMax,
      temperatureMax: temperatureMax ?? this.temperatureMax,
      dashboardTab: dashboardTab ?? this.dashboardTab,
      electricalPlotAId: electricalPlotAId ?? this.electricalPlotAId,
      electricalPlotBId: electricalPlotBId ?? this.electricalPlotBId,
      mechanicalPlotAId: mechanicalPlotAId ?? this.mechanicalPlotAId,
      mechanicalPlotBId: mechanicalPlotBId ?? this.mechanicalPlotBId,
      historyRetentionDays: historyRetentionDays ?? this.historyRetentionDays,
      remoteHistoryRetentionDays:
          remoteHistoryRetentionDays ?? this.remoteHistoryRetentionDays,
    );
  }

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
      dashboardTab: _readDashboardTab(map['dashboard_tab']),
      electricalPlotAId: _readPlotId(
        map['electrical_plot_a'],
        defaultElectricalPlotAId,
      ),
      electricalPlotBId: _readPlotId(
        map['electrical_plot_b'],
        defaultElectricalPlotBId,
      ),
      mechanicalPlotAId: _readPlotId(
        map['mechanical_plot_a'],
        defaultMechanicalPlotAId,
      ),
      mechanicalPlotBId: _readPlotId(
        map['mechanical_plot_b'],
        defaultMechanicalPlotBId,
      ),
      historyRetentionDays: _readRetentionDays(map['history_retention_days']),
      remoteHistoryRetentionDays: _readRetentionDays(
        map['remote_history_retention_days'] ?? map['remote_retention_days'],
        fallback: defaultRemoteHistoryRetentionDays,
      ),
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
      'dashboard_tab': dashboardTab,
      'electrical_plot_a': electricalPlotAId,
      'electrical_plot_b': electricalPlotBId,
      'mechanical_plot_a': mechanicalPlotAId,
      'mechanical_plot_b': mechanicalPlotBId,
      'history_retention_days': historyRetentionDays,
      'remote_history_retention_days': remoteHistoryRetentionDays,
    };
  }

  static String _readDashboardTab(Object? raw) {
    final String value = '$raw'.trim();
    switch (value) {
      case dashboardTabElectrical:
      case dashboardTabMechanical:
      case dashboardTabMeasurements:
        return value;
      default:
        return dashboardTabMeasurements;
    }
  }

  static String _readPlotId(Object? raw, String fallback) {
    final String value = '$raw'.trim();
    if (value.isEmpty || value == 'null') {
      return fallback;
    }
    return value;
  }

  static int _readRetentionDays(
    Object? raw, {
    int fallback = defaultHistoryRetentionDays,
  }) {
    final int? value = raw is int ? raw : int.tryParse('${raw ?? ''}'.trim());
    if (value == null) {
      return fallback;
    }
    return value.clamp(1, 3650);
  }
}
