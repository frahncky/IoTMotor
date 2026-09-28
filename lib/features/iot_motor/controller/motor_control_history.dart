part of 'motor_control_controller.dart';

/// Histórico de telemetria: filtros, retenção, gráficos e gravação.
extension MotorControlHistory on MotorControlController {
  UnmodifiableListView<TelemetrySample> get history =>
      UnmodifiableListView<TelemetrySample>(
        _recebeuDadoAtual ? _buildCombinedHistory() : <TelemetrySample>[],
      );

  UnmodifiableListView<TelemetryHistoryEntry> get historyEntries =>
      UnmodifiableListView<TelemetryHistoryEntry>(
        _buildCombinedHistoryEntries(),
      );

  UnmodifiableListView<TelemetryHistoryEntry> get filteredHistoryEntries =>
      UnmodifiableListView<TelemetryHistoryEntry>(
        _buildFilteredHistoryEntries(),
      );

  /// Mudanças do motor (ligou, desligou, modo) nas leituras filtradas.
  List<HistoryEvent> get historyEvents => historyEventsFrom(
    _buildFilteredHistoryEntries(),
    placaDoMotor: _motorDeviceId ?? 'esp32-01',
  );

  bool get hasActiveHistoryFilters =>
      _historyDeviceFilter != MotorControlController.historyFilterAll ||
      _historyPeriodFilter != MotorControlController.historyFilterAll ||
      _historyMetricFilter != MotorControlController.historyFilterAll ||
      _historyStateFilter != MotorControlController.historyFilterAll;

  String get historyRetentionSummary {
    final int entries = historyEntryCount;
    final String suffix = entries == 1 ? 'leitura' : 'leituras';
    return '$historyRetentionDays dias | $entries $suffix';
  }

  String get remoteHistoryRetentionSummary =>
      '$remoteHistoryRetentionDays dias no ESP32/SD';

  Future<void> loadPersistedHistory() async {
    if (_historyLoaded) {
      return;
    }
    _historyLoaded = true;

    try {
      final List<TelemetryHistoryEntry> persisted =
          await loadPersistedTelemetryHistory();
      if (persisted.isEmpty) {
        return;
      }

      for (final TelemetryHistoryEntry entry in persisted) {
        _registerDevice(entry.deviceId);
        _addSampleToHistory(
          deviceId: entry.deviceId,
          sample: entry.sample,
          persist: false,
        );
        final TelemetrySample? latest = _latestByDevice[entry.deviceId];
        if (latest == null ||
            entry.sample.timestamp.isAfter(latest.timestamp)) {
          _latestByDevice[entry.deviceId] = entry.sample;
          _syncStateFromTelemetry(
            deviceId: entry.deviceId,
            sample: entry.sample,
          );
        }
      }
      final int removed = _pruneTelemetryHistoryByRetention(persist: false);
      if (removed > 0) {
        _scheduleHistoryPersist();
      }
      statusMessage =
          removed > 0
              ? 'Histórico local carregado (${persisted.length - removed}).'
              : 'Histórico local carregado (${persisted.length}).';
      _notify();
    } catch (_) {
      // Keep in-memory history empty if storage is unavailable or invalid.
    }
  }

  void clearHistory() {
    _historyByDevice.clear();
    _latestByDevice.clear();
    _statusByDevice.clear();
    _motorOnByDevice.clear();
    _bootByDevice.clear();
    _relaysByDevice.clear();
    _runningByDevice.clear();
    _desarmeByDevice.clear();
    _modeByDevice.clear();
    _lastTelemetryReceivedByDevice.clear();
    _lastTelemetryStale = false;
    _clearHistoryFilters(shouldNotify: false);
    statusMessage = 'Histórico limpo para todos os dispositivos.';
    _historyPersistTimer?.cancel();
    _historyPersistTimer = null;
    unawaited(clearPersistedTelemetryHistory());
    _notify();
  }

  void setHistoryRetentionDays(int days) {
    final int normalized = _normalizeHistoryRetentionDays(days);
    if (historyRetentionDays == normalized) {
      return;
    }
    historyRetentionDays = normalized;
    final int removed = _pruneTelemetryHistoryByRetention();
    _scheduleSettingsPersist();
    _pendingMessage =
        removed > 0
            ? 'Retenção atualizada. $removed leituras antigas removidas.'
            : 'Retenção atualizada para $historyRetentionDays dias.';
    _notify();
  }

  void setRemoteHistoryRetentionDays(int days) {
    final int normalized = _normalizeHistoryRetentionDays(days);
    if (remoteHistoryRetentionDays == normalized) {
      return;
    }
    remoteHistoryRetentionDays = normalized;
    _scheduleSettingsPersist();
    _pendingMessage =
        'Retenção remota ajustada para $remoteHistoryRetentionDays dias.';
    _notify();
  }

  void setHistoryDeviceFilter(String value) {
    _historyDeviceFilter = _normalizeHistoryFilter(value);
    _notify();
  }

  void setHistoryPeriodFilter(String value) {
    _historyPeriodFilter = _normalizeHistoryFilter(value);
    _notify();
  }

  void setHistoryMetricFilter(String value) {
    _historyMetricFilter = _normalizeHistoryFilter(value);
    _notify();
  }

  void setHistoryStateFilter(String value) {
    _historyStateFilter = _normalizeHistoryFilter(value);
    _notify();
  }

  void clearHistoryFilters() {
    _clearHistoryFilters(shouldNotify: true);
  }

  List<TelemetrySample> _buildCombinedHistory() {
    final List<TelemetrySample> merged =
        _historyByDevice.values
            .expand((List<TelemetrySample> entries) => entries)
            .toList();
    merged.sort(
      (TelemetrySample a, TelemetrySample b) =>
          a.timestamp.compareTo(b.timestamp),
    );
    if (merged.length <= MotorControlController.maxHistory) {
      return merged;
    }
    return merged.sublist(merged.length - MotorControlController.maxHistory);
  }

  List<TelemetryHistoryEntry> _buildFilteredHistoryEntries() {
    return _buildCombinedHistoryEntries()
        .where(_matchesHistoryFilters)
        .toList(growable: false);
  }

  List<TelemetryHistoryEntry> _buildCombinedHistoryEntries() {
    final List<TelemetryHistoryEntry> merged = <TelemetryHistoryEntry>[];
    for (final MapEntry<String, List<TelemetrySample>> entry
        in _historyByDevice.entries) {
      for (final TelemetrySample sample in entry.value) {
        merged.add(TelemetryHistoryEntry(deviceId: entry.key, sample: sample));
      }
    }

    merged.sort(
      (TelemetryHistoryEntry a, TelemetryHistoryEntry b) =>
          a.sample.timestamp.compareTo(b.sample.timestamp),
    );
    if (merged.length <= MotorControlController.maxHistory) {
      return merged;
    }
    return merged.sublist(merged.length - MotorControlController.maxHistory);
  }

  int _pruneTelemetryHistoryByRetention({bool persist = true}) {
    final DateTime cutoff = DateTime.now().subtract(
      Duration(days: historyRetentionDays),
    );
    int removed = 0;
    final List<String> emptyDevices = <String>[];

    for (final MapEntry<String, List<TelemetrySample>> entry
        in _historyByDevice.entries) {
      final int before = entry.value.length;
      entry.value.removeWhere(
        (TelemetrySample sample) => sample.timestamp.isBefore(cutoff),
      );
      removed += before - entry.value.length;
      if (entry.value.isEmpty) {
        emptyDevices.add(entry.key);
      }
    }

    // Removido o expurgo de _latestByDevice para manter o último estado conhecido
    // mesmo que o histórico seja antigo.

    if (removed > 0 && persist) {
      _scheduleHistoryPersist();
    }
    return removed;
  }

  DateTime _chartBucketStart(DateTime timestamp) {
    final int interval = acquisitionConfig.chartMs;
    final int bucketMs =
        (timestamp.millisecondsSinceEpoch ~/ interval) * interval;
    return DateTime.fromMillisecondsSinceEpoch(
      bucketMs,
      isUtc: timestamp.isUtc,
    );
  }

  void _upsertChartHistory({
    required String deviceId,
    required TelemetrySample sample,
  }) {
    // Antes de receber a configuração oficial, mantém o comportamento antigo
    // para não descartar dados durante a conexão inicial.
    if (acquisitionConfig.revision == 0) {
      _addSampleToHistory(deviceId: deviceId, sample: sample);
      return;
    }

    final DateTime inicio = _chartBucketStart(sample.timestamp);
    final _ChartBucketAccumulator? atual = _chartBucketsByDevice[deviceId];

    // Pacote atrasado de uma janela já encerrada não volta no tempo no gráfico.
    if (atual != null && inicio.isBefore(atual.start)) return;

    if (atual == null || inicio != atual.start) {
      final _ChartBucketAccumulator novo = _ChartBucketAccumulator(
        inicio,
        sample,
      );
      _chartBucketsByDevice[deviceId] = novo;
      _addSampleToHistory(deviceId: deviceId, sample: novo.build());
      return;
    }

    atual.add(sample);
    final List<TelemetrySample>? historico = _historyByDevice[deviceId];
    if (historico == null || historico.isEmpty) {
      _addSampleToHistory(deviceId: deviceId, sample: atual.build());
      return;
    }

    // Atualiza o ponto corrente pela média das amostras da mesma janela, sem
    // criar um ponto extra. Energia/estado/modo usam o valor mais recente.
    if (historico.last.timestamp == atual.start) {
      historico[historico.length - 1] = atual.build();
      _scheduleHistoryPersist();
    } else {
      _addSampleToHistory(deviceId: deviceId, sample: atual.build());
    }
  }

  void _addSampleToHistory({
    required String deviceId,
    required TelemetrySample sample,
    bool persist = true,
  }) {
    final List<TelemetrySample> deviceHistory = _historyByDevice.putIfAbsent(
      deviceId,
      () => <TelemetrySample>[],
    );
    deviceHistory.add(sample);
    if (deviceHistory.length > MotorControlController.maxHistory) {
      deviceHistory.removeAt(0);
    }
    _pruneTelemetryHistoryByRetention(persist: false);
    if (persist) {
      _scheduleHistoryPersist();
    }
  }

  bool _matchesHistoryFilters(TelemetryHistoryEntry entry) {
    if (_historyDeviceFilter != MotorControlController.historyFilterAll &&
        entry.deviceId != _historyDeviceFilter) {
      return false;
    }
    if (!_matchesHistoryPeriod(entry.sample.timestamp)) {
      return false;
    }
    if (!_matchesHistoryMetric(entry.sample)) {
      return false;
    }
    if (!_matchesHistoryState(entry.sample)) {
      return false;
    }
    return true;
  }

  bool _matchesHistoryPeriod(DateTime timestamp) {
    if (_historyPeriodFilter == MotorControlController.historyFilterAll) {
      return true;
    }

    final DateTime now = DateTime.now();
    switch (_historyPeriodFilter) {
      case MotorControlController.historyPeriodToday:
        return timestamp.year == now.year &&
            timestamp.month == now.month &&
            timestamp.day == now.day;
      case MotorControlController.historyPeriodLastHour:
        return now.difference(timestamp) <= const Duration(hours: 1);
      case MotorControlController.historyPeriodLast24Hours:
        return now.difference(timestamp) <= const Duration(hours: 24);
      default:
        return true;
    }
  }

  bool _matchesHistoryMetric(TelemetrySample sample) {
    switch (_historyMetricFilter) {
      case MotorControlController.historyMetricVoltage:
        return sample.voltage != null;
      case MotorControlController.historyMetricCurrent:
        return sample.current != null;
      case MotorControlController.historyMetricPower:
        return sample.power != null;
      case MotorControlController.historyMetricPowerFactor:
        return sample.powerFactor != null;
      case MotorControlController.historyMetricFrequency:
        return sample.frequency != null;
      case MotorControlController.historyMetricEnergy:
        return sample.energy != null;
      case MotorControlController.historyMetricVibration:
        return sample.vibration != null;
      case MotorControlController.historyMetricTemperature:
        return sample.temperature != null;
      default:
        return true;
    }
  }

  bool _matchesHistoryState(TelemetrySample sample) {
    switch (_historyStateFilter) {
      case MotorControlController.historyStateOn:
        return sample.motorOn == true;
      case MotorControlController.historyStateOff:
        return sample.motorOn == false;
      case MotorControlController.historyStateUnknown:
        return sample.motorOn == null;
      default:
        return true;
    }
  }

  String _normalizeHistoryFilter(String value) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      return MotorControlController.historyFilterAll;
    }
    return normalized;
  }

  int _normalizeHistoryRetentionDays(int value) {
    return value.clamp(1, 3650);
  }

  void _clearHistoryFilters({required bool shouldNotify}) {
    _historyDeviceFilter = MotorControlController.historyFilterAll;
    _historyPeriodFilter = MotorControlController.historyFilterAll;
    _historyMetricFilter = MotorControlController.historyFilterAll;
    _historyStateFilter = MotorControlController.historyFilterAll;
    if (shouldNotify) {
      _notify();
    }
  }

  void _scheduleHistoryPersist() {
    if (_disposed) {
      return;
    }
    _historyPersistTimer?.cancel();
    _historyPersistTimer = Timer(
      MotorControlController._historyPersistDelay,
      () {
        unawaited(_persistHistory());
      },
    );
  }

  Future<void> _persistHistory() async {
    try {
      final List<TelemetryHistoryEntry> origem = _buildCombinedHistoryEntries();
      final List<TelemetryHistoryEntry> gravar = historyEntriesToPersist(
        origem,
        recordMs: acquisitionConfig.recordMs,
      );
      await savePersistedTelemetryHistory(gravar);
    } catch (_) {
      // Keep in-memory history active even if persistence fails.
    }
  }

  /// Horas dos últimos 7 dias da placa de sensores em uso (a dos alarmes ou,
  /// sem ela, a única que publicou histórico), em ordem.
  List<BoardHistoryHour> get boardHistory {
    final String? placa =
        _boardHistoryByDevice.containsKey(alarmsDeviceId)
            ? alarmsDeviceId
            : _boardHistoryByDevice.length == 1
            ? _boardHistoryByDevice.keys.first
            : null;
    if (placa == null) return const <BoardHistoryHour>[];
    final DateTime inicio = DateTime.now().subtract(
      const Duration(days: 7, hours: 1),
    );
    final List<BoardHistoryHour> horas = <BoardHistoryHour>[
      for (final List<BoardHistoryHour> dia
          in _boardHistoryByDevice[placa]!.values)
        for (final BoardHistoryHour hora in dia)
          if (hora.time.isAfter(inicio)) hora,
    ];
    horas.sort(
      (BoardHistoryHour a, BoardHistoryHour b) => a.time.compareTo(b.time),
    );
    return horas;
  }
}

class _ChartBucketAccumulator {
  _ChartBucketAccumulator(this.start, TelemetrySample sample) {
    add(sample);
  }

  final DateTime start;
  final Map<String, double> _sums = <String, double>{};
  final Map<String, int> _counts = <String, int>{};
  bool measuredByBoard = false;
  double? energy;
  bool? motorOn;
  String? mode;

  void _addNumber(String key, double? value) {
    if (value == null) return;
    _sums[key] = (_sums[key] ?? 0) + value;
    _counts[key] = (_counts[key] ?? 0) + 1;
  }

  double? _average(String key) {
    final int count = _counts[key] ?? 0;
    if (count == 0) return null;
    return _sums[key]! / count;
  }

  void add(TelemetrySample sample) {
    measuredByBoard = measuredByBoard || sample.measuredByBoard;
    _addNumber('voltage', sample.voltage);
    _addNumber('current', sample.current);
    _addNumber('power', sample.power);
    _addNumber('powerFactor', sample.powerFactor);
    _addNumber('frequency', sample.frequency);
    _addNumber('vibration', sample.vibration);
    _addNumber('temperature', sample.temperature);
    if (sample.energy != null) energy = sample.energy;
    if (sample.motorOn != null) motorOn = sample.motorOn;
    if (sample.mode != null) mode = sample.mode;
  }

  TelemetrySample build() => TelemetrySample(
    timestamp: start,
    measuredByBoard: measuredByBoard,
    voltage: _average('voltage'),
    current: _average('current'),
    power: _average('power'),
    powerFactor: _average('powerFactor'),
    frequency: _average('frequency'),
    energy: energy,
    vibration: _average('vibration'),
    temperature: _average('temperature'),
    motorOn: motorOn,
    mode: mode,
  );
}
