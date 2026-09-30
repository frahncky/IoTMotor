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
import '../services/firmware_publicado_service.dart';
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
part 'motor_control_connection.dart';
part 'motor_control_settings.dart';
part 'motor_control_telemetry.dart';

class MotorControlController extends ChangeNotifier {
  MotorControlController({
    MqttMotorService? service,
    FirmwarePublicadoService? firmwarePublicadoService,
    bool loadSettings = true,
    MqttConnectionConfig? initialConfig,
    String initialProfileId = '',
  }) : _service = service ?? MqttMotorService(),
       _firmwarePublicadoService =
           firmwarePublicadoService ?? FirmwarePublicadoService() {
    activeProfileId = initialProfileId;
    brokerController = TextEditingController(
      text: initialConfig?.host ?? 'ws://test.mosquitto.org',
    );
    portController = TextEditingController(
      text: (initialConfig?.port ?? 8080).toString(),
    );
    clientIdController = TextEditingController(
      text:
          initialConfig?.clientId ??
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
    final Set<String> placas = <String>{
      ..._motorInfoByDevice.keys,
      ..._motorUsageByDevice.keys,
    };
    return placas.length == 1 ? placas.first : null;
  }

  /// Quadro ao qual os dados do motor pertencem.
  String? get motorDeviceId => _motorDeviceId;

  /// Dados de placa do motor do quadro de comando em uso.
  MotorInfo? get motorInfo =>
      _motorDeviceId == null ? null : _motorInfoByDevice[_motorDeviceId];

  /// Horímetro e partidas da última telemetria do quadro de comando em uso.
  MotorUsage? get motorUsage =>
      _motorDeviceId == null ? null : _motorUsageByDevice[_motorDeviceId];

  /// Última telemetria do quadro de comando com a corrente medida.
  double? get benchCurrent =>
      _benchDeviceId == null ? null : _latestByDevice[_benchDeviceId]?.current;

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
  static const Duration telemetryStaleTimeout = Duration(seconds: 10);
  static const Duration _deviceOnlineTimeout = telemetryStaleTimeout;

  @visibleForTesting
  static bool telemetryIsFreshAt(DateTime receivedAt, {DateTime? now}) =>
      (now ?? DateTime.now()).difference(receivedAt) < telemetryStaleTimeout;
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
  final FirmwarePublicadoService _firmwarePublicadoService;

  /// Versão publicada para OTA [quadro, sensores]: a do firmware-latest.json,
  /// lida ao conectar; até lá (ou sem rede), a reserva escrita no app.
  List<String> publishedFirmware = firmwarePublicado;
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
  final Map<String, double> _voltageByDevice = <String, double>{};

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

  TelemetrySample? get latestSample =>
      _recebeuDadoAtual ? _buildCombinedLatestSample() : null;

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
    if (!_hasFreshTelemetryFrom(deviceId)) {
      return false;
    }
    final bool? knownState = _motorOnByDevice[deviceId];
    if (knownState != null) {
      return knownState;
    }
    return _latestByDevice[deviceId]?.motorOn ?? false;
  }

  String? get selectedDeviceMode {
    final String deviceId = selectedDeviceId;
    if (!_hasFreshTelemetryFrom(deviceId)) {
      return null;
    }
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

  /// Segundos que o quadro mantem as saidas ligadas sem Wi-Fi/MQTT.
  /// `-1` mantem ligado, respeitando o limite do ensaio e as protecoes.
  int? linkGraceSeconds;

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

  /// Partidas vindas da placa; enquanto elas não chegam, valem as locais.
  bool startTypesFromBoard = false;
  String? _perfisDeviceId;
  String? _ultimoComandoDePerfil;

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

  /// Entrega uma mensagem MQTT ao controlador, como se viesse do broker.
  @visibleForTesting
  void handlePayloadForTest(String topic, String payload) =>
      _handlePayload(topic, payload);

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
