class DataAcquisitionConfig {
  const DataAcquisitionConfig({
    this.pzemIntervalMs = 3000,
    this.mqttIntervalMs = 1000,
    this.vibrationWindowMs = 1000,
    this.chartIntervalMs = 1000,
    this.recordIntervalMs = 1000,
  });

  static const int vibrationSamplingHz = 1000;
  static const int historySampleMs = 1000;
  static const int historyBucketMinutes = 60;
  static const int retentionDays = 7;

  static const DataAcquisitionConfig realtime = DataAcquisitionConfig(
    pzemIntervalMs: 1000,
    mqttIntervalMs: 1000,
    vibrationWindowMs: 1000,
    chartIntervalMs: 1000,
    recordIntervalMs: 1000,
  );

  static const DataAcquisitionConfig monitoring = DataAcquisitionConfig(
    pzemIntervalMs: 2000,
    mqttIntervalMs: 2000,
    vibrationWindowMs: 1000,
    chartIntervalMs: 2000,
    recordIntervalMs: 5000,
  );

  static const DataAcquisitionConfig economic = DataAcquisitionConfig(
    pzemIntervalMs: 5000,
    mqttIntervalMs: 5000,
    vibrationWindowMs: 1000,
    chartIntervalMs: 5000,
    recordIntervalMs: 30000,
  );

  final int pzemIntervalMs;
  final int mqttIntervalMs;
  final int vibrationWindowMs;
  final int chartIntervalMs;
  final int recordIntervalMs;

  String get signature =>
      '$pzemIntervalMs-$mqttIntervalMs-$vibrationWindowMs-$chartIntervalMs-$recordIntervalMs';

  DataAcquisitionConfig copyWith({
    int? pzemIntervalMs,
    int? mqttIntervalMs,
    int? vibrationWindowMs,
    int? chartIntervalMs,
    int? recordIntervalMs,
  }) {
    return DataAcquisitionConfig(
      pzemIntervalMs: pzemIntervalMs ?? this.pzemIntervalMs,
      mqttIntervalMs: mqttIntervalMs ?? this.mqttIntervalMs,
      vibrationWindowMs: vibrationWindowMs ?? this.vibrationWindowMs,
      chartIntervalMs: chartIntervalMs ?? this.chartIntervalMs,
      recordIntervalMs: recordIntervalMs ?? this.recordIntervalMs,
    );
  }

  bool get isValid =>
      pzemIntervalMs >= 1000 &&
      pzemIntervalMs <= 10000 &&
      mqttIntervalMs >= 1000 &&
      mqttIntervalMs <= 60000 &&
      vibrationWindowMs >= 500 &&
      vibrationWindowMs <= 2000 &&
      chartIntervalMs >= mqttIntervalMs &&
      chartIntervalMs <= 60000 &&
      recordIntervalMs >= mqttIntervalMs &&
      recordIntervalMs <= 600000;

  String? get validationMessage {
    if (pzemIntervalMs < 1000 || pzemIntervalMs > 10000) {
      return 'A leitura elétrica deve ficar entre 1 e 10 s.';
    }
    if (mqttIntervalMs < 1000 || mqttIntervalMs > 60000) {
      return 'A telemetria deve ficar entre 1 e 60 s.';
    }
    if (vibrationWindowMs < 500 || vibrationWindowMs > 2000) {
      return 'A janela RMS deve ficar entre 0,5 e 2 s.';
    }
    if (chartIntervalMs < mqttIntervalMs) {
      return 'O gráfico não pode atualizar mais rápido que a telemetria.';
    }
    if (recordIntervalMs < mqttIntervalMs) {
      return 'O registro não pode ser mais rápido que a telemetria.';
    }
    if (chartIntervalMs > 60000 || recordIntervalMs > 600000) {
      return 'Revise os intervalos de gráfico e registro.';
    }
    return null;
  }

  static int? readInt(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}');
  }
}
