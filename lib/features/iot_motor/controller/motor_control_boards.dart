part of 'motor_control_controller.dart';

/// Configuração guardada nas placas: alarmes, aquisição, dados do motor e manutenção.
extension MotorControlBoards on MotorControlController {
  /// Situação do firmware de uma placa frente ao publicado para OTA; null
  /// enquanto a placa não informou nada.
  ({String texto, bool atualizar})? firmwareOf(String deviceId) {
    if (!firmwareByDevice.containsKey(deviceId)) return null;
    final String instalado = firmwareByDevice[deviceId]!;
    final int indice = instalado.startsWith('s3-') || deviceId == 'esp32-02' ? 1 : 0;
    return firmwareSituation(instalado, firmwarePublicado[indice]);
  }

  MaintenanceStatus? get maintenanceStatus =>
      MaintenanceStatus.of(motorInfo, motorUsage?.runSTotal);

  /// Manutenção vencida entra na lista de alertas uma vez por vencimento, só
  /// para o quadro de comando em uso.
  void _conferirManutencao(String deviceId) {
    if (deviceId != _motorDeviceId) return;
    final MaintenanceStatus? status = maintenanceStatus;
    const String chave = 'manutencao';
    final String alertKey = '$deviceId:$chave';
    if (status == null || !status.vencida) {
      if (_activeAlertKeys.contains(alertKey)) _resolveTelemetryAlert(deviceId: deviceId, metricKey: chave);
      return;
    }
    if (_activeAlertKeys.contains(alertKey)) return;
    _activeAlertKeys.add(alertKey);
    _registerAlert(
      deviceId: deviceId,
      metricKey: chave,
      title: 'Manutenção do motor',
      message: '${status.texto}. Depois do serviço, use "Manutenção feita" no painel.',
      severity: TelemetryAlertSeverity.warning,
    );
  }

  void _aplicarAlarmesDaPlaca({
    required String deviceId,
    required String payload,
  }) {
    if (deviceId.isEmpty) return;
    alarmsDeviceId = deviceId;
    boardAlarms = BoardAlarm.listFromPayload(payload);
    boardAlarmsMax = BoardAlarm.maxFromPayload(payload, fallback: boardAlarmsMax);
    _notify();
  }

  Future<bool> saveAcquisitionConfig(AcquisitionConfig config) async {
    final String? erro = config.validate();
    if (erro != null) {
      statusMessage = erro;
      _notify();
      return false;
    }
    final String dev = _motorDeviceId ?? 'esp32-01';
    final String? seq = _service.sendRawCommand(
      deviceId: dev,
      action: 'acquisition_config_set',
      body: <String, dynamic>{'config': config.toBoard()},
    );
    if (seq == null) {
      statusMessage = _service.seal.impedimento(dev) ??
          'Conecte ao MQTT antes de gravar a configuração.';
      _notify();
      return false;
    }
    statusMessage = 'Enviando configuração de aquisição ao ESP32-01…';
    _notify();
    return true;
  }

  void requestAcquisitionConfig() {
    final String dev = _motorDeviceId ?? 'esp32-01';
    _service.sendRawCommand(deviceId: dev, action: 'acquisition_config_get');
  }

  /// Cria ou edita um alarme na placa. A placa republica a lista ao aceitar.
  Future<bool> saveBoardAlarm(BoardAlarm alarme) async {
    final String? dev = alarmsDeviceId;
    if (dev == null) {
      _pendingMessage = 'A placa de sensores ainda não publicou a lista de alarmes.';
      _notify();
      return false;
    }
    final String? seq = _service.sendRawCommand(
      deviceId: dev,
      action: 'alarm_save',
      body: <String, dynamic>{'alarm': alarme.toBoard()},
    );
    if (seq == null) {
      _pendingMessage = _service.seal.impedimento(dev) ??
          'Conecte-se ao broker antes de enviar comandos.';
      _notify();
      return false;
    }
    statusMessage = 'Gravando o alarme em ${nomeDaPlaca(dev)}…';
    _notify();
    return true;
  }

  /// Tira um alarme da placa.
  Future<bool> removeBoardAlarm(String id) async {
    final String? dev = alarmsDeviceId;
    if (dev == null) return false;
    final String? seq = _service.sendRawCommand(
      deviceId: dev,
      action: 'alarm_remove',
      body: <String, dynamic>{'id': id},
    );
    if (seq == null) {
      _pendingMessage = _service.seal.impedimento(dev) ??
          'Conecte-se ao broker antes de enviar comandos.';
      _notify();
      return false;
    }
    statusMessage = 'Removendo o alarme de ${nomeDaPlaca(dev)}…';
    _notify();
    return true;
  }

  /// Pede a lista de novo, caso a mensagem retida não tenha chegado.
  void requestBoardAlarms() {
    final String? dev = alarmsDeviceId;
    if (dev == null) return;
    _service.sendRawCommand(deviceId: dev, action: 'alarm_list');
  }

  /// Id novo e curto para um alarme, derivado da grandeza (a placa aceita 12).
  String newAlarmId(String field) {
    final String base = field.replaceAll(RegExp('[^a-z]'), '');
    final String raiz = (base.isEmpty ? 'alarme' : base).substring(
      0,
      base.length > 8 ? 8 : (base.isEmpty ? 6 : base.length),
    );
    final Set<String> usados = boardAlarms.map((BoardAlarm a) => a.id).toSet();
    if (!usados.contains(raiz)) return raiz;
    for (int i = 2; i < 99; i++) {
      if (!usados.contains('$raiz$i')) return '$raiz$i';
    }
    return raiz + DateTime.now().millisecondsSinceEpoch.toString().substring(10);
  }

  Future<bool> saveMotorInfo(Map<String, dynamic> motor) async {
    final String? dev = _motorDeviceId;
    if (dev == null) {
      _pendingMessage = 'Aguardando o quadro de comando para gravar os dados do motor.';
      _notify();
      return false;
    }
    final String? seq = _service.sendRawCommand(
      deviceId: dev,
      action: 'motor_info_set',
      body: <String, dynamic>{'motor': motor},
    );
    if (seq == null) {
      _pendingMessage = _service.seal.impedimento(dev) ??
          'Conecte-se ao broker antes de gravar os dados do motor.';
      _notify();
      return false;
    }
    statusMessage = 'Dados do motor enviados para ${nomeDaPlaca(dev)}.';
    _notify();
    return true;
  }

  Future<bool> markMotorMaintenanceDone() async {
    final String? dev = _motorDeviceId;
    if (dev == null) {
      _pendingMessage = 'Aguardando o quadro de comando.';
      _notify();
      return false;
    }
    final String? seq = _service.sendRawCommand(
      deviceId: dev,
      action: 'maintenance_done',
    );
    if (seq == null) {
      _pendingMessage = _service.seal.impedimento(dev) ??
          'Não foi possível registrar a manutenção.';
      _notify();
      return false;
    }
    statusMessage = 'Registro de manutenção enviado para ${nomeDaPlaca(dev)}.';
    _notify();
    return true;
  }

  Future<bool> resetMotorCounters() async {
    final String? dev = _motorDeviceId;
    if (dev == null) {
      _pendingMessage = 'Aguardando o quadro de comando.';
      _notify();
      return false;
    }
    final String? seq = _service.sendRawCommand(
      deviceId: dev,
      action: 'motor_counters_reset',
    );
    if (seq == null) {
      _pendingMessage = _service.seal.impedimento(dev) ??
          'Não foi possível zerar o horímetro e as partidas.';
      _notify();
      return false;
    }
    statusMessage = 'Pedido para zerar horímetro e partidas enviado.';
    _notify();
    return true;
  }

  /// Pede ao ESP32 que abra o portal de Wi-Fi (`wifi_portal`) ou que se
  /// atualize pela internet (`update`). Nenhuma senha trafega no broker.
  Future<void> sendMaintenanceCommand(String action) async {
    final bool enviado = _service.sendMaintenanceCommand(action);
    if (!enviado) {
      _pendingMessage = _service.seal.impedimento(_benchDeviceId ?? '') ??
          'Conecte-se ao broker antes de enviar comandos.';
      _notify();
      return;
    }
    statusMessage =
        action == 'wifi_portal'
            ? 'Pedido enviado: a placa vai abrir a rede IoTMotor- por 3 minutos.'
            : 'Pedido enviado: a placa vai baixar o firmware e reiniciar.';
    _notify();
  }
}
