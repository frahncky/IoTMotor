part of 'motor_control_controller.dart';

/// Preferências do app: carregar, normalizar e gravar (com atraso).
extension MotorControlSettings on MotorControlController {
  Future<void> loadPersistedSettings() async {
    if (_settingsLoaded) {
      return;
    }
    _settingsLoaded = true;

    try {
      final MotorAppSettings? settings = await loadPersistedMotorSettings();
      if (settings == null) {
        return;
      }

      // Conexão: o que estava salvo vale, exceto quando o perfil MQTT ativo
      // mudou — aí quem manda é o perfil novo, que já preencheu os campos.
      final bool mesmoPerfil =
          activeProfileId.isEmpty || settings.profileId == activeProfileId;
      if (mesmoPerfil) {
        brokerController.text = settings.broker;
        portController.text = settings.port;
        // "motor_app" era fixo nas versões antigas: dois celulares com ele se
        // derrubavam no broker. Fica o id único gerado nesta instalação.
        if (settings.clientId != 'motor_app') {
          clientIdController.text = settings.clientId;
        }
        topicPrefixController.text = settings.topicPrefix;
        usernameController.text = settings.username;
        useTls = settings.useTls;
      }
      passwordController.clear();
      telemetryAlertsEnabled = settings.telemetryAlertsEnabled;
      voltageMinController.text = settings.voltageMin;
      voltageMaxController.text = settings.voltageMax;
      currentMaxController.text = settings.currentMax;
      vibrationMaxController.text = settings.vibrationMax;
      temperatureMaxController.text = settings.temperatureMax;
      dashboardTab = _normalizeDashboardTab(settings.dashboardTab);
      electricalPlotAId = _normalizePlotId(
        settings.electricalPlotAId,
        MotorAppSettings.defaultElectricalPlotAId,
      );
      electricalPlotBId = _normalizePlotId(
        settings.electricalPlotBId,
        MotorAppSettings.defaultElectricalPlotBId,
      );
      mechanicalPlotAId = _normalizePlotId(
        settings.mechanicalPlotAId,
        MotorAppSettings.defaultMechanicalPlotAId,
      );
      mechanicalPlotBId = _normalizePlotId(
        settings.mechanicalPlotBId,
        MotorAppSettings.defaultMechanicalPlotBId,
      );
      historyRetentionDays = _normalizeHistoryRetentionDays(
        settings.historyRetentionDays,
      );
      remoteHistoryRetentionDays = _normalizeHistoryRetentionDays(
        settings.remoteHistoryRetentionDays,
      );
      _pruneTelemetryHistoryByRetention(persist: false);
      _notify();
    } catch (_) {
      // Keep defaults if storage is unavailable or invalid.
    }
  }

  void setTls(bool enabled) {
    useTls = enabled;
    if (enabled && portController.text.trim() == '1883') {
      portController.text = '8883';
    } else if (!enabled && portController.text.trim() == '8883') {
      portController.text = '1883';
    }
    _scheduleSettingsPersist();
    _notify();
  }

  void refreshPreview() {
    _scheduleSettingsPersist();
  }

  void setDashboardTab(String value) {
    final String normalized = _normalizeDashboardTab(value);
    if (dashboardTab == normalized) {
      return;
    }
    dashboardTab = normalized;
    _scheduleSettingsPersist();
    _notify();
  }

  void setElectricalPlotAId(String value) {
    final String normalized = _normalizePlotId(
      value,
      MotorAppSettings.defaultElectricalPlotAId,
    );
    if (electricalPlotAId == normalized) {
      return;
    }
    electricalPlotAId = normalized;
    _scheduleSettingsPersist();
    _notify();
  }

  void setElectricalPlotBId(String value) {
    final String normalized = _normalizePlotId(
      value,
      MotorAppSettings.defaultElectricalPlotBId,
    );
    if (electricalPlotBId == normalized) {
      return;
    }
    electricalPlotBId = normalized;
    _scheduleSettingsPersist();
    _notify();
  }

  void setMechanicalPlotAId(String value) {
    final String normalized = _normalizePlotId(
      value,
      MotorAppSettings.defaultMechanicalPlotAId,
    );
    if (mechanicalPlotAId == normalized) {
      return;
    }
    mechanicalPlotAId = normalized;
    _scheduleSettingsPersist();
    _notify();
  }

  void setMechanicalPlotBId(String value) {
    final String normalized = _normalizePlotId(
      value,
      MotorAppSettings.defaultMechanicalPlotBId,
    );
    if (mechanicalPlotBId == normalized) {
      return;
    }
    mechanicalPlotBId = normalized;
    _scheduleSettingsPersist();
    _notify();
  }

  String _normalizeDashboardTab(String value) {
    final String normalized = value.trim();
    switch (normalized) {
      case MotorControlController.dashboardTabElectrical:
      case MotorControlController.dashboardTabMechanical:
      case MotorControlController.dashboardTabMeasurements:
        return normalized;
      default:
        return MotorControlController.dashboardTabMeasurements;
    }
  }

  String _normalizePlotId(String value, String fallback) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      return fallback;
    }
    return normalized;
  }

  void _scheduleSettingsPersist() {
    if (_disposed || !_settingsRestored) {
      return;
    }
    _settingsPersistTimer?.cancel();
    _settingsPersistTimer = Timer(
      MotorControlController._settingsPersistDelay,
      () {
        unawaited(_persistSettings());
      },
    );
  }

  Future<void> _persistSettings() {
    final MotorAppSettings snapshot = _buildSettingsSnapshot();
    return _settingsWrite = _settingsWrite.then((_) async {
      try {
        await savePersistedMotorSettings(snapshot);
      } catch (_) {
        // Keep app flow active even if settings persistence fails.
      }
    });
  }

  MotorAppSettings _buildSettingsSnapshot() {
    return MotorAppSettings(
      profileId: activeProfileId,
      broker: brokerController.text.trim(),
      port: portController.text.trim(),
      clientId: clientIdController.text.trim(),
      topicPrefix: topicPrefixController.text.trim(),
      username: usernameController.text.trim(),
      useTls: useTls,
      telemetryAlertsEnabled: telemetryAlertsEnabled,
      voltageMin: voltageMinController.text.trim(),
      voltageMax: voltageMaxController.text.trim(),
      currentMax: currentMaxController.text.trim(),
      vibrationMax: vibrationMaxController.text.trim(),
      temperatureMax: temperatureMaxController.text.trim(),
      dashboardTab: dashboardTab,
      electricalPlotAId: electricalPlotAId,
      electricalPlotBId: electricalPlotBId,
      mechanicalPlotAId: mechanicalPlotAId,
      mechanicalPlotBId: mechanicalPlotBId,
      historyRetentionDays: historyRetentionDays,
      remoteHistoryRetentionDays: remoteHistoryRetentionDays,
    );
  }
}
