part of 'motor_control_controller.dart';

/// Alertas de telemetria do app: limites, avaliação, reconhecimento e gravação.
extension MotorControlAlerts on MotorControlController {
  UnmodifiableListView<TelemetryAlert> get alerts =>
      UnmodifiableListView<TelemetryAlert>(
        _alertHistory.toList(growable: false),
      );

  int get pendingAlertsCount =>
      _alertHistory.where((TelemetryAlert alert) => !alert.acknowledged).length;

  TelemetryAlert? get latestAlert =>
      _alertHistory.isEmpty ? null : _alertHistory.first;

  int get acknowledgedAlertsCount =>
      _alertHistory.where((TelemetryAlert alert) => alert.acknowledged).length;

  int get criticalAlertsCount =>
      _alertHistory
          .where(
            (TelemetryAlert alert) =>
                alert.severity == TelemetryAlertSeverity.critical,
          )
          .length;

  String get alertStatusSummary {
    if (!telemetryAlertsEnabled) {
      return 'alertas desativados';
    }
    if (pendingAlertsCount == 0) {
      return 'sem alertas pendentes';
    }
    return pendingAlertsCount == 1
        ? '1 alerta pendente'
        : '$pendingAlertsCount alertas pendentes';
  }

  String? get alertThresholdsError {
    final String? voltageMinError = MqttSettingsValidators.validateDecimal(
      voltageMinController.text,
      fieldLabel: 'a tensão mínima',
      min: 0,
      allowZero: false,
    );
    if (voltageMinError != null) {
      return voltageMinError;
    }

    final String? voltageMaxError = MqttSettingsValidators.validateDecimal(
      voltageMaxController.text,
      fieldLabel: 'a tensão máxima',
      min: 0,
      allowZero: false,
    );
    if (voltageMaxError != null) {
      return voltageMaxError;
    }

    final double? minVoltage = _readThreshold(voltageMinController);
    final double? maxVoltage = _readThreshold(voltageMaxController);
    if (minVoltage != null && maxVoltage != null && minVoltage >= maxVoltage) {
      return 'A tensão mínima deve ser menor que a máxima.';
    }

    return MqttSettingsValidators.validateDecimal(
          currentMaxController.text,
          fieldLabel: 'o limite de corrente',
          min: 0,
          allowZero: false,
        ) ??
        MqttSettingsValidators.validateDecimal(
          vibrationMaxController.text,
          fieldLabel: 'o limite de vibração',
          min: 0,
          allowZero: false,
        ) ??
        MqttSettingsValidators.validateDecimal(
          temperatureMaxController.text,
          fieldLabel: 'o limite de temperatura',
          min: 0,
          allowZero: false,
        );
  }

  Future<void> loadPersistedAlerts() async {
    if (_alertsLoaded) {
      return;
    }
    _alertsLoaded = true;

    try {
      final List<TelemetryAlert> persisted =
          await loadPersistedTelemetryAlerts();
      if (persisted.isEmpty) {
        return;
      }

      _alertHistory
        ..clear()
        ..addAll(persisted.take(200));
      _notify();
    } catch (_) {
      // Keep in-memory alerts empty if storage is unavailable or invalid.
    }
  }

  void clearAlerts() {
    _alertHistory.clear();
    _activeAlertKeys.clear();
    _pendingMessage = 'Alertas limpos.';
    _alertsPersistTimer?.cancel();
    _alertsPersistTimer = null;
    unawaited(clearPersistedTelemetryAlerts());
    _notify();
  }

  void acknowledgeAlert(String id) {
    final int index = _alertHistory.indexWhere(
      (TelemetryAlert alert) => alert.id == id,
    );
    if (index == -1) {
      return;
    }
    _alertHistory[index] = _alertHistory[index].copyWith(acknowledged: true);
    _scheduleAlertsPersist();
    _notify();
  }

  void acknowledgeAllAlerts() {
    bool changed = false;
    for (int i = 0; i < _alertHistory.length; i++) {
      final TelemetryAlert alert = _alertHistory[i];
      if (alert.acknowledged) {
        continue;
      }
      _alertHistory[i] = alert.copyWith(acknowledged: true);
      changed = true;
    }
    if (!changed) {
      return;
    }
    _pendingMessage = 'Alertas reconhecidos.';
    _scheduleAlertsPersist();
    _notify();
  }

  void setTelemetryAlertsEnabled(bool enabled) {
    telemetryAlertsEnabled = enabled;
    if (!enabled) {
      _activeAlertKeys.clear();
    }
    _scheduleSettingsPersist();
    _notify();
  }

  TelemetryAlert? _evaluateTelemetryAlerts({
    required String deviceId,
    required TelemetrySample sample,
  }) {
    if (!telemetryAlertsEnabled) {
      return null;
    }

    TelemetryAlert? firstAlert;

    TelemetryAlert? capture(TelemetryAlert? alert) {
      firstAlert ??= alert;
      return alert;
    }

    capture(_evaluateVoltageAlert(deviceId: deviceId, value: sample.voltage));
    capture(
      _evaluateUpperLimitAlert(
        deviceId: deviceId,
        metricKey: 'current',
        title: 'Corrente alta',
        metricLabel: 'corrente',
        unit: 'A',
        value: sample.current,
        limit: _readThreshold(currentMaxController),
        severity: TelemetryAlertSeverity.critical,
        digits: 2,
      ),
    );
    capture(
      _evaluateUpperLimitAlert(
        deviceId: deviceId,
        metricKey: 'vibration',
        title: 'Vibração elevada',
        metricLabel: 'vibração',
        unit: 'mm/s',
        value: sample.vibration,
        limit: _readThreshold(vibrationMaxController),
        severity: TelemetryAlertSeverity.warning,
        digits: 2,
      ),
    );
    capture(
      _evaluateUpperLimitAlert(
        deviceId: deviceId,
        metricKey: 'temperature',
        title: 'Temperatura alta',
        metricLabel: 'temperatura',
        unit: 'C',
        value: sample.temperature,
        limit: _readThreshold(temperatureMaxController),
        severity: TelemetryAlertSeverity.critical,
        digits: 1,
      ),
    );

    return firstAlert;
  }

  TelemetryAlert? _evaluateVoltageAlert({
    required String deviceId,
    required double? value,
  }) {
    final double? min = _readThreshold(voltageMinController);
    final double? max = _readThreshold(voltageMaxController);
    if (value == null || min == null || max == null || min >= max) {
      return null;
    }

    final String alertKey = '$deviceId:voltage';
    final bool outOfRange = value < min || value > max;
    if (outOfRange) {
      if (_activeAlertKeys.contains(alertKey)) {
        return null;
      }
      _activeAlertKeys.add(alertKey);
      final String range =
          '${min.toStringAsFixed(1)} a ${max.toStringAsFixed(1)} V';
      return _registerAlert(
        deviceId: deviceId,
        metricKey: 'voltage',
        title: 'Tensão fora da faixa',
        message:
            '${nomeDaPlaca(deviceId)}: tensão ${value.toStringAsFixed(1)} V fora da faixa $range.',
        severity: TelemetryAlertSeverity.warning,
      );
    }

    _resolveTelemetryAlert(deviceId: deviceId, metricKey: 'voltage');
    return null;
  }

  TelemetryAlert? _evaluateUpperLimitAlert({
    required String deviceId,
    required String metricKey,
    required String title,
    required String metricLabel,
    required String unit,
    required double? value,
    required double? limit,
    required TelemetryAlertSeverity severity,
    required int digits,
  }) {
    if (value == null || limit == null || limit <= 0) {
      return null;
    }

    final String alertKey = '$deviceId:$metricKey';
    if (value > limit) {
      if (_activeAlertKeys.contains(alertKey)) {
        return null;
      }
      _activeAlertKeys.add(alertKey);
      return _registerAlert(
        deviceId: deviceId,
        metricKey: metricKey,
        title: title,
        message:
            '${nomeDaPlaca(deviceId)}: $metricLabel ${value.toStringAsFixed(digits)} $unit acima do limite ${limit.toStringAsFixed(digits)} $unit.',
        severity: severity,
      );
    }

    if (value <= limit * 0.95) {
      _resolveTelemetryAlert(deviceId: deviceId, metricKey: metricKey);
    }
    return null;
  }

  void _resolveTelemetryAlert({
    required String deviceId,
    required String metricKey,
  }) {
    _activeAlertKeys.remove('$deviceId:$metricKey');
    bool changed = false;
    for (int i = 0; i < _alertHistory.length; i++) {
      final TelemetryAlert alert = _alertHistory[i];
      if (alert.acknowledged ||
          alert.deviceId != deviceId ||
          alert.metric != metricKey) {
        continue;
      }
      _alertHistory[i] = alert.copyWith(acknowledged: true);
      changed = true;
    }
    if (changed) {
      _scheduleAlertsPersist();
    }
  }

  TelemetryAlert _registerAlert({
    required String deviceId,
    required String metricKey,
    required String title,
    required String message,
    required TelemetryAlertSeverity severity,
  }) {
    final DateTime now = DateTime.now();
    final TelemetryAlert alert = TelemetryAlert(
      id: '${deviceId}_${metricKey}_${now.microsecondsSinceEpoch}',
      deviceId: deviceId,
      title: title,
      message: message,
      metric: metricKey,
      severity: severity,
      createdAt: now,
    );

    _alertHistory.insert(0, alert);
    if (_alertHistory.length > 100) {
      _alertHistory.removeRange(100, _alertHistory.length);
    }
    _pendingMessage = '$title: $message';
    _scheduleAlertsPersist();
    return alert;
  }

  double? _readThreshold(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '.'));
  }

  void _scheduleAlertsPersist() {
    if (_disposed) {
      return;
    }
    _alertsPersistTimer?.cancel();
    _alertsPersistTimer = Timer(MotorControlController._alertsPersistDelay, () {
      unawaited(_persistAlerts());
    });
  }

  Future<void> _persistAlerts() async {
    try {
      await savePersistedTelemetryAlerts(_alertHistory);
    } catch (_) {
      // Keep in-memory alerts active even if persistence fails.
    }
  }
}
