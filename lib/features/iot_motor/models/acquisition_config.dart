class AcquisitionConfig {
  const AcquisitionConfig({
    required this.revision,
    required this.pzemReadMs,
    required this.publishMs,
    required this.chartMs,
    required this.recordMs,
    this.vibrationHz = 1000,
    this.vibrationWindowMs = 1000,
    this.historyBucketS = 3600,
    this.historyRetentionDays = 7,
  });

  final int revision;
  final int pzemReadMs;
  final int publishMs;
  final int chartMs;
  final int recordMs;
  final int vibrationHz;
  final int vibrationWindowMs;
  final int historyBucketS;
  final int historyRetentionDays;

  static const AcquisitionConfig defaults = AcquisitionConfig(
    revision: 0,
    pzemReadMs: 1000,
    publishMs: 1000,
    chartMs: 1000,
    recordMs: 1000,
  );

  static const Map<String, AcquisitionConfig> presets = <String, AcquisitionConfig>{
    'realtime': AcquisitionConfig(
      revision: 0,
      pzemReadMs: 1000,
      publishMs: 1000,
      chartMs: 1000,
      recordMs: 1000,
    ),
    'monitoring': AcquisitionConfig(
      revision: 0,
      pzemReadMs: 1000,
      publishMs: 2000,
      chartMs: 2000,
      recordMs: 5000,
    ),
    'economic': AcquisitionConfig(
      revision: 0,
      pzemReadMs: 5000,
      publishMs: 5000,
      chartMs: 5000,
      recordMs: 30000,
    ),
  };

  factory AcquisitionConfig.fromJson(Map<String, dynamic> json) {
    int inteiro(String key, int fallback) {
      final Object? value = json[key];
      if (value is num) return value.round();
      return int.tryParse('$value') ?? fallback;
    }

    return AcquisitionConfig(
      revision: inteiro('revision', 0),
      pzemReadMs: inteiro('pzem_read_ms', 1000),
      publishMs: inteiro('publish_ms', 1000),
      chartMs: inteiro('chart_ms', 1000),
      recordMs: inteiro('record_ms', 1000),
      vibrationHz: inteiro('vibration_hz', 1000),
      vibrationWindowMs: inteiro('vibration_window_ms', 1000),
      historyBucketS: inteiro('history_bucket_s', 3600),
      historyRetentionDays: inteiro('history_retention_days', 7),
    );
  }

  Map<String, dynamic> toBoard() => <String, dynamic>{
        'pzem_read_ms': pzemReadMs,
        'publish_ms': publishMs,
        'chart_ms': chartMs,
        'record_ms': recordMs,
      };

  String? validate() {
    if (pzemReadMs < 1000 || pzemReadMs > 10000) {
      return 'Aquisição elétrica deve ficar entre 1 e 10 s.';
    }
    if (publishMs < 1000 || publishMs > 60000) {
      return 'Publicação MQTT deve ficar entre 1 e 60 s.';
    }
    if (pzemReadMs > publishMs) {
      return 'A aquisição elétrica deve ser igual ou mais rápida que a publicação MQTT.';
    }
    if (chartMs < publishMs || chartMs > 60000) {
      return 'O gráfico deve ser igual ou mais lento que a publicação MQTT.';
    }
    if (recordMs < publishMs || recordMs > 600000) {
      return 'O registro deve ser igual ou mais lento que a publicação MQTT.';
    }
    return null;
  }
}
