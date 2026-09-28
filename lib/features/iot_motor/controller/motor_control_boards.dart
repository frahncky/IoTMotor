part of 'motor_control_controller.dart';

/// Configuração guardada nas placas: alarmes, aquisição, dados do motor e manutenção.
extension MotorControlBoards on MotorControlController {
  /// Situação do firmware de uma placa frente ao publicado para OTA; null
  /// enquanto a placa não informou nada.
  ({String texto, bool atualizar})? firmwareOf(String deviceId) {
    if (!firmwareByDevice.containsKey(deviceId)) return null;
    final String instalado = firmwareByDevice[deviceId]!;
    final int indice =
        instalado.startsWith('s3-') || deviceId == 'esp32-02' ? 1 : 0;
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
      if (_activeAlertKeys.contains(alertKey))
        _resolveTelemetryAlert(deviceId: deviceId, metricKey: chave);
      return;
    }
    if (_activeAlertKeys.contains(alertKey)) return;
    _activeAlertKeys.add(alertKey);
    _registerAlert(
      deviceId: deviceId,
      metricKey: chave,
      title: 'Manutenção do motor',
      message:
          '${status.texto}. Depois do serviço, use "Manutenção feita" no painel.',
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
    boardAlarmsMax = BoardAlarm.maxFromPayload(
      payload,
      fallback: boardAlarmsMax,
    );
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
      statusMessage =
          _service.seal.impedimento(dev) ??
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
      _pendingMessage =
          'A placa de sensores ainda não publicou a lista de alarmes.';
      _notify();
      return false;
    }
    final String? seq = _service.sendRawCommand(
      deviceId: dev,
      action: 'alarm_save',
      body: <String, dynamic>{'alarm': alarme.toBoard()},
    );
    if (seq == null) {
      _pendingMessage =
          _service.seal.impedimento(dev) ??
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
      _pendingMessage =
          _service.seal.impedimento(dev) ??
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
    return raiz +
        DateTime.now().millisecondsSinceEpoch.toString().substring(10);
  }

  Future<bool> saveMotorInfo(Map<String, dynamic> motor) async {
    final String? dev = _motorDeviceId;
    if (dev == null) {
      _pendingMessage =
          'Aguardando o quadro de comando para gravar os dados do motor.';
      _notify();
      return false;
    }
    final String? seq = _service.sendRawCommand(
      deviceId: dev,
      action: 'motor_info_set',
      body: <String, dynamic>{'motor': motor},
    );
    if (seq == null) {
      _pendingMessage =
          _service.seal.impedimento(dev) ??
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
      _pendingMessage =
          _service.seal.impedimento(dev) ??
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
      _pendingMessage =
          _service.seal.impedimento(dev) ??
          'Não foi possível zerar o horímetro e as partidas.';
      _notify();
      return false;
    }
    statusMessage = 'Pedido para zerar horímetro e partidas enviado.';
    _notify();
    return true;
  }

  /// Grava no quadro o comportamento quando Wi-Fi ou MQTT cair.
  /// `-1` mantem as saidas; de 0 a 3600 desliga depois desse intervalo.
  Future<bool> saveLinkGraceSeconds(int seconds) async {
    if (seconds != -1 && (seconds < 0 || seconds > 3600)) {
      _pendingMessage = 'Informe uma espera entre 0 e 3600 segundos.';
      _notify();
      return false;
    }
    final String? dev = _benchDeviceId;
    if (dev == null || !_hasFreshTelemetryFrom(dev)) {
      _pendingMessage = 'Aguardando telemetria recente do quadro de comando.';
      _notify();
      return false;
    }
    final String? seq = _service.sendRawCommand(
      deviceId: dev,
      action: 'link_grace',
      body: <String, dynamic>{'seconds': seconds},
    );
    if (seq == null) {
      _pendingMessage =
          _service.seal.impedimento(dev) ??
          'Nao foi possivel gravar o comportamento da conexao.';
      _notify();
      return false;
    }
    statusMessage =
        seconds < 0
            ? 'Configuracao enviada: manter ligado se a conexao cair.'
            : 'Configuracao enviada: desligar apos $seconds s sem conexao.';
    _notify();
    return true;
  }

  /// Placas no ar agora: as que anunciaram `online` no status retido (a
  /// placa publica `online` ao conectar e o broker troca por `offline`, o
  /// testamento dela, quando cai). Placa só conhecida pelo histórico ou de uma
  /// conexão anterior, sem status atual, não entra.
  List<String> get maintenanceBoards {
    if (!isConnected) return const <String>[];
    final List<String> placas =
        _knownDevices
            .where(
              (String d) =>
                  _statusByDevice[d]?.trim().toLowerCase() == 'online',
            )
            .toList()
          ..sort();
    return placas;
  }

  /// Placas no ar com firmware diferente do publicado: o alvo do botão
  /// "Atualizar firmware". Placa que nunca informou a versão (firmware antigo,
  /// sem o tópico `capabilities`) também entra.
  List<String> get boardsToUpdate => <String>[
    for (final String placa in maintenanceBoards)
      if (!isFirmwareUpdating(placa) && (firmwareOf(placa)?.atualizar ?? true))
        placa,
  ];

  /// Placas que estão em OTA ou acabaram de voltar dela.
  List<String> get firmwareUpdateDeviceIds {
    final List<String> placas = _firmwareUpdatesByDevice.keys.toList()..sort();
    return placas;
  }

  bool isFirmwareUpdating(String deviceId) =>
      _firmwareUpdatesByDevice[deviceId]?.active ?? false;

  bool firmwareUpdateSucceeded(String deviceId) =>
      _firmwareUpdatesByDevice[deviceId]?.phase == 'completed';

  /// Texto curto para a UI enquanto a OTA acontece. O estado não vira
  /// "desconectado" só porque a placa reiniciou como parte da atualização.
  String? firmwareUpdateLabel(String deviceId) {
    final _FirmwareUpdateProgress? p = _firmwareUpdatesByDevice[deviceId];
    if (p == null) return null;
    switch (p.phase) {
      case 'requested':
        return 'Atualizando firmware… aguardando confirmação da placa';
      case 'downloading':
        return 'Atualizando firmware… download e gravação em andamento';
      case 'reconnecting':
        return 'Atualizando firmware… reiniciando e reconectando';
      case 'verifying':
        return 'Atualizando firmware… conectado, confirmando versão';
      case 'completed':
        return 'Atualizado · Conectado · firmware ${p.installedVersion ?? p.expectedVersion}';
      default:
        return null;
    }
  }

  String _firmwareExpectedFor(String deviceId) {
    final String atual = firmwareByDevice[deviceId] ?? '';
    final int indice =
        atual.startsWith('s3-') || deviceId == 'esp32-02' ? 1 : 0;
    return firmwarePublicado[indice];
  }

  void _iniciarAtualizacaoFirmware(String deviceId, String seq) {
    _firmwareUpdatesByDevice[deviceId] = _FirmwareUpdateProgress(
      seq: seq,
      expectedVersion: _firmwareExpectedFor(deviceId),
      startedAt: DateTime.now(),
    );
  }

  /// O primeiro ACK só confirma que o download começou. Uma falha pode chegar
  /// depois com o mesmo seq, por isso o acompanhamento continua até a placa
  /// reiniciar e publicar a versão esperada em capabilities.
  void _tratarRespostaDeAtualizacao(String deviceId, String payload) {
    final _FirmwareUpdateProgress? p = _firmwareUpdatesByDevice[deviceId];
    if (p == null || !p.active) return;
    try {
      final Object? bruto = jsonDecode(payload);
      if (bruto is! Map<String, dynamic> ||
          '${bruto['seq'] ?? ''}' != p.seq ||
          '${bruto['action'] ?? ''}' != 'update') {
        return;
      }
      final String motivo = '${bruto['reason'] ?? ''}'.trim();
      if (bruto['accepted'] == true) {
        p.phase = 'downloading';
        p.changedAt = DateTime.now();
        statusMessage =
            '${nomeDaPlaca(deviceId)}: atualizando firmware… download e gravação em andamento.';
      } else {
        _firmwareUpdatesByDevice.remove(deviceId);
        _pendingMessage =
            'Atualização de ${nomeDaPlaca(deviceId)} falhou'
            '${motivo.isEmpty ? '.' : ': $motivo.'}';
        statusMessage = _pendingMessage!;
      }
      _notify();
    } catch (_) {
      // ACK ilegível: a placa continua sendo acompanhada pelo status/capabilities.
    }
  }

  void _tratarStatusDeAtualizacao(String deviceId, String payload) {
    final _FirmwareUpdateProgress? p = _firmwareUpdatesByDevice[deviceId];
    if (p == null || !p.active) return;
    final String estado = payload.trim().toLowerCase();
    if (estado == 'offline') {
      p.phase = 'reconnecting';
      p.changedAt = DateTime.now();
      statusMessage =
          '${nomeDaPlaca(deviceId)}: atualizando firmware… reiniciando e reconectando.';
      return;
    }
    if (estado == 'online' &&
        (p.phase == 'reconnecting' || p.phase == 'downloading')) {
      p.phase = 'verifying';
      p.changedAt = DateTime.now();
      statusMessage =
          '${nomeDaPlaca(deviceId)}: conectado novamente; confirmando a versão do firmware.';
    }
  }

  void _tratarFirmwarePublicado(String deviceId, String firmware) {
    final _FirmwareUpdateProgress? p = _firmwareUpdatesByDevice[deviceId];
    if (p == null || !p.active || firmware != p.expectedVersion) return;
    p
      ..phase = 'completed'
      ..installedVersion = firmware
      ..changedAt = DateTime.now();
    statusMessage =
        '${nomeDaPlaca(deviceId)}: Atualizado · Conectado · firmware $firmware.';
  }

  bool _pruneFirmwareUpdates() {
    final DateTime agora = DateTime.now();
    bool mudou = false;
    for (final MapEntry<String, _FirmwareUpdateProgress> entry
        in _firmwareUpdatesByDevice.entries.toList()) {
      final _FirmwareUpdateProgress p = entry.value;
      if (p.phase == 'completed') {
        if (agora.difference(p.changedAt) >
            MotorControlController._firmwareUpdatedVisibleFor) {
          _firmwareUpdatesByDevice.remove(entry.key);
          mudou = true;
        }
        continue;
      }
      if (agora.difference(p.startedAt) >
          MotorControlController._firmwareUpdateTimeout) {
        _firmwareUpdatesByDevice.remove(entry.key);
        _pendingMessage =
            'Atualização de ${nomeDaPlaca(entry.key)} não foi confirmada. '
            'Verifique a conexão e a versão do firmware.';
        statusMessage = _pendingMessage!;
        mudou = true;
      }
    }
    return mudou;
  }

  /// Pede a cada placa de [deviceIds], no tópico dela, que abra o portal de
  /// Wi-Fi (`wifi_portal`) ou que se atualize pela internet (`update`).
  /// Nenhuma senha trafega no broker.
  Future<void> sendMaintenanceCommand(
    String action,
    List<String> deviceIds,
  ) async {
    // A lista veio de antes do diálogo de confirmação: confere de novo, porque
    // a placa pode ter caído ou terminado de atualizar enquanto ele estava aberto.
    final List<String> validas =
        action == 'update' ? boardsToUpdate : maintenanceBoards;
    final List<String> alvos = <String>[
      for (final String placa in deviceIds)
        if (validas.contains(placa)) placa,
    ];
    if (alvos.isEmpty) {
      _pendingMessage =
          action == 'update'
              ? 'Nenhuma placa no ar precisa de atualização agora.'
              : 'Nenhuma placa no ar para receber o pedido.';
      _notify();
      return;
    }
    final List<String> enviados = <String>[];
    final List<String> falhas = <String>[
      for (final String placa in deviceIds)
        if (!alvos.contains(placa))
          '${nomeDaPlaca(placa)}: ${action == 'update' && maintenanceBoards.contains(placa) ? 'já está em dia' : 'saiu do ar'}',
    ];
    for (final String placa in alvos) {
      final String? seq = _service.sendMaintenanceCommand(
        action,
        deviceId: placa,
      );
      if (seq != null) {
        enviados.add(nomeDaPlaca(placa));
        if (action == 'update') _iniciarAtualizacaoFirmware(placa, seq);
      } else {
        falhas.add(
          '${nomeDaPlaca(placa)}: '
          '${_service.seal.impedimento(placa) ?? 'sem conexão com o broker'}',
        );
      }
    }
    if (enviados.isNotEmpty) {
      final String quem = enviados.join(' e ');
      statusMessage =
          action == 'wifi_portal'
              ? 'Pedido enviado: $quem vai abrir a rede IoTMotor- por 3 minutos.'
              : 'Pedido enviado para $quem: baixar o firmware e reiniciar.';
    }
    if (falhas.isNotEmpty)
      _pendingMessage = 'Pedido não enviado. ${falhas.join('; ')}.';
    _notify();
  }
}

class _FirmwareUpdateProgress {
  _FirmwareUpdateProgress({
    required this.seq,
    required this.expectedVersion,
    required this.startedAt,
  }) : changedAt = startedAt;

  final String seq;
  final String expectedVersion;
  final DateTime startedAt;
  DateTime changedAt;
  String phase = 'requested';
  String? installedVersion;

  bool get active => phase != 'completed';
}
