part of 'motor_control_controller.dart';

/// Conexão com o broker e envio de comandos e pedidos às placas.
extension MotorControlConnection on MotorControlController {
  Future<void> connect() async {
    if (isBusy) {
      return;
    }

    final MqttConnectionConfig? config = _buildConfigFromInputs();
    if (config == null) {
      _notify();
      return;
    }

    isBusy = true;
    connectionMessage = 'Conectando em ${config.host}:${config.port}...';
    statusMessage = 'Iniciando conexão MQTT.';
    _notify();

    final MqttConnectResult result = await _service.connect(config);
    isBusy = false;

    if (!result.success) {
      isConnected = false;
      connectionMessage = 'Falha de conexão';
      statusMessage = result.message;
      _notify();
      return;
    }

    isConnected = true;
    connectionMessage = result.message;
    // Conexão bem-sucedida: grava estes dados sem esperar o próximo ajuste.
    unawaited(_persistSettings());

    statusMessage = 'Conexão ativa. Aguardando dados dos ESP32.';
    _notify();
  }

  Future<void> disconnect() async {
    if (!isConnected && !isBusy) {
      return;
    }

    await _service.disconnect();
    isBusy = false;
    isConnected = false;
    _lastSeenByDevice.clear();
    _lastTelemetryReceivedByDevice.clear();
    _commandClients.clear();
    _firmwareUpdatesByDevice.clear();
    _lastConnectedDevices = <String>{};
    _lastTelemetryStale = false;
    _latestByDevice
        .clear(); // Limpa o último valor conhecido de cada dispositivo
    // Uso, dados do motor, versões e histórico voltam (retidos) na próxima conexão.
    _motorUsageByDevice.clear();
    _motorInfoByDevice.clear();
    firmwareByDevice.clear();
    _boardHistoryByDevice.clear();
    _recebeuDadoAtual = false; // Garante que a UI não mostre valores antigos
    connectionMessage = 'Desconectado';
    statusMessage = 'Conexão encerrada pelo usuário.';
    _notify();
  }

  void setDeviceId(String id) {
    deviceIdController.text = id;
    _scheduleSettingsPersist();
    _notify();
  }

  /// Liga ou desliga os contatores no formato do firmware (v:1), o mesmo da
  /// página. A partida usa os mesmos perfis padrão da página: direta liga o
  /// CNT 1; estrela-triângulo usa principal CNT 1, estrela CNT 2, triângulo
  /// CNT 3 e 5 s em estrela.
  Future<void> sendCommand(MotorCommandType type) async {
    final String? dev = _benchDeviceId;
    if (dev == null) {
      _pendingMessage =
          'Aguardando telemetria do ESP32 de comandos para saber os contatores.';
      _notify();
      return;
    }

    final bool enviado;
    if (type.isStop) {
      enviado = _service.sendBenchCommand(deviceId: dev, action: 'stop');
    } else {
      final String? boot = _bootByDevice[dev];
      if (boot == null || !_hasFreshTelemetryFrom(dev)) {
        _pendingMessage =
            'Sem telemetria recente de ${nomeDaPlaca(dev)}: a partida exige a sessão atual da placa.';
        _notify();
        return;
      }
      if (!hasValidBenchVoltage) {
        _pendingMessage =
            'Partida bloqueada: aguardando uma leitura valida de tensao.';
        _notify();
        return;
      }
      if (_relaysByDevice[dev]?.any((ligado) => ligado) ?? false) {
        _pendingMessage = 'Há contatores ligados; desligue antes de iniciar.';
        _notify();
        return;
      }
      // Partida da lista da placa: manda o id, e não os tempos. Assim a placa
      // informa na telemetria qual partida está rodando, e o painel segue.
      if (type.timings != null) {
        enviado = _service.sendBenchCommand(
          deviceId: dev,
          action: 'start',
          boot: boot,
          profile: type.id,
        );
        if (enviado) {
          lastCommandType = type;
          lastCommandAt = DateTime.now();
          statusMessage =
              'Comando enviado a ${nomeDaPlaca(dev)}: ${type.label}.';
        } else {
          _pendingMessage =
              _service.seal.impedimento(dev) ??
              'Conecte-se ao broker antes de enviar comandos.';
        }
        _notify();
        return;
      }
      if (!type.profileIsValid) {
        _pendingMessage = 'Revise os contatores da partida "${type.label}".';
        _notify();
        return;
      }
      // Partida antiga, só do app: vai no formato anterior (mode/máscara).
      enviado =
          type.sequence
              ? _service.sendBenchCommand(
                deviceId: dev,
                action: 'start',
                boot: boot,
                mode: 'sequence',
                main: type.main,
                star: type.star,
                delta: type.delta,
                seconds: type.seconds,
              )
              : _service.sendBenchCommand(
                deviceId: dev,
                action: 'start',
                boot: boot,
                mode: 'direct',
                mask: type.mask,
              );
    }

    if (!enviado) {
      _pendingMessage =
          _service.seal.impedimento(dev) ??
          'Conecte-se ao broker antes de enviar comandos.';
      _notify();
      return;
    }
    lastCommandType = type;
    lastCommandAt = DateTime.now();
    statusMessage = 'Comando enviado a ${nomeDaPlaca(dev)}: ${type.label}.';
    _notify();
  }

  Future<void> requestTelemetrySnapshot() async {
    const List<String> fields = MotorControlController.telemetryRequestFields;
    final String? requestId = _service.requestTelemetry(
      fields: fields,
      reason: 'dashboard_refresh',
    );

    if (requestId == null) {
      _pendingMessage =
          'Conecte-se ao broker antes de solicitar telemetria dos ESPs.';
      _notify();
      return;
    }

    statusMessage =
        'Solicitação enviada ($requestId) para ${fields.join(', ')}.';
    _notify();
  }

  Future<void> applyRemoteHistoryRetention() async {
    final String? requestId = _service.configureRemoteStorageRetention(
      retentionDays: remoteHistoryRetentionDays,
      reason: 'settings_storage_tab',
    );
    if (requestId == null) {
      _pendingMessage =
          'Conecte-se ao broker antes de aplicar a retenção remota no ESP32.';
      _notify();
      return;
    }

    statusMessage =
        'Retenção remota enviada ($requestId): $remoteHistoryRetentionDays dias no ESP32/SD.';
    _pendingMessage =
        'Retenção remota enviada para o ESP32: $remoteHistoryRetentionDays dias.';
    _notify();
  }

  /// Conexão que os alertas no celular usam: a ativa, ou a dos campos.
  MqttConnectionConfig? configuracaoParaAlertas() =>
      _service.activeConfig ?? _buildConfigFromInputs();

  /// Conexão ativa agora (null desconectado).
  MqttConnectionConfig? get activeConnectionConfig => _service.activeConfig;

  MqttConnectionConfig? _buildConfigFromInputs() {
    final String host = brokerController.text.trim();
    final String clientId = clientIdController.text.trim();
    final String topicPrefix = topicPrefixController.text.trim();

    final String? validationError = MqttSettingsValidators.firstConnectionError(
      broker: host,
      port: portController.text,
      clientId: clientId,
      topicPrefix: topicPrefix,
    );
    if (validationError != null) {
      _pendingMessage = validationError;
      return null;
    }

    final int port = int.parse(portController.text.trim());

    final String username = usernameController.text.trim();
    final String password = passwordController.text;

    return MqttConnectionConfig(
      host: host,
      port: port,
      clientId: clientId,
      topicPrefix: topicPrefix,
      deviceId: MotorControlController._autoDeviceId,
      username: username.isEmpty ? null : username,
      password: password.isEmpty ? null : password,
      useTls: useTls,
    );
  }

  void _handleConnected() {
    isConnected = true;
    isBusy = false;
    _recebeuDadoAtual = false;
    // Uma conexão nova pode apontar para outro broker/prefixo.
    _commandClients.clear();
    final MqttConnectionConfig? config = _service.activeConfig;
    if (config != null) {
      connectionMessage = 'Conectado em ${config.host}:${config.port}';
    }
    _notify();
  }

  void _handleDisconnected({required bool manual}) {
    isBusy = false;
    isConnected = false;
    _recebeuDadoAtual = false;
    _lastSeenByDevice.clear();
    _lastTelemetryReceivedByDevice.clear();
    _commandClients.clear();
    if (manual) _firmwareUpdatesByDevice.clear();
    _lastConnectedDevices = <String>{};
    _lastTelemetryStale = false;
    connectionMessage = 'Desconectado';
    statusMessage =
        manual
            ? 'Conexão encerrada pelo usuário.'
            : 'Conexão perdida. Reconexão automática pode ocorrer.';
    _notify();
  }

  void _handleAutoReconnect() {
    statusMessage = 'Tentando reconectar automaticamente...';
    _notify();
  }

  void _handleAutoReconnected() {
    isConnected = true;
    _recebeuDadoAtual = false;
    statusMessage = 'Reconectado. Aguardando atualizacoes dos dispositivos...';
    _notify();
  }

  void _handleStreamError(String message) {
    statusMessage = message;
    _notify();
  }
}
