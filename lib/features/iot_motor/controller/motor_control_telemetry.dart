part of 'motor_control_controller.dart';

/// Mensagens recebidas do broker: telemetria, status e estado das placas.
extension MotorControlTelemetry on MotorControlController {
  void _handlePayload(String topic, String payload) {
    if (_handleCommandClientPresence(topic, payload)) return;
    // Partidas e respostas não dependem da configuração ativa: o dispositivo
    // vem do próprio tópico (prefixo/dispositivo/profiles).
    final List<String> partes = topic.split('/');
    if (topic.endsWith('/system/acquisition')) {
      try {
        final Object? decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          final AcquisitionConfig nova = AcquisitionConfig.fromJson(decoded);
          if (nova.validate() == null) {
            if (nova.chartMs != acquisitionConfig.chartMs) {
              _chartBucketsByDevice.clear();
            }
            acquisitionConfig = nova;
            statusMessage =
                'Configuração de aquisição sincronizada (revisão ${nova.revision}).';
            _notify();
          }
        }
      } catch (_) {}
      return;
    }
    final String deviceIdDoTopico =
        partes.length >= 2 ? partes[partes.length - 2] : '';
    // Histórico da placa: prefixo/dispositivo/history/<dia>.
    if (partes.length >= 3 && partes[partes.length - 2] == 'history') {
      final int? dia = int.tryParse(partes.last);
      if (dia != null && dia >= 0 && dia < 7) {
        final String placa = partes[partes.length - 3];
        (_boardHistoryByDevice[placa] ??=
            <int, List<BoardHistoryHour>>{})[dia] = BoardHistoryHour.parseDay(
          payload,
        );
        _notify();
      }
      return;
    }
    if (topic.endsWith('/motor_info')) {
      final MotorInfo? info = MotorInfo.tryParse(payload);
      if (info == null) {
        _motorInfoByDevice.remove(deviceIdDoTopico);
      } else {
        _motorInfoByDevice[deviceIdDoTopico] = info;
      }
      _conferirManutencao(deviceIdDoTopico);
      _notify();
      return;
    }
    if (topic.endsWith('/capabilities')) {
      try {
        final Object? dados = jsonDecode(payload);
        if (dados is Map<String, dynamic>) {
          final Object? versao = dados['firmware_version'];
          final String firmware = versao is String ? versao : '';
          firmwareByDevice[deviceIdDoTopico] = firmware;
          _tratarFirmwarePublicado(deviceIdDoTopico, firmware);
          _notify();
        }
      } catch (_) {}
      return;
    }
    if (topic.endsWith('/alarms')) {
      _aplicarAlarmesDaPlaca(deviceId: deviceIdDoTopico, payload: payload);
      return;
    }
    if (topic.endsWith('/auth')) {
      // Desafio da placa para os comandos cifrados (command_seal.dart).
      _service.registrarAuth(topic, payload);
      return;
    }
    if (topic.endsWith('/profiles')) {
      _aplicarPerfisDaPlaca(deviceId: deviceIdDoTopico, payload: payload);
      return;
    }
    if (topic.endsWith('/command_ack')) {
      _tratarRespostaDeAtualizacao(deviceIdDoTopico, payload);
      _tratarRespostaDeComando(payload);
      return;
    }
    // Contatores, sessão e partida em andamento: úteis mesmo antes de a
    // configuração ativa existir, e é daqui que sai o Ligar/Desligar.
    if (topic.endsWith('/telemetry')) {
      _syncBenchFromTelemetry(deviceId: deviceIdDoTopico, payload: payload);
    }

    final MqttConnectionConfig? config = _service.activeConfig;
    if (config == null) {
      return;
    }

    final String? deviceId = _extractDeviceId(topic: topic, config: config);
    if (deviceId == null) {
      return;
    }
    _registerDevice(deviceId);
    _markDeviceSeen(deviceId);

    if (_isStatusTopic(topic)) {
      _statusByDevice[deviceId] = payload;
      _tratarStatusDeAtualizacao(deviceId, payload);
      _syncMotorStateFromStatus(deviceId: deviceId, payload: payload);
      if (deviceId == selectedDeviceId) {
        statusMessage = _buildDeviceStateSummary(deviceId, fallback: payload);
      }
      _notify();
      return;
    }

    if (!_isTelemetryTopic(topic)) {
      return;
    }

    final TelemetrySample? sample = TelemetrySample.tryParsePayload(payload);
    if (sample == null) {
      if (deviceId == selectedDeviceId) {
        statusMessage = 'Falha ao ler payload de telemetria.';
        _notify();
      }
      return;
    }

    _recebeuDadoAtual = true;
    _latestByDevice[deviceId] = sample;
    _lastTelemetryReceivedByDevice[deviceId] = DateTime.now();
    _syncStateFromTelemetry(deviceId: deviceId, sample: sample);

    _upsertChartHistory(deviceId: deviceId, sample: sample);

    final TelemetryAlert? alert = _evaluateTelemetryAlerts(
      deviceId: deviceId,
      sample: sample,
    );

    statusMessage =
        alert != null
            ? '${alert.title}: ${alert.message}'
            : '${_buildDeviceStateSummary(deviceId)} Último pacote em ${formatTimestamp(sample.timestamp)}';

    _notify();
  }

  TelemetrySample? _buildCombinedLatestSample() {
    if (_latestByDevice.isEmpty) {
      return null;
    }

    double? voltage;
    DateTime? voltageAt;
    double? current;
    DateTime? currentAt;
    double? power;
    DateTime? powerAt;
    double? powerFactor;
    DateTime? powerFactorAt;
    double? frequency;
    DateTime? frequencyAt;
    double? energy;
    DateTime? energyAt;
    double? vibration;
    DateTime? vibrationAt;
    double? temperature;
    DateTime? temperatureAt;
    bool? motorOn;
    DateTime? motorOnAt;
    String? mode;
    DateTime? modeAt;
    DateTime latestTimestamp = DateTime.fromMillisecondsSinceEpoch(0);

    for (final TelemetrySample sample in _latestByDevice.values) {
      if (sample.timestamp.isAfter(latestTimestamp)) {
        latestTimestamp = sample.timestamp;
      }

      if (sample.voltage != null &&
          (voltageAt == null || sample.timestamp.isAfter(voltageAt))) {
        voltage = sample.voltage;
        voltageAt = sample.timestamp;
      }

      if (sample.current != null &&
          (currentAt == null || sample.timestamp.isAfter(currentAt))) {
        current = sample.current;
        currentAt = sample.timestamp;
      }

      if (sample.power != null &&
          (powerAt == null || sample.timestamp.isAfter(powerAt))) {
        power = sample.power;
        powerAt = sample.timestamp;
      }

      if (sample.powerFactor != null &&
          (powerFactorAt == null || sample.timestamp.isAfter(powerFactorAt))) {
        powerFactor = sample.powerFactor;
        powerFactorAt = sample.timestamp;
      }

      if (sample.frequency != null &&
          (frequencyAt == null || sample.timestamp.isAfter(frequencyAt))) {
        frequency = sample.frequency;
        frequencyAt = sample.timestamp;
      }

      if (sample.energy != null &&
          (energyAt == null || sample.timestamp.isAfter(energyAt))) {
        energy = sample.energy;
        energyAt = sample.timestamp;
      }

      if (sample.vibration != null &&
          (vibrationAt == null || sample.timestamp.isAfter(vibrationAt))) {
        vibration = sample.vibration;
        vibrationAt = sample.timestamp;
      }

      if (sample.temperature != null &&
          (temperatureAt == null || sample.timestamp.isAfter(temperatureAt))) {
        temperature = sample.temperature;
        temperatureAt = sample.timestamp;
      }

      if (sample.motorOn != null &&
          (motorOnAt == null || sample.timestamp.isAfter(motorOnAt))) {
        motorOn = sample.motorOn;
        motorOnAt = sample.timestamp;
      }

      final String normalizedMode = sample.mode?.trim() ?? '';
      if (normalizedMode.isNotEmpty &&
          (modeAt == null || sample.timestamp.isAfter(modeAt))) {
        mode = normalizedMode;
        modeAt = sample.timestamp;
      }
    }

    if (voltage == null &&
        current == null &&
        power == null &&
        powerFactor == null &&
        frequency == null &&
        energy == null &&
        vibration == null &&
        temperature == null &&
        motorOn == null &&
        mode == null) {
      return null;
    }

    return TelemetrySample(
      timestamp: latestTimestamp,
      voltage: voltage,
      current: current,
      power: power,
      powerFactor: powerFactor,
      frequency: frequency,
      energy: energy,
      vibration: vibration,
      temperature: temperature,
      motorOn: motorOn,
      mode: mode,
    );
  }

  bool _isStatusTopic(String topic) => topic.endsWith('/status');

  bool _isTelemetryTopic(String topic) => topic.endsWith('/telemetry');

  String? _extractDeviceId({
    required String topic,
    required MqttConnectionConfig config,
  }) {
    final List<String> topicSegments =
        topic.split('/').where((String part) => part.isNotEmpty).toList();
    if (topicSegments.length < 3) {
      return null;
    }

    final String leaf = topicSegments.last;
    if (leaf != 'status' && leaf != 'telemetry') {
      return null;
    }

    final List<String> prefixSegments =
        config.topicPrefix
            .split('/')
            .where((String part) => part.isNotEmpty)
            .toList();
    if (prefixSegments.length + 2 > topicSegments.length) {
      return null;
    }

    for (int i = 0; i < prefixSegments.length; i++) {
      if (topicSegments[i] != prefixSegments[i]) {
        return null;
      }
    }

    final String deviceId = topicSegments[topicSegments.length - 2].trim();
    if (deviceId.isEmpty) {
      return null;
    }
    return deviceId;
  }

  void _syncMotorStateFromStatus({
    required String deviceId,
    required String payload,
  }) {
    final String normalized = payload.trim().toLowerCase();
    if (normalized == 'motor_started') {
      _motorOnByDevice[deviceId] = true;
      return;
    }

    if (normalized == 'motor_stopped' || normalized == 'offline') {
      _motorOnByDevice[deviceId] = false;
      _modeByDevice[deviceId] = MotorCommandType.stop.mode;
      return;
    }

    if (normalized == 'online' && _motorOnByDevice[deviceId] == null) {
      _motorOnByDevice[deviceId] = false;
    }
  }

  void _syncStateFromTelemetry({
    required String deviceId,
    required TelemetrySample sample,
  }) {
    if (sample.motorOn != null) {
      _motorOnByDevice[deviceId] = sample.motorOn!;
      if (!sample.motorOn! &&
          (sample.mode == null || sample.mode!.trim().isEmpty)) {
        _modeByDevice[deviceId] = MotorCommandType.stop.mode;
      }
    }

    final String normalizedMode = sample.mode?.trim() ?? '';
    if (normalizedMode.isNotEmpty) {
      _modeByDevice[deviceId] = normalizedMode;
    }
  }

  /// O firmware atual publica `boot` e `relays` (em vez de `motor_on`):
  /// o motor conta como ligado quando algum contator está ligado.
  void _syncBenchFromTelemetry({
    required String deviceId,
    required String payload,
  }) {
    final Object? dados;
    try {
      dados = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (dados is! Map<String, dynamic>) return;
    final Object? tensao = dados['voltage'];
    final double? tensaoValida =
        tensao is num && tensao.toDouble().isFinite && tensao.toDouble() > 0
            ? tensao.toDouble()
            : null;
    if (dados['pzem_ok'] == false || tensaoValida == null) {
      _voltageByDevice.remove(deviceId);
    } else {
      _voltageByDevice[deviceId] = tensaoValida;
    }
    final Object? boot = dados['boot'];
    if (boot is String && RegExp(r'^[0-9a-f]{16}$').hasMatch(boot)) {
      _bootByDevice[deviceId] = boot;
    }
    final Object? emExecucao = dados['profile'];
    runningProfileId =
        emExecucao is String && emExecucao.isNotEmpty ? emExecucao : null;
    final Object? toleranciaSemLink = dados['link_grace_s'];
    if (toleranciaSemLink is num) {
      final int segundos = toleranciaSemLink.toInt();
      if (segundos == -1 || (segundos >= 0 && segundos <= 3600)) {
        linkGraceSeconds = segundos;
      }
    }
    final MotorUsage? uso = MotorUsage.fromMap(dados);
    if (uso != null) {
      _motorUsageByDevice[deviceId] = uso;
      _conferirManutencao(deviceId);
    }
    final Object? relays = dados['relays'];
    if (relays is List &&
        relays.length == 4 &&
        relays.every((v) => v is bool)) {
      final List<bool> estados = relays.cast<bool>();
      _relaysByDevice[deviceId] = estados;
      _motorOnByDevice[deviceId] = estados.any((ligado) => ligado);
      _lastTelemetryReceivedByDevice[deviceId] = DateTime.now();
      _markDeviceSeen(deviceId);
    }
    final Object? desarme = dados['trip_field'];
    if (desarme is String && desarme.isNotEmpty) {
      _desarmeByDevice[deviceId] = desarme;
    } else {
      _desarmeByDevice.remove(deviceId);
    }
    final Object? girando = dados['motor_running'];
    if (girando is bool) {
      _runningByDevice[deviceId] = girando;
    } else {
      _runningByDevice.remove(deviceId);
    }
    // Quem decide o alarme é a placa: ela diz quais estão disparados agora.
    final Object? disparados = dados['alarms_firing'];
    if (disparados is List) {
      _firingAlarmsAt = DateTime.now();
      firingAlarmIds = <String>{
        for (final Object? id in disparados)
          if (id is String && id.isNotEmpty) id,
      };
      boardAlarms = <BoardAlarm>[
        for (final BoardAlarm alarme in boardAlarms)
          alarme.copyWith(firing: firingAlarmIds.contains(alarme.id)),
      ];
    }
  }

  /// Placa que aciona os contatores: a selecionada, se publicar `relays`;
  /// senão a primeira que publicar.
  String? get _benchDeviceId {
    if (_relaysByDevice.containsKey(selectedDeviceId)) return selectedDeviceId;
    return _relaysByDevice.keys.isEmpty ? null : _relaysByDevice.keys.first;
  }

  bool _hasFreshTelemetryFrom(String deviceId) {
    if (!isConnected) return false;
    final String status = _statusByDevice[deviceId]?.trim().toLowerCase() ?? '';
    if (status == 'offline') return false;
    final DateTime? receivedAt = _lastTelemetryReceivedByDevice[deviceId];
    return receivedAt != null &&
        MotorControlController.telemetryIsFreshAt(receivedAt);
  }

  /// O estado visual do motor só é confiável enquanto o quadro publica
  /// telemetria. Depois de 10 s sem leitura, o estado passa a desconhecido.
  bool get hasLiveMotorState {
    final String? dev = _benchDeviceId;
    return dev != null && _hasFreshTelemetryFrom(dev);
  }

  /// A partida exige uma tensao positiva e finita, confirmada recentemente.
  /// A parada nao depende dessa leitura.
  bool get hasValidBenchVoltage {
    final String? dev = _benchDeviceId;
    if (dev == null || !_hasFreshTelemetryFrom(dev)) return false;
    final double? voltage = _voltageByDevice[dev];
    return voltage != null && voltage.isFinite && voltage > 0;
  }

  /// Ligado quando algum contator da placa de comandos está ligado. É o que
  /// decide Ligar/Desligar: a "placa selecionada" em modo automático alterna
  /// entre o ESP32-01 e o S3, que não tem contatores.
  bool get isBenchMotorOn => benchRelays?.any((ligado) => ligado) ?? false;

  /// Grandeza do alarme que desligou o motor pelo desarme automático
  /// (`temperature`, `current`...), enquanto o quadro informa; null sem desarme.
  String? get desarmeCampo {
    final String? dev = _benchDeviceId;
    return dev == null ? null : _desarmeByDevice[dev];
  }

  /// Motor girando, para o desenho, o som, a carga e a vibração: inclui o modo
  /// instrumentação, em que nenhum contator da placa fecha. Placas antigas,
  /// sem `motor_running`, seguem pelos contatores.
  bool get isMotorRunning {
    final String? dev = _benchDeviceId;
    if (dev == null || !_hasFreshTelemetryFrom(dev)) return false;
    return _runningByDevice[dev] ?? isBenchMotorOn;
  }

  /// Estado lógico de CNT 1 a CNT 4 informado pela placa de comandos.
  List<bool>? get benchRelays {
    final String? dev = _benchDeviceId;
    return dev == null || !_hasFreshTelemetryFrom(dev)
        ? null
        : _relaysByDevice[dev];
  }
}
