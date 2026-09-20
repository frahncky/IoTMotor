import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/motor_app_settings.dart';
import '../models/motor_command_type.dart';
import '../models/mqtt_connection_config.dart';
import '../models/telemetry_alert.dart';
import '../models/telemetry_history_entry.dart';
import '../models/telemetry_sample.dart';
import '../services/background_mqtt_service.dart';
import '../services/motor_settings_store.dart';
import '../services/mqtt_settings_validators.dart';
import '../services/mqtt_motor_service.dart';
import '../services/start_types_store.dart';
import '../services/telemetry_alert_store.dart';
import '../services/telemetry_history_store.dart';

class MotorControlController extends ChangeNotifier {
  MotorControlController({MqttMotorService? service, bool loadSettings = true})
    : _service = service ?? MqttMotorService() {
    // ...existing code for controllers...
    brokerController = TextEditingController(text: 'broker.hivemq.com');
    portController = TextEditingController(text: '1883');
    clientIdController = TextEditingController(
      text: 'motor_app_${DateTime.now().millisecondsSinceEpoch % 100000}',
    );
    deviceIdController = TextEditingController(text: '');
    usernameController = TextEditingController();
    passwordController = TextEditingController();
    commandPasswordController = TextEditingController();
    // A senha de comando cifra cada comando enviado as placas; fica guardada
    // no cofre do aparelho, nunca no broker nem no arquivo de configuracoes.
    commandPasswordController.addListener(() {
      _service.seal.senha = commandPasswordController.text;
      unawaited(_guardarSenhaDeComando());
      _notify();
    });
    topicPrefixController = TextEditingController(text: 'iotmotor');
    voltageMinController = TextEditingController(text: '190');
    voltageMaxController = TextEditingController(text: '240');
    currentMaxController = TextEditingController(text: '10');
    vibrationMaxController = TextEditingController(text: '1.5');
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
    _initializeData(loadSettings);
  }

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
    final controller = MotorControlController(
      service: service,
      loadSettings: true,
    );
    controller.activeProfileId = profileId;
    controller.brokerController.text = config.host;
    controller.portController.text = config.port.toString();
    controller.clientIdController.text = config.clientId;
    controller.deviceIdController.text = config.deviceId;
    controller.topicPrefixController.text = config.topicPrefix;
    controller.usernameController.text = config.username ?? '';
    controller.passwordController.text = config.password ?? '';
    controller.useTls = config.useTls;
    // deviceId não é usado diretamente nos campos, mas pode ser adicionado se necessário
    return controller;
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
  final Map<String, String> _modeByDevice = <String, String>{};
  final Map<String, DateTime> _lastSeenByDevice = <String, DateTime>{};
  final Map<String, DateTime> _lastTelemetryReceivedByDevice =
      <String, DateTime>{};
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

  UnmodifiableListView<TelemetrySample> get history =>
      UnmodifiableListView<TelemetrySample>(
        _recebeuDadoAtual ? _buildCombinedHistory() : <TelemetrySample>[]
      );

  UnmodifiableListView<TelemetryHistoryEntry> get historyEntries =>
      UnmodifiableListView<TelemetryHistoryEntry>(
        _buildCombinedHistoryEntries(),
      );

  UnmodifiableListView<TelemetryHistoryEntry> get filteredHistoryEntries =>
      UnmodifiableListView<TelemetryHistoryEntry>(
        _buildFilteredHistoryEntries(),
      );

  int get historyEntryCount => historyEntries.length;
  int get filteredHistoryEntryCount => filteredHistoryEntries.length;

  String get historyDeviceFilter => _historyDeviceFilter;
  String get historyPeriodFilter => _historyPeriodFilter;
  String get historyMetricFilter => _historyMetricFilter;
  String get historyStateFilter => _historyStateFilter;

  bool get hasActiveHistoryFilters =>
      _historyDeviceFilter != historyFilterAll ||
      _historyPeriodFilter != historyFilterAll ||
      _historyMetricFilter != historyFilterAll ||
      _historyStateFilter != historyFilterAll;

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

  String get historyRetentionSummary {
    final int entries = historyEntryCount;
    final String suffix = entries == 1 ? 'leitura' : 'leituras';
    return '$historyRetentionDays dias | $entries $suffix';
  }

  String get remoteHistoryRetentionSummary =>
      '$remoteHistoryRetentionDays dias no ESP32/SD';

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

  UnmodifiableListView<String> get knownDeviceIds =>
      UnmodifiableListView<String>(_knownDevices.toList(growable: false));
  int get knownDeviceCount => _knownDevices.length;

  UnmodifiableListView<String> get connectedDeviceIds {
    final List<String> connected = _knownDevices
        .where(_isDeviceConnected)
        .toList(growable: false);
    return UnmodifiableListView<String>(connected);
  }

  int get connectedDeviceCount => connectedDeviceIds.length;

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
    return DateTime.now().difference(latest) >= telemetryStaleTimeout;
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
    if (age >= telemetryStaleTimeout) {
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

    bool backgroundReady = false;
    try {
      await BackgroundMqttService.instance.startMonitoring(config);
      backgroundReady = true;
    } catch (_) {
      backgroundReady = false;
    }

    statusMessage =
        backgroundReady
            ? 'Conexão ativa. Monitoramento em segundo plano ativo.'
            : 'Conexão ativa. Aguardando dados dos ESP32.';
    _notify();
  }

  Future<void> disconnect() async {
    if (!isConnected && !isBusy) {
      return;
    }
    try {
      await BackgroundMqttService.instance.stopMonitoring();
    } catch (_) {
      // Keep foreground disconnect flow even if background service stop fails.
    }

    await _service.disconnect();
    isBusy = false;
    isConnected = false;
    _lastSeenByDevice.clear();
    _lastTelemetryReceivedByDevice.clear();
    _lastConnectedDevices = <String>{};
    _lastTelemetryStale = false;
    _latestByDevice.clear(); // Limpa o último valor conhecido de cada dispositivo
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
          DateTime.now().difference(ultima) > const Duration(seconds: 10)) {
        _pendingMessage =
            'Sem telemetria recente de $dev: a partida exige a sessão atual da placa.';
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
          statusMessage = 'Comando enviado a $dev: ${type.label}.';
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
    statusMessage = 'Comando enviado a $dev: ${type.label}.';
    _notify();
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

  MotorCommandType? startTypeById(String id) {
    for (final MotorCommandType type in _startTypes) {
      if (type.id == id) {
        return type;
      }
    }
    return null;
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
        clientIdController.text = settings.clientId;
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

  /// Partidas vindas da placa; enquanto elas não chegam, valem as locais.
  bool startTypesFromBoard = false;
  String? _perfisDeviceId;
  String? _ultimoComandoDePerfil;

  /// Lê a lista publicada pelo ESP32 e substitui a lista mostrada no app.
  ///
  /// O formato é o mesmo do painel: cada contator tem o instante em que liga e
  /// o instante em que desliga (0 = fica ligado até parar), em milissegundos.
  void _aplicarPerfisDaPlaca({required String deviceId, required String payload}) {
    final Object? dados;
    try {
      dados = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (dados is! Map<String, dynamic>) return;
    final Object? lista = dados['profiles'];
    if (lista is! List) return;

    final List<MotorCommandType> partidas = <MotorCommandType>[];
    for (final Object? bruto in lista) {
      if (bruto is! Map) continue;
      final String id = '${bruto['id'] ?? ''}'.trim();
      final String nome = '${bruto['name'] ?? ''}'.trim();
      final Object? contatores = bruto['cnt'];
      if (id.isEmpty || nome.isEmpty || contatores is! List || contatores.length != 4) continue;
      final List<ContactorTiming> tempos = <ContactorTiming>[];
      for (final Object? item in contatores) {
        if (item is! Map) break;
        tempos.add(ContactorTiming(
          use: item['use'] == true,
          onMs: (item['on'] as num?)?.round() ?? 0,
          offMs: (item['off'] as num?)?.round() ?? 0,
        ));
      }
      if (tempos.length != 4) continue;
      partidas.add(MotorCommandType.fromBoard(id: id, label: nome, timings: tempos));
    }
    if (partidas.isEmpty) return;

    _perfisDeviceId = deviceId;
    startTypesFromBoard = true;
    _startTypes
      ..clear()
      ..addAll(partidas);
    _notify();
  }

  void _tratarRespostaDeComando(String payload) {
    if (_ultimoComandoDePerfil == null) return;
    final Object? dados;
    try {
      dados = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (dados is! Map<String, dynamic>) return;
    if ('${dados['seq'] ?? ''}' != _ultimoComandoDePerfil) return;
    _ultimoComandoDePerfil = null;
    final String detalhe = '${dados['reason'] ?? dados['action'] ?? ''}';
    _pendingMessage = dados['accepted'] == true
        ? 'Placa confirmou: $detalhe'
        : 'Placa recusou: $detalhe';
    _notify();
  }

  /// Envia a partida para a placa, que grava e republica para todos.
  bool _enviarPerfilParaPlaca(String action, Map<String, dynamic> corpo) {
    final String? dev = _perfisDeviceId ?? _benchDeviceId;
    if (dev == null) {
      _pendingMessage = 'Aguardando a lista de partidas do ESP32 de comandos.';
      _notify();
      return false;
    }
    final String? seq = _service.sendRawCommand(deviceId: dev, action: action, body: corpo);
    if (seq == null) {
      _pendingMessage = 'Conecte-se ao broker antes de editar partidas.';
      _notify();
      return false;
    }
    _ultimoComandoDePerfil = seq;
    return true;
  }

  /// Cria ou atualiza uma partida na placa; ela grava e republica para todos.
  ///
  /// `id` vazio cria uma partida nova. Os tempos são os mesmos do painel:
  /// para cada contator, quando liga e quando desliga (0 = até parar).
  bool saveStartTypeOnBoard({
    required String id,
    required String label,
    required List<ContactorTiming> timings,
  }) {
    final String nome = _normalizeLabel(label);
    if (nome.isEmpty) {
      _pendingMessage = 'Informe o nome da partida.';
      _notify();
      return false;
    }
    if (!timings.any((ContactorTiming t) => t.use)) {
      _pendingMessage = 'Marque pelo menos um contator.';
      _notify();
      return false;
    }
    for (int i = 0; i < timings.length; i++) {
      final ContactorTiming t = timings[i];
      if (!t.use) continue;
      if (t.onMs < 0 || t.offMs < 0 || (t.offMs != 0 && t.offMs <= t.onMs)) {
        _pendingMessage = 'CNT ${i + 1}: desligar depois de ligar (ou 0 para ficar ligado).';
        _notify();
        return false;
      }
    }
    final String identificador = id.isNotEmpty
        ? id
        : 'p${DateTime.now().millisecondsSinceEpoch.toRadixString(36).substring(4)}';
    return _enviarPerfilParaPlaca('profile_save', <String, dynamic>{
      'profile': <String, dynamic>{
        'id': identificador,
        'name': nome,
        'cnt': timings.map((ContactorTiming t) => t.toBoard()).toList(growable: false),
      },
    });
  }

  Future<void> loadStartTypes() async {
    if (_startTypesLoaded) {
      return;
    }
    _startTypesLoaded = true;

    try {
      final List<MotorCommandType> persisted = await loadPersistedStartTypes();
      final List<MotorCommandType> normalized = _normalizePersistedStartTypes(
        persisted,
      );
      if (normalized.isEmpty) {
        return;
      }

      _startTypes
        ..clear()
        ..addAll(normalized);
      _notify();
    } catch (_) {
      // Keep defaults if storage is unavailable or content is invalid.
    }
  }

  /// Perfil (contatores) informado pelo editor de partidas.
  MotorCommandType _comPerfil(
    MotorCommandType base, {
    required bool sequence,
    required int mask,
    required int main,
    required int star,
    required int delta,
    required int seconds,
  }) {
    return base.copyAsStart(
      label: base.label,
      mode: base.mode,
      sequence: sequence,
      mask: mask,
      main: main,
      star: star,
      delta: delta,
      seconds: seconds,
    );
  }

  String? addStartType({
    required String label,
    required String mode,
    bool sequence = false,
    int mask = 1,
    int main = 1,
    int star = 2,
    int delta = 3,
    int seconds = 5,
  }) {
    final String normalizedLabel = _normalizeLabel(label);
    if (normalizedLabel.isEmpty) {
      _pendingMessage = 'Informe o nome da partida.';
      _notify();
      return null;
    }

    final String normalizedMode = _normalizeMode(mode, normalizedLabel);
    if (_containsMode(normalizedMode)) {
      _pendingMessage = 'Já existe uma partida com modo "$normalizedMode".';
      _notify();
      return null;
    }

    final String id =
        'custom_${DateTime.now().millisecondsSinceEpoch}_${_startTypes.length}';
    final MotorCommandType type = _comPerfil(
      MotorCommandType.start(id: id, label: normalizedLabel, mode: normalizedMode),
      sequence: sequence,
      mask: mask,
      main: main,
      star: star,
      delta: delta,
      seconds: seconds,
    );
    if (!type.profileIsValid) {
      _pendingMessage = 'Contatores inválidos para esta partida.';
      _notify();
      return null;
    }
    _startTypes.add(type);
    unawaited(_persistStartTypes());
    _pendingMessage = 'Partida "$normalizedLabel" adicionada.';
    _notify();
    return id;
  }

  bool updateStartType({
    required String id,
    required String label,
    required String mode,
    bool? sequence,
    int? mask,
    int? main,
    int? star,
    int? delta,
    int? seconds,
  }) {
    final int index = _startTypes.indexWhere(
      (MotorCommandType item) => item.id == id,
    );
    if (index == -1) {
      _pendingMessage = 'Partida não encontrada para edição.';
      _notify();
      return false;
    }

    final String normalizedLabel = _normalizeLabel(label);
    if (normalizedLabel.isEmpty) {
      _pendingMessage = 'Informe o nome da partida.';
      _notify();
      return false;
    }

    final String normalizedMode = _normalizeMode(mode, normalizedLabel);
    if (_containsMode(normalizedMode, ignoreId: id)) {
      _pendingMessage = 'Já existe uma partida com modo "$normalizedMode".';
      _notify();
      return false;
    }

    final MotorCommandType atualizado = _startTypes[index].copyAsStart(
      label: normalizedLabel,
      mode: normalizedMode,
      sequence: sequence,
      mask: mask,
      main: main,
      star: star,
      delta: delta,
      seconds: seconds,
    );
    if (!atualizado.profileIsValid) {
      _pendingMessage = 'Contatores inválidos para esta partida.';
      _notify();
      return false;
    }
    _startTypes[index] = atualizado;
    unawaited(_persistStartTypes());
    _pendingMessage = 'Partida "$normalizedLabel" atualizada.';
    _notify();
    return true;
  }

  bool removeStartType(String id) {
    if (_startTypes.length <= 1) {
      _pendingMessage = 'Mantenha pelo menos uma partida configurada.';
      _notify();
      return false;
    }
    // Lista da placa: quem remove é ela, e a nova lista chega por MQTT.
    if (startTypesFromBoard) {
      return _enviarPerfilParaPlaca('profile_remove', <String, dynamic>{'id': id});
    }

    final int index = _startTypes.indexWhere(
      (MotorCommandType item) => item.id == id,
    );
    if (index == -1) {
      _pendingMessage = 'Partida não encontrada para exclusão.';
      _notify();
      return false;
    }

    final String removed = _startTypes[index].label;
    _startTypes.removeAt(index);
    unawaited(_persistStartTypes());
    _pendingMessage = 'Partida "$removed" removida.';
    _notify();
    return true;
  }

  void clearHistory() {
    _historyByDevice.clear();
    _latestByDevice.clear();
    _statusByDevice.clear();
    _motorOnByDevice.clear();
    _bootByDevice.clear();
    _relaysByDevice.clear();
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

  void setTelemetryAlertsEnabled(bool enabled) {
    telemetryAlertsEnabled = enabled;
    if (!enabled) {
      _activeAlertKeys.clear();
    }
    _scheduleSettingsPersist();
    _notify();
  }

  void refreshPreview() {
    _scheduleSettingsPersist();
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
    // Partidas e respostas não dependem da configuração ativa: o dispositivo
    // vem do próprio tópico (prefixo/dispositivo/profiles).
    final List<String> partes = topic.split('/');
    final String deviceIdDoTopico = partes.length >= 2 ? partes[partes.length - 2] : '';
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

    _addSampleToHistory(deviceId: deviceId, sample: sample);

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

  List<TelemetrySample> _buildCombinedHistory() {
    final List<TelemetrySample> merged =
        _historyByDevice.values
            .expand((List<TelemetrySample> entries) => entries)
            .toList();
    merged.sort(
      (TelemetrySample a, TelemetrySample b) =>
          a.timestamp.compareTo(b.timestamp),
    );
    if (merged.length <= maxHistory) {
      return merged;
    }
    return merged.sublist(merged.length - maxHistory);
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
    if (merged.length <= maxHistory) {
      return merged;
    }
    return merged.sublist(merged.length - maxHistory);
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
    if (deviceHistory.length > maxHistory) {
      deviceHistory.removeAt(0);
    }
    _pruneTelemetryHistoryByRetention(persist: false);
    if (persist) {
      _scheduleHistoryPersist();
    }
  }

  bool _matchesHistoryFilters(TelemetryHistoryEntry entry) {
    if (_historyDeviceFilter != historyFilterAll &&
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
    if (_historyPeriodFilter == historyFilterAll) {
      return true;
    }

    final DateTime now = DateTime.now();
    switch (_historyPeriodFilter) {
      case historyPeriodToday:
        return timestamp.year == now.year &&
            timestamp.month == now.month &&
            timestamp.day == now.day;
      case historyPeriodLastHour:
        return now.difference(timestamp) <= const Duration(hours: 1);
      case historyPeriodLast24Hours:
        return now.difference(timestamp) <= const Duration(hours: 24);
      default:
        return true;
    }
  }

  bool _matchesHistoryMetric(TelemetrySample sample) {
    switch (_historyMetricFilter) {
      case historyMetricVoltage:
        return sample.voltage != null;
      case historyMetricCurrent:
        return sample.current != null;
      case historyMetricPower:
        return sample.power != null;
      case historyMetricPowerFactor:
        return sample.powerFactor != null;
      case historyMetricFrequency:
        return sample.frequency != null;
      case historyMetricEnergy:
        return sample.energy != null;
      case historyMetricVibration:
        return sample.vibration != null;
      case historyMetricTemperature:
        return sample.temperature != null;
      default:
        return true;
    }
  }

  bool _matchesHistoryState(TelemetrySample sample) {
    switch (_historyStateFilter) {
      case historyStateOn:
        return sample.motorOn == true;
      case historyStateOff:
        return sample.motorOn == false;
      case historyStateUnknown:
        return sample.motorOn == null;
      default:
        return true;
    }
  }

  String _normalizeHistoryFilter(String value) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      return historyFilterAll;
    }
    return normalized;
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

  int _normalizeHistoryRetentionDays(int value) {
    return value.clamp(1, 3650);
  }

  void _clearHistoryFilters({required bool shouldNotify}) {
    _historyDeviceFilter = historyFilterAll;
    _historyPeriodFilter = historyFilterAll;
    _historyMetricFilter = historyFilterAll;
    _historyStateFilter = historyFilterAll;
    if (shouldNotify) {
      _notify();
    }
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

  MotorCommandType? _startTypeByMode(String mode) {
    final String normalized = mode.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final MotorCommandType type in _startTypes) {
      if (!type.isStop && type.mode == normalized) {
        return type;
      }
    }
    return null;
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
    final Object? relays = dados['relays'];
    if (relays is List && relays.length == 4 && relays.every((v) => v is bool)) {
      final List<bool> estados = relays.cast<bool>();
      _relaysByDevice[deviceId] = estados;
      _motorOnByDevice[deviceId] = estados.any((ligado) => ligado);
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

  /// Estado lógico de CNT 1 a CNT 4 informado pela placa de comandos.
  List<bool>? get benchRelays {
    final String? dev = _benchDeviceId;
    return dev == null ? null : _relaysByDevice[dev];
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
        unit: 'g',
        value: sample.vibration,
        limit: _readThreshold(vibrationMaxController),
        severity: TelemetryAlertSeverity.warning,
        digits: 3,
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
            'ESP $deviceId: tensão ${value.toStringAsFixed(1)} V fora da faixa $range.',
        severity: TelemetryAlertSeverity.warning,
      );
    }

    _activeAlertKeys.remove(alertKey);
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
            'ESP $deviceId: $metricLabel ${value.toStringAsFixed(digits)} $unit acima do limite ${limit.toStringAsFixed(digits)} $unit.',
        severity: severity,
      );
    }

    if (_activeAlertKeys.contains(alertKey) && value <= limit * 0.95) {
      _activeAlertKeys.remove(alertKey);
    }
    return null;
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
        normalized == _autoDeviceId) {
      return;
    }
    _knownDevices.add(normalized);
  }

  void _markDeviceSeen(String deviceId) {
    _lastSeenByDevice[deviceId] = DateTime.now();
  }

  void _notifyConnectionHealthIfChanged() {
    final Set<String> current = connectedDeviceIds.toSet();
    final bool stale = hasStaleTelemetry;
    if (_hasSameDevices(current, _lastConnectedDevices) &&
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
    return DateTime.now().difference(lastSeen) <= _deviceOnlineTimeout;
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

  bool _containsMode(String mode, {String? ignoreId}) {
    return _startTypes.any(
      (MotorCommandType item) => item.mode == mode && item.id != ignoreId,
    );
  }

  List<MotorCommandType> _normalizePersistedStartTypes(
    List<MotorCommandType> persisted,
  ) {
    if (persisted.isEmpty) {
      return const <MotorCommandType>[];
    }

    final Set<String> knownModes = <String>{};
    final List<MotorCommandType> normalized = <MotorCommandType>[];

    for (final MotorCommandType raw in persisted) {
      final String label = _normalizeLabel(raw.label);
      if (label.isEmpty) {
        continue;
      }

      final String mode = _normalizeMode(raw.mode, label);
      if (knownModes.contains(mode)) {
        continue;
      }
      knownModes.add(mode);

      final String id = raw.id.trim();
      final String normalizedId =
          id.isEmpty
              ? 'custom_${DateTime.now().millisecondsSinceEpoch}_${normalized.length}'
              : id;

      normalized.add(
        MotorCommandType.start(
          id: normalizedId,
          label: label,
          mode: mode,
          sequence: raw.sequence,
          mask: raw.mask,
          main: raw.main,
          star: raw.star,
          delta: raw.delta,
          seconds: raw.seconds,
        ),
      );
    }

    if (normalized.isEmpty) {
      return <MotorCommandType>[..._defaultStartTypes];
    }
    return normalized;
  }

  Future<void> _persistStartTypes() async {
    try {
      await savePersistedStartTypes(_startTypes);
    } catch (_) {
      // Keep in-memory flow active even if persistence fails.
    }
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

  Future<void> _persistSettings() async {
    try {
      await savePersistedMotorSettings(_buildSettingsSnapshot());
    } catch (_) {
      // Keep app flow active even if settings persistence fails.
    }
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

  void _scheduleHistoryPersist() {
    if (_disposed) {
      return;
    }
    _historyPersistTimer?.cancel();
    _historyPersistTimer = Timer(_historyPersistDelay, () {
      unawaited(_persistHistory());
    });
  }

  Future<void> _persistHistory() async {
    try {
      await savePersistedTelemetryHistory(_buildCombinedHistoryEntries());
    } catch (_) {
      // Keep in-memory history active even if persistence fails.
    }
  }

  void _scheduleAlertsPersist() {
    if (_disposed) {
      return;
    }
    _alertsPersistTimer?.cancel();
    _alertsPersistTimer = Timer(_alertsPersistDelay, () {
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

  String _normalizeLabel(String raw) {
    final String compact = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= 40) {
      return compact;
    }
    return compact.substring(0, 40);
  }

  String _normalizeMode(String raw, String fallbackLabel) {
    String base = raw.trim();
    if (base.isEmpty) {
      base = fallbackLabel;
    }

    String normalized = base.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    normalized = normalized.replaceAll(RegExp(r'_+'), '_');
    normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');

    if (normalized.isNotEmpty) {
      return normalized;
    }
    return 'start_mode_${_startTypes.length + 1}';
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
