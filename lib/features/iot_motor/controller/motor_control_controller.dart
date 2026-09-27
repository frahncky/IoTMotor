import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/motor_info.dart';
import '../models/acquisition_config.dart';
import '../models/motor_app_settings.dart';
import '../models/board_alarm.dart';
import '../models/device_names.dart';
import '../models/motor_command_type.dart';
import '../models/mqtt_connection_config.dart';
import '../models/telemetry_alert.dart';
import '../models/telemetry_history_entry.dart';
import '../models/telemetry_sample.dart';
import '../services/motor_settings_store.dart';
import '../services/mqtt_settings_validators.dart';
import '../services/mqtt_motor_service.dart';
import '../services/start_types_store.dart';
import '../services/telemetry_alert_store.dart';
import '../services/telemetry_history_store.dart';

part 'motor_control_start_types.dart';
part 'motor_control_alerts.dart';
part 'motor_control_history.dart';
part 'motor_control_boards.dart';
part 'motor_control_devices.dart';

class MotorControlController extends ChangeNotifier {
  MotorControlController({
    MqttMotorService? service,
    bool loadSettings = true,
    MqttConnectionConfig? initialConfig,
    String initialProfileId = '',
  }) : _service = service ?? MqttMotorService() {
    activeProfileId = initialProfileId;
    brokerController = TextEditingController(
      text: initialConfig?.host ?? 'ws://test.mosquitto.org',
    );
    portController = TextEditingController(
      text: (initialConfig?.port ?? 8080).toString(),
    );
    clientIdController = TextEditingController(
      text: initialConfig?.clientId ??
          'motor_app_${DateTime.now().millisecondsSinceEpoch % 100000}',
    );
    deviceIdController = TextEditingController(
      text: initialConfig?.deviceId ?? '',
    );
    usernameController = TextEditingController(
      text: initialConfig?.username ?? '',
    );
    passwordController = TextEditingController(
      text: initialConfig?.password ?? '',
    );
    commandPasswordController = TextEditingController();
    // A senha de comando cifra cada comando enviado as placas; fica guardada
    // no cofre do aparelho, nunca no broker nem no arquivo de configuracoes.
    commandPasswordController.addListener(() {
      _service.seal.senha = commandPasswordController.text;
      unawaited(_guardarSenhaDeComando());
      _notify();
    });
    topicPrefixController = TextEditingController(
      text: initialConfig?.topicPrefix ?? 'iotmotor',
    );
    useTls = initialConfig?.useTls ?? false;
    voltageMinController = TextEditingController(text: '190');
    voltageMaxController = TextEditingController(text: '240');
    currentMaxController = TextEditingController(text: '10');
    vibrationMaxController = TextEditingController(text: '4.5');
    temperatureMaxController = TextEditingController(text: '70');

    // Sem isto, digitar broker, porta, client ID, prefixo, usuário ou limites
    // não agendava a gravação: ao fechar o app, o que foi digitado se perdia.
    for (final TextEditingController campo in <TextEditingController>[
      brokerController,
      portController,
      clientIdController,
      topicPrefixController,
      usernameController,
      voltageMinController,
      voltageMaxController,
      currentMaxController,
      vibrationMaxController,
      temperatureMaxController,
    ]) {
      campo.addListener(_scheduleSettingsPersist);
    }

    _service.onConnected = _handleConnected;
    _service.onDisconnected = _handleDisconnected;
    _service.onAutoReconnect = _handleAutoReconnect;
    _service.onAutoReconnected = _handleAutoReconnected;
    _service.onPayload = _handlePayload;
    _service.onStreamError = _handleStreamError;

    _connectedDevicesTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _notifyConnectionHealthIfChanged();
    });
    ready = _initializeData(loadSettings);
  }

  /// Termina quando o que estava salvo foi lido (e o app pode gravar).
  late final Future<void> ready;

  /// Gravações das configurações em fila: uma nunca começa antes de a
  /// anterior terminar, então o arquivo não fica pela metade nem fora de ordem.
  Future<void> _settingsWrite = Future<void>.value();

  /// Termina quando a última gravação das configurações pedida até agora
  /// chegou ao disco (inclusive a do [dispose]).
  Future<void> get settingsWritten => _settingsWrite;

  /// `true` só quando alguma placa foi gravada exigindo comando cifrado.
  bool get commandPasswordNeeded => _service.seal.algumaExigeSelo;

  /// Lista de alarmes gravada na placa de sensores, como ela publicou.
  List<BoardAlarm> boardAlarms = const <BoardAlarm>[];

  /// Quantos alarmes cabem na placa (ela informa junto da lista).
  int boardAlarmsMax = 8;

  /// Placa que publicou a lista; é para ela que os comandos vão.
  String? alarmsDeviceId;

  /// Ids disparados agora, segundo a última telemetria da placa.
  Set<String> firingAlarmIds = const <String>{};

  /// Quando chegou a última [firingAlarmIds].
  DateTime? _firingAlarmsAt;

  /// Idade máxima de [firingAlarmIds], a mesma `TELEMETRY_STALE_MS` do web.
  static const Duration firingAlarmsStaleAfter = Duration(seconds: 6);

  /// [firingAlarmIds] só com telemetria recente: com a placa fora do ar ou o
  /// broker reconectando, a lista é antiga e não vale como alarme ao vivo.
  Set<String> get liveFiringAlarmIds {
    final DateTime? at = _firingAlarmsAt;
    if (!isConnected || at == null) return const <String>{};
    if (DateTime.now().difference(at) >= firingAlarmsStaleAfter) {
      return const <String>{};
    }
    return firingAlarmIds;
  }

  bool get hasBoardAlarms => alarmsDeviceId != null;

  /// Dados de placa do motor e horímetro/partidas, por quadro de comando: com
  /// mais de um quadro no mesmo prefixo, cada um guarda os seus.
  final Map<String, MotorInfo> _motorInfoByDevice = <String, MotorInfo>{};
  final Map<String, MotorUsage> _motorUsageByDevice = <String, MotorUsage>{};

  /// Quadro de comando em uso: o que aciona os contatores ou, sem telemetria
  /// ainda, o único que publicou dados do motor.
  String? get _motorDeviceId {
    final String? bancada = _benchDeviceId;
    if (bancada != null) return bancada;
    final Set<String> placas = <String>{..._motorInfoByDevice.keys, ..._motorUsageByDevice.keys};
    return placas.length == 1 ? placas.first : null;
  }

  /// Quadro ao qual os dados do motor pertencem.
  String? get motorDeviceId => _motorDeviceId;

  /// Dados de placa do motor do quadro de comando em uso.
  MotorInfo? get motorInfo => _motorDeviceId == null ? null : _motorInfoByDevice[_motorDeviceId];

  /// Horímetro e partidas da última telemetria do quadro de comando em uso.
  MotorUsage? get motorUsage => _motorDeviceId == null ? null : _motorUsageByDevice[_motorDeviceId];

  /// Última telemetria do quadro de comando com a corrente medida.
  double? get benchCurrent => _benchDeviceId == null ? null : _latestByDevice[_benchDeviceId]?.current;

  /// Vibração RMS (mm/s, ISO 10816) da placa de sensores na última telemetria.
  double? get sensorVibration {
    for (final TelemetrySample amostra in _latestByDevice.values) {
      if (amostra.vibration != null) return amostra.vibration;
    }
    return null;
  }

  /// Configuração única de aquisição publicada pelo ESP32-01.
  AcquisitionConfig acquisitionConfig = AcquisitionConfig.defaults;
  final Map<String, _ChartBucketAccumulator> _chartBucketsByDevice =
      <String, _ChartBucketAccumulator>{};

  /// Versão do firmware informada por cada placa.
  final Map<String, String> firmwareByDevice = <String, String>{};

  /// Histórico por hora guardado em cada placa de sensores, por dia (0 a 6).
  final Map<String, Map<int, List<BoardHistoryHour>>> _boardHistoryByDevice =
      <String, Map<int, List<BoardHistoryHour>>>{};

  static const FlutterSecureStorage _cofre = FlutterSecureStorage();
  static const String _chaveSenhaComando = 'iotmotor_cmd_senha';

  Future<void> _guardarSenhaDeComando() async {
    try {
      final String senha = commandPasswordController.text.trim();
      if (senha.isEmpty) {
        await _cofre.delete(key: _chaveSenhaComando);
      } else {
        await _cofre.write(key: _chaveSenhaComando, value: senha);
      }
    } catch (_) {
      // Aparelho sem cofre disponivel: a senha vale so nesta sessao.
    }
  }

  Future<void> _lerSenhaDeComando() async {
    try {
      final String? senha = await _cofre.read(key: _chaveSenhaComando);
      if (senha == null || senha.isEmpty || _disposed) return;
      commandPasswordController.text = senha;
      _service.seal.senha = senha;
    } catch (_) {
      // Sem cofre: segue sem senha guardada.
    }
  }

  Future<void> _initializeData(bool loadSettings) async {
    if (loadSettings) {
      await loadPersistedSettings();
    }
    await _lerSenhaDeComando();
    // Só grava depois de ler o que estava salvo, senão os valores padrão
    // sobrescreveriam o arquivo assim que o app abrisse.
    _settingsRestored = true;
    await Future.wait([
      loadPersistedHistory(),
      loadPersistedAlerts(),
      loadStartTypes(),
    ]);
  }

  // Construtor para injetar config MQTT diretamente
  /// Monta o controlador a partir do perfil MQTT ativo.
  ///
  /// O perfil é o ponto de partida; o que o usuário digitar depois nos campos
  /// de conexão é gravado e, ao reabrir o app, prevalece sobre o perfil — a
  /// menos que o perfil ativo tenha mudado, quando o perfil novo é quem vale.
  factory MotorControlController.withMqttConfig(
    MqttConnectionConfig config, {
    MqttMotorService? service,
    String profileId = '',
  }) {
    return MotorControlController(
      service: service,
      loadSettings: true,
      initialConfig: config,
      initialProfileId: profileId,
    );
  }

  static const int maxHistory = 120;
  static const String _autoDeviceId = 'auto';
  static const String historyFilterAll = 'all';
  static const String historyPeriodToday = 'today';
  static const String historyPeriodLastHour = 'last_hour';
  static const String historyPeriodLast24Hours = 'last_24h';
  static const String historyMetricVoltage = 'voltage';
  static const String historyMetricCurrent = 'current';
  static const String historyMetricPower = 'power';
  static const String historyMetricPowerFactor = 'power_factor';
  static const String historyMetricFrequency = 'frequency';
  static const String historyMetricEnergy = 'energy';
  static const String historyMetricVibration = 'vibration';
  static const String historyMetricTemperature = 'temperature';
  static const String historyStateOn = 'on';
  static const String historyStateOff = 'off';
  static const String historyStateUnknown = 'unknown';
  static const String dashboardTabMeasurements =
      MotorAppSettings.dashboardTabMeasurements;
  static const String dashboardTabElectrical =
      MotorAppSettings.dashboardTabElectrical;
  static const String dashboardTabMechanical =
      MotorAppSettings.dashboardTabMechanical;
  static const Duration telemetryStaleTimeout = Duration(minutes: 5);
  static const Duration _deviceOnlineTimeout = Duration(seconds: 4);
  static const Duration _settingsPersistDelay = Duration(milliseconds: 450);
  static const Duration _historyPersistDelay = Duration(milliseconds: 700);
  static const Duration _alertsPersistDelay = Duration(milliseconds: 350);
  static const List<MotorCommandType> _defaultStartTypes = <MotorCommandType>[
    MotorCommandType.directStart,
    MotorCommandType.starDeltaStart,
  ];
  static const List<String> telemetryRequestFields = <String>[
    'voltage',
    'current',
    'power',
    'pf',
    'frequency',
    'energy',
    'vibration',
    'temperature',
  ];

  final MqttMotorService _service;
  bool _disposed = false;
  bool _startTypesLoaded = false;
  bool _settingsLoaded = false;
  bool _settingsRestored = false;
  /// Perfil MQTT que montou esta tela (vazio fora do app com perfis).
  String activeProfileId = '';
  bool _historyLoaded = false;
  bool _alertsLoaded = false;
  String? _pendingMessage;

  late final TextEditingController brokerController;
  late final TextEditingController portController;
  late final TextEditingController clientIdController;
  late final TextEditingController deviceIdController;
  late final TextEditingController usernameController;
  late final TextEditingController passwordController;

  /// Senha combinada com as placas para cifrar os comandos.
  late final TextEditingController commandPasswordController;
  late final TextEditingController topicPrefixController;
  late final TextEditingController voltageMinController;
  late final TextEditingController voltageMaxController;
  late final TextEditingController currentMaxController;
  late final TextEditingController vibrationMaxController;
  late final TextEditingController temperatureMaxController;

  bool isConnected = false;
  bool isBusy = false;
  bool useTls = false;
  bool telemetryAlertsEnabled = true;
  bool _recebeuDadoAtual = false;
  String dashboardTab = dashboardTabMeasurements;
  String electricalPlotAId = MotorAppSettings.defaultElectricalPlotAId;
  String electricalPlotBId = MotorAppSettings.defaultElectricalPlotBId;
  String mechanicalPlotAId = MotorAppSettings.defaultMechanicalPlotAId;
  String mechanicalPlotBId = MotorAppSettings.defaultMechanicalPlotBId;
  int historyRetentionDays = MotorAppSettings.defaultHistoryRetentionDays;
  int remoteHistoryRetentionDays =
      MotorAppSettings.defaultRemoteHistoryRetentionDays;

  String connectionMessage = 'Desconectado';
  String statusMessage = 'Aguardando conexão e dados.';
  MotorCommandType? lastCommandType;
  DateTime? lastCommandAt;

  final Map<String, List<TelemetrySample>> _historyByDevice =
      <String, List<TelemetrySample>>{};
  final Map<String, TelemetrySample> _latestByDevice =
      <String, TelemetrySample>{};
  final Map<String, String> _statusByDevice = <String, String>{};
  final Map<String, bool> _motorOnByDevice = <String, bool>{};
  // Da telemetria do ESP32 de comandos: sessão exigida pela partida e estado
  // lógico dos quatro contatores (CNT 1 a CNT 4).
  final Map<String, String> _bootByDevice = <String, String>{};
  final Map<String, List<bool>> _relaysByDevice = <String, List<bool>>{};
  /// `motor_running` do quadro: girando pela regra do horímetro, que inclui o
  /// modo instrumentação (motor comandado por fora, sem contator da placa).
  final Map<String, bool> _runningByDevice = <String, bool>{};
  /// Grandeza do alarme que desligou o motor (desarme), até a próxima partida.
  final Map<String, String> _desarmeByDevice = <String, String>{};
  final Map<String, String> _modeByDevice = <String, String>{};
  final Map<String, DateTime> _lastSeenByDevice = <String, DateTime>{};
  final Map<String, DateTime> _lastTelemetryReceivedByDevice =
      <String, DateTime>{};
  final Map<String, _CommandClientPresence> _commandClients =
      <String, _CommandClientPresence>{};
  final Map<String, _FirmwareUpdateProgress> _firmwareUpdatesByDevice =
      <String, _FirmwareUpdateProgress>{};
  static const Duration _commandClientTtl = Duration(seconds: 10);
  static const Duration _firmwareUpdateTimeout = Duration(minutes: 2);
  static const Duration _firmwareUpdatedVisibleFor = Duration(seconds: 30);
  final List<TelemetryAlert> _alertHistory = <TelemetryAlert>[];
  final Set<String> _activeAlertKeys = <String>{};
  Set<String> _lastConnectedDevices = <String>{};
  bool _lastTelemetryStale = false;
  Timer? _connectedDevicesTimer;
  Timer? _settingsPersistTimer;
  Timer? _historyPersistTimer;
  Timer? _alertsPersistTimer;
  String _historyDeviceFilter = historyFilterAll;
  String _historyPeriodFilter = historyFilterAll;
  String _historyMetricFilter = historyFilterAll;
  String _historyStateFilter = historyFilterAll;
  final LinkedHashSet<String> _knownDevices = LinkedHashSet<String>();
  final List<MotorCommandType> _startTypes = <MotorCommandType>[
    ..._defaultStartTypes,
  ];

  TelemetrySample? get latestSample => _recebeuDadoAtual ? _buildCombinedLatestSample() : null;

  bool get recebeuDadoAtual => _recebeuDadoAtual;

  int get historyEntryCount => historyEntries.length;
  int get filteredHistoryEntryCount => filteredHistoryEntries.length;

  String get historyDeviceFilter => _historyDeviceFilter;
  String get historyPeriodFilter => _historyPeriodFilter;
  String get historyMetricFilter => _historyMetricFilter;
  String get historyStateFilter => _historyStateFilter;

  int get knownDeviceCount => _knownDevices.length;

  int get connectedDeviceCount => connectedDeviceIds.length;

  UnmodifiableListView<MotorCommandType> get startTypes =>
      UnmodifiableListView<MotorCommandType>(
        _startTypes.toList(growable: false),
      );

  String get selectedDeviceId {
    final String manualId = deviceIdController.text.trim();
    if (manualId.isNotEmpty && manualId != 'auto') {
      return manualId;
    }

    final String? connectedPrimary = _latestConnectedDeviceId();
    if (connectedPrimary != null) {
      return connectedPrimary;
    }
    if (_knownDevices.isNotEmpty) {
      return _knownDevices.first;
    }
    return '--';
  }

  String get commandRequestTopic {
    final MqttConnectionConfig? active = _service.activeConfig;
    final String topicPrefix =
        active?.topicPrefix ?? topicPrefixController.text.trim();
    if (topicPrefix.isEmpty) {
      return '--';
    }
    return '$topicPrefix/request/command';
  }

  String get commandTopic => commandRequestTopic;

  String get telemetryTopic {
    final MqttConnectionConfig? active = _service.activeConfig;
    final String topicPrefix =
        active?.topicPrefix ?? topicPrefixController.text.trim();
    if (topicPrefix.isEmpty) {
      return '--';
    }
    return '$topicPrefix/+/telemetry';
  }

  String get statusTopic {
    final MqttConnectionConfig? active = _service.activeConfig;
    final String topicPrefix =
        active?.topicPrefix ?? topicPrefixController.text.trim();
    if (topicPrefix.isEmpty) {
      return '--';
    }
    return '$topicPrefix/+/status';
  }

  String get telemetryRequestTopic {
    final MqttConnectionConfig? active = _service.activeConfig;
    final String topicPrefix =
        active?.topicPrefix ?? topicPrefixController.text.trim();
    if (topicPrefix.isEmpty) {
      return '--';
    }
    return '$topicPrefix/request/telemetry';
  }

  String get connectionHost {
    final MqttConnectionConfig? active = _service.activeConfig;
    return active?.host ?? brokerController.text.trim();
  }

  String get connectionPort {
    final MqttConnectionConfig? active = _service.activeConfig;
    final int? activePort = active?.port;
    if (activePort != null) {
      return activePort.toString();
    }
    return portController.text.trim();
  }

  String get connectionClientId {
    final MqttConnectionConfig? active = _service.activeConfig;
    return active?.clientId ?? clientIdController.text.trim();
  }

  String get connectionProtocol => useTls ? 'MQTTS (TLS)' : 'MQTT (TCP)';

  String get lastConnectionType {
    final MotorCommandType? last = lastCommandType;
    if (last == null) {
      return '--';
    }
    return last.label;
  }

  String get lastConnectionTime {
    final DateTime? at = lastCommandAt;
    if (at == null) {
      return '--';
    }
    return formatTimestamp(at);
  }

  bool get isSelectedDeviceMotorOn {
    final String deviceId = selectedDeviceId;
    final bool? knownState = _motorOnByDevice[deviceId];
    if (knownState != null) {
      return knownState;
    }
    return _latestByDevice[deviceId]?.motorOn ?? false;
  }

  String? get selectedDeviceMode {
    final String deviceId = selectedDeviceId;
    final String? mode =
        _modeByDevice[deviceId] ?? _latestByDevice[deviceId]?.mode;
    final String normalized = mode?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  /// Partida que a placa informa estar executando agora (telemetria `profile`).
  String? runningProfileId;

  MotorCommandType? get selectedDeviceConnectionType {
    // Enquanto há partida em andamento, o app segue a partida da placa, mesmo
    // que tenha sido acionada pelo painel ou por outro celular.
    final String? emExecucao = runningProfileId;
    if (emExecucao != null) {
      final MotorCommandType? tipo = startTypeById(emExecucao);
      if (tipo != null) {
        return tipo;
      }
    }
    final String? mode = selectedDeviceMode;
    if (mode == null) {
      return null;
    }
    return _startTypeByMode(mode);
  }

  String? consumePendingMessage() {
    final String? message = _pendingMessage;
    _pendingMessage = null;
    return message;
  }

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
    _latestByDevice.clear(); // Limpa o último valor conhecido de cada dispositivo
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
      final DateTime? ultima = _lastTelemetryReceivedByDevice[dev];
      if (boot == null ||
          ultima == null ||
          // Mesma janela do painel: no broker publico, 8 a 20 s entre
          // telemetrias sao comuns, e 10 s recusava a partida a toa.
          DateTime.now().difference(ultima) > const Duration(seconds: 25)) {
        _pendingMessage =
            'Sem telemetria recente de ${nomeDaPlaca(dev)}: a partida exige a sessão atual da placa.';
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
          statusMessage = 'Comando enviado a ${nomeDaPlaca(dev)}: ${type.label}.';
        } else {
          _pendingMessage = _service.seal.impedimento(dev) ??
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
      _pendingMessage = _service.seal.impedimento(dev) ??
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
    const List<String> fields = telemetryRequestFields;
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

  /// Partidas vindas da placa; enquanto elas não chegam, valem as locais.
  bool startTypesFromBoard = false;
  String? _perfisDeviceId;
  String? _ultimoComandoDePerfil;

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

  String formatTimestamp(DateTime dateTime) {
    final String hour = dateTime.hour.toString().padLeft(2, '0');
    final String minute = dateTime.minute.toString().padLeft(2, '0');
    final String second = dateTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _formatTelemetryAge(Duration age) {
    if (age.inSeconds < 5) {
      return 'agora';
    }
    if (age.inMinutes < 1) {
      return 'há ${age.inSeconds}s';
    }
    if (age.inHours < 1) {
      return 'há ${age.inMinutes}min';
    }
    if (age.inDays < 1) {
      return 'há ${age.inHours}h';
    }
    return 'há ${age.inDays}d';
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
      deviceId: _autoDeviceId,
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

  /// Entrega uma mensagem MQTT ao controlador, como se viesse do broker.
  @visibleForTesting
  void handlePayloadForTest(String topic, String payload) =>
      _handlePayload(topic, payload);

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
            statusMessage = 'Configuração de aquisição sincronizada (revisão ${nova.revision}).';
            _notify();
          }
        }
      } catch (_) {}
      return;
    }
    final String deviceIdDoTopico = partes.length >= 2 ? partes[partes.length - 2] : '';
    // Histórico da placa: prefixo/dispositivo/history/<dia>.
    if (partes.length >= 3 && partes[partes.length - 2] == 'history') {
      final int? dia = int.tryParse(partes.last);
      if (dia != null && dia >= 0 && dia < 7) {
        final String placa = partes[partes.length - 3];
        (_boardHistoryByDevice[placa] ??= <int, List<BoardHistoryHour>>{})[dia] =
            BoardHistoryHour.parseDay(payload);
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

  String _normalizeDashboardTab(String value) {
    final String normalized = value.trim();
    switch (normalized) {
      case dashboardTabElectrical:
      case dashboardTabMechanical:
      case dashboardTabMeasurements:
        return normalized;
      default:
        return dashboardTabMeasurements;
    }
  }

  String _normalizePlotId(String value, String fallback) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      return fallback;
    }
    return normalized;
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
    final Object? boot = dados['boot'];
    if (boot is String && RegExp(r'^[0-9a-f]{16}$').hasMatch(boot)) {
      _bootByDevice[deviceId] = boot;
    }
    final Object? emExecucao = dados['profile'];
    runningProfileId = emExecucao is String && emExecucao.isNotEmpty ? emExecucao : null;
    final MotorUsage? uso = MotorUsage.fromMap(dados);
    if (uso != null) {
      _motorUsageByDevice[deviceId] = uso;
      _conferirManutencao(deviceId);
    }
    final Object? relays = dados['relays'];
    if (relays is List && relays.length == 4 && relays.every((v) => v is bool)) {
      final List<bool> estados = relays.cast<bool>();
      _relaysByDevice[deviceId] = estados;
      _motorOnByDevice[deviceId] = estados.any((ligado) => ligado);
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
    return (dev == null ? null : _runningByDevice[dev]) ?? isBenchMotorOn;
  }

  /// Estado lógico de CNT 1 a CNT 4 informado pela placa de comandos.
  List<bool>? get benchRelays {
    final String? dev = _benchDeviceId;
    return dev == null ? null : _relaysByDevice[dev];
  }

  void _scheduleSettingsPersist() {
    if (_disposed || !_settingsRestored) {
      return;
    }
    _settingsPersistTimer?.cancel();
    _settingsPersistTimer = Timer(_settingsPersistDelay, () {
      unawaited(_persistSettings());
    });
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

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connectedDevicesTimer?.cancel();
    _connectedDevicesTimer = null;
    _settingsPersistTimer?.cancel();
    _settingsPersistTimer = null;
    _historyPersistTimer?.cancel();
    _historyPersistTimer = null;
    _alertsPersistTimer?.cancel();
    _alertsPersistTimer = null;
    unawaited(_persistSettings());
    unawaited(_persistHistory());
    unawaited(_persistAlerts());
    _service.disconnect(silent: true);

    brokerController.dispose();
    portController.dispose();
    clientIdController.dispose();
    deviceIdController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    topicPrefixController.dispose();
    voltageMinController.dispose();
    voltageMaxController.dispose();
    currentMaxController.dispose();
    vibrationMaxController.dispose();
    temperatureMaxController.dispose();
    super.dispose();
  }
}
