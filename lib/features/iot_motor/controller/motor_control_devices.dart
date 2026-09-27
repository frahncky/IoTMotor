part of 'motor_control_controller.dart';

/// Dispositivos e clientes: presença, conexão de cada placa e resumos de status.
extension MotorControlDevices on MotorControlController {
  UnmodifiableListView<String> get knownDeviceIds =>
      UnmodifiableListView<String>(_knownDevices.toList(growable: false));

  UnmodifiableListView<String> get connectedDeviceIds {
    final List<String> connected = _knownDevices
        .where(_isDeviceConnected)
        .toList(growable: false);
    return UnmodifiableListView<String>(connected);
  }

  DateTime? get latestTelemetryReceivedAt {
    DateTime? latest;
    for (final DateTime receivedAt in _lastTelemetryReceivedByDevice.values) {
      if (latest == null || receivedAt.isAfter(latest)) {
        latest = receivedAt;
      }
    }
    return latest;
  }

  bool get hasStaleTelemetry {
    if (!isConnected) {
      return false;
    }
    final DateTime? latest = latestTelemetryReceivedAt;
    if (latest == null) {
      return false;
    }
    return DateTime.now().difference(latest) >= MotorControlController.telemetryStaleTimeout;
  }

  String get telemetryStatusSummary {
    if (!isConnected) {
      return 'sem conexão';
    }

    final DateTime? latest = latestTelemetryReceivedAt;
    if (latest == null) {
      return 'aguardando leituras';
    }

    final Duration age = DateTime.now().difference(latest);
    final String ageText = _formatTelemetryAge(age);
    if (age >= MotorControlController.telemetryStaleTimeout) {
      return 'atrasada $ageText';
    }
    return 'ativa $ageText';
  }

  String get brokerStatusLabel {
    if (isBusy && !isConnected) {
      return 'conectando';
    }
    if (isConnected) {
      return 'conectado';
    }
    return 'desconectado';
  }

  String deviceStatusLabel(String deviceId) {
    if (isBusy && !isConnected) {
      return 'conectando';
    }
    return _isDeviceConnected(deviceId) ? 'conectado' : 'desconectado';
  }

  String get devicesStatusSummary {
    if (_knownDevices.isEmpty) {
      return 'nenhum dispositivo';
    }
    final List<String> entries = _knownDevices
        .map((String id) => '$id (${deviceStatusLabel(id)})')
        .toList(growable: false);
    return entries.join(' | ');
  }

  String get connectedDevicesSummary {
    if (connectedDeviceIds.isEmpty) {
      return 'nenhum conectado';
    }
    return connectedDeviceIds.join(', ');
  }

  String get devicesPresenceSummary {
    final UnmodifiableListView<String> conectados = connectedDeviceIds;
    final int quadro = conectados.contains('esp32-01') ? 1 : 0;
    final int sensores = conectados.contains('esp32-02') ? 1 : 0;
    return '${conectados.length} · Quadro $quadro · Sensores $sensores';
  }

  List<_CommandClientPresence> get _activeCommandClients {
    final DateTime limite = DateTime.now().subtract(MotorControlController._commandClientTtl);
    return _commandClients.values
        .where((_CommandClientPresence info) => info.seenAt.isAfter(limite))
        .toList(growable: false);
  }

  String get commandClientsSummary {
    final List<_CommandClientPresence> ativos = _activeCommandClients;
    final int apps = ativos
        .where((_CommandClientPresence info) => info.source == 'app')
        .length;
    final int webs = ativos
        .where((_CommandClientPresence info) => info.source == 'web')
        .length;
    return '${ativos.length} · App $apps · Web $webs';
  }

  bool _handleCommandClientPresence(String topic, String payload) {
    final List<String> partes = topic.split('/');
    if (partes.length < 4 ||
        partes[partes.length - 3] != 'clients' ||
        partes.last != 'presence') {
      return false;
    }

    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['kind'] != 'command_client') {
        return true;
      }
      final String source =
          decoded['source'] == 'app'
              ? 'app'
              : decoded['source'] == 'web'
              ? 'web'
              : '';
      final String topicId = partes[partes.length - 2].trim();
      final String clientId = (decoded['client_id']?.toString() ?? topicId).trim();
      if (source.isEmpty || clientId.isEmpty) return true;

      if (decoded['state'] == 'offline') {
        _commandClients.remove(clientId);
      } else {
        _commandClients[clientId] = _CommandClientPresence(
          source: source,
          seenAt: DateTime.now(),
        );
      }
      _notify();
    } catch (_) {
      // Presença inválida não deve afetar telemetria/comandos.
    }
    return true;
  }

  bool _pruneCommandClients() {
    final DateTime limite = DateTime.now().subtract(MotorControlController._commandClientTtl);
    final int antes = _commandClients.length;
    _commandClients.removeWhere(
      (String _, _CommandClientPresence info) => !info.seenAt.isAfter(limite),
    );
    return antes != _commandClients.length;
  }

  String _buildDeviceStateSummary(String deviceId, {String? fallback}) {
    final bool? isOn = _motorOnByDevice[deviceId];
    final String mode = _modeByDevice[deviceId]?.trim() ?? '';
    final MotorCommandType? type = mode.isEmpty ? null : _startTypeByMode(mode);

    if (isOn == true) {
      if (type != null) {
        return 'Motor ligado (${type.label}).';
      }
      if (mode.isNotEmpty) {
        return 'Motor ligado ($mode).';
      }
      return 'Motor ligado.';
    }

    if (isOn == false) {
      return 'Motor desligado.';
    }

    final String normalizedFallback = fallback?.trim() ?? '';
    if (normalizedFallback.isNotEmpty) {
      return normalizedFallback;
    }

    return 'Estado do motor desconhecido.';
  }

  void _registerDevice(String deviceId) {
    final String normalized = deviceId.trim();
    if (normalized.isEmpty ||
        normalized == '--' ||
        normalized == MotorControlController._autoDeviceId) {
      return;
    }
    _knownDevices.add(normalized);
  }

  void _markDeviceSeen(String deviceId) {
    _lastSeenByDevice[deviceId] = DateTime.now();
  }

  void _notifyConnectionHealthIfChanged() {
    final bool clientsChanged = _pruneCommandClients();
    final Set<String> current = connectedDeviceIds.toSet();
    final bool stale = hasStaleTelemetry;
    if (!clientsChanged &&
        _hasSameDevices(current, _lastConnectedDevices) &&
        stale == _lastTelemetryStale) {
      return;
    }

    if (stale && !_lastTelemetryStale) {
      final DateTime? latest = latestTelemetryReceivedAt;
      if (latest != null) {
        statusMessage =
            'Telemetria atrasada. Ultima leitura ${_formatTelemetryAge(DateTime.now().difference(latest))}.';
      }
    }

    _lastConnectedDevices = current;
    _lastTelemetryStale = stale;
    _notify();
  }

  bool _hasSameDevices(Set<String> a, Set<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final String value in a) {
      if (!b.contains(value)) {
        return false;
      }
    }
    return true;
  }

  bool _isDeviceConnected(String deviceId) {
    if (!isConnected) {
      return false;
    }
    final String status = _statusByDevice[deviceId]?.trim().toLowerCase() ?? '';
    if (status == 'offline') {
      return false;
    }
    final DateTime? lastSeen = _lastSeenByDevice[deviceId];
    if (lastSeen == null) {
      return false;
    }
    return DateTime.now().difference(lastSeen) <= MotorControlController._deviceOnlineTimeout;
  }

  String? _latestConnectedDeviceId() {
    String? selected;
    DateTime? selectedSeenAt;

    for (final String deviceId in _knownDevices) {
      if (!_isDeviceConnected(deviceId)) {
        continue;
      }

      final DateTime seenAt =
          _lastSeenByDevice[deviceId] ?? DateTime.fromMillisecondsSinceEpoch(0);

      if (selected == null ||
          selectedSeenAt == null ||
          seenAt.isAfter(selectedSeenAt)) {
        selected = deviceId;
        selectedSeenAt = seenAt;
      }
    }

    return selected;
  }
}

class _CommandClientPresence {
  const _CommandClientPresence({required this.source, required this.seenAt});

  final String source;
  final DateTime seenAt;
}
