import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../models/motor_command_type.dart';
import '../models/mqtt_connection_config.dart';
import '../models/telemetry_sample.dart';
import '../services/background_mqtt_service.dart';
import '../services/mqtt_motor_service.dart';
import '../services/start_types_store.dart';

class MotorControlController extends ChangeNotifier {
  MotorControlController({MqttMotorService? service})
    : _service = service ?? MqttMotorService() {
    brokerController = TextEditingController(text: 'broker.hivemq.com');
    portController = TextEditingController(text: '1883');
    clientIdController = TextEditingController(
      text: 'motor_app_${DateTime.now().millisecondsSinceEpoch % 100000}',
    );
    usernameController = TextEditingController();
    passwordController = TextEditingController();
    topicPrefixController = TextEditingController(text: 'iotmotor');

    _service.onConnected = _handleConnected;
    _service.onDisconnected = _handleDisconnected;
    _service.onAutoReconnect = _handleAutoReconnect;
    _service.onAutoReconnected = _handleAutoReconnected;
    _service.onPayload = _handlePayload;
    _service.onStreamError = _handleStreamError;

    _connectedDevicesTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _notifyConnectedDevicesIfChanged();
    });
    unawaited(loadStartTypes());
  }

  static const int maxHistory = 120;
  static const String _autoDeviceId = 'auto';
  static const Duration _deviceOnlineTimeout = Duration(seconds: 4);
  static const List<MotorCommandType> _defaultStartTypes = <MotorCommandType>[
    MotorCommandType.directStart,
    MotorCommandType.starDeltaStart,
  ];
  static const List<String> telemetryRequestFields = <String>[
    'voltage',
    'current',
    'vibration',
    'temperature',
  ];

  final MqttMotorService _service;
  bool _disposed = false;
  bool _startTypesLoaded = false;
  String? _pendingMessage;

  late final TextEditingController brokerController;
  late final TextEditingController portController;
  late final TextEditingController clientIdController;
  late final TextEditingController usernameController;
  late final TextEditingController passwordController;
  late final TextEditingController topicPrefixController;

  bool isConnected = false;
  bool isBusy = false;
  bool useTls = false;

  String connectionMessage = 'Desconectado';
  String statusMessage = 'Aguardando conexao e dados.';
  MotorCommandType? lastCommandType;
  DateTime? lastCommandAt;

  final Map<String, List<TelemetrySample>> _historyByDevice =
      <String, List<TelemetrySample>>{};
  final Map<String, TelemetrySample> _latestByDevice =
      <String, TelemetrySample>{};
  final Map<String, String> _statusByDevice = <String, String>{};
  final Map<String, bool> _motorOnByDevice = <String, bool>{};
  final Map<String, String> _modeByDevice = <String, String>{};
  final Map<String, DateTime> _lastSeenByDevice = <String, DateTime>{};
  Set<String> _lastConnectedDevices = <String>{};
  Timer? _connectedDevicesTimer;
  final LinkedHashSet<String> _knownDevices = LinkedHashSet<String>();
  final List<MotorCommandType> _startTypes = <MotorCommandType>[
    ..._defaultStartTypes,
  ];

  TelemetrySample? get latestSample => _buildCombinedLatestSample();

  UnmodifiableListView<TelemetrySample> get history =>
      UnmodifiableListView<TelemetrySample>(_buildCombinedHistory());

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

  MotorCommandType? get selectedDeviceConnectionType {
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
    statusMessage = 'Iniciando conexao MQTT.';
    _notify();

    final MqttConnectResult result = await _service.connect(config);
    isBusy = false;

    if (!result.success) {
      isConnected = false;
      connectionMessage = 'Falha de conexao';
      statusMessage = result.message;
      _notify();
      return;
    }

    isConnected = true;
    connectionMessage = result.message;

    bool backgroundReady = false;
    try {
      await BackgroundMqttService.instance.startMonitoring(config);
      backgroundReady = true;
    } catch (_) {
      backgroundReady = false;
    }

    statusMessage =
        backgroundReady
            ? 'Conexao ativa. Monitoramento em segundo plano ativo.'
            : 'Conexao ativa. Aguardando dados dos ESP32.';
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
    _lastConnectedDevices = <String>{};
    connectionMessage = 'Desconectado';
    statusMessage = 'Conexao encerrada pelo usuario.';
    _notify();
  }

  Future<void> sendCommand(MotorCommandType type) async {
    final String? requestId = _service.requestCommand(
      type: type,
      reason: 'automatic_dispatch',
    );
    if (requestId == null) {
      _pendingMessage = 'Conecte-se ao broker antes de enviar comandos.';
      _notify();
      return;
    }

    lastCommandType = type;
    lastCommandAt = DateTime.now();
    statusMessage = 'Comando em broadcast ($requestId): ${type.label}.';
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
        'Solicitacao enviada ($requestId) para ${fields.join(', ')}.';
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

  String? addStartType({required String label, required String mode}) {
    final String normalizedLabel = _normalizeLabel(label);
    if (normalizedLabel.isEmpty) {
      _pendingMessage = 'Informe o nome da partida.';
      _notify();
      return null;
    }

    final String normalizedMode = _normalizeMode(mode, normalizedLabel);
    if (_containsMode(normalizedMode)) {
      _pendingMessage = 'Ja existe uma partida com modo "$normalizedMode".';
      _notify();
      return null;
    }

    final String id =
        'custom_${DateTime.now().millisecondsSinceEpoch}_${_startTypes.length}';
    final MotorCommandType type = MotorCommandType.start(
      id: id,
      label: normalizedLabel,
      mode: normalizedMode,
    );
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
  }) {
    final int index = _startTypes.indexWhere(
      (MotorCommandType item) => item.id == id,
    );
    if (index == -1) {
      _pendingMessage = 'Partida nao encontrada para edicao.';
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
      _pendingMessage = 'Ja existe uma partida com modo "$normalizedMode".';
      _notify();
      return false;
    }

    _startTypes[index] = _startTypes[index].copyAsStart(
      label: normalizedLabel,
      mode: normalizedMode,
    );
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

    final int index = _startTypes.indexWhere(
      (MotorCommandType item) => item.id == id,
    );
    if (index == -1) {
      _pendingMessage = 'Partida nao encontrada para exclusao.';
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
    _modeByDevice.clear();
    statusMessage = 'Historico limpo para todos os dispositivos.';
    _notify();
  }

  void setTls(bool enabled) {
    useTls = enabled;
    if (enabled && portController.text.trim() == '1883') {
      portController.text = '8883';
    } else if (!enabled && portController.text.trim() == '8883') {
      portController.text = '1883';
    }
    _notify();
  }

  void refreshPreview() {
    _notify();
  }

  String formatTimestamp(DateTime dateTime) {
    final String hour = dateTime.hour.toString().padLeft(2, '0');
    final String minute = dateTime.minute.toString().padLeft(2, '0');
    final String second = dateTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  MqttConnectionConfig? _buildConfigFromInputs() {
    final String host = brokerController.text.trim();
    final String clientId = clientIdController.text.trim();
    final String topicPrefix = topicPrefixController.text.trim();
    final int? port = int.tryParse(portController.text.trim());

    if (host.isEmpty || clientId.isEmpty || topicPrefix.isEmpty) {
      _pendingMessage = 'Preencha broker, client id e topic prefix.';
      return null;
    }

    if (port == null || port <= 0) {
      _pendingMessage = 'Porta MQTT invalida.';
      return null;
    }

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
    final MqttConnectionConfig? config = _service.activeConfig;
    if (config != null) {
      connectionMessage = 'Conectado em ${config.host}:${config.port}';
    }
    _notify();
  }

  void _handleDisconnected({required bool manual}) {
    isBusy = false;
    isConnected = false;
    _lastSeenByDevice.clear();
    _lastConnectedDevices = <String>{};
    connectionMessage = 'Desconectado';
    statusMessage =
        manual
            ? 'Conexao encerrada pelo usuario.'
            : 'Conexao perdida. Reconexao automatica pode ocorrer.';
    _notify();
  }

  void _handleAutoReconnect() {
    statusMessage = 'Tentando reconectar automaticamente...';
    _notify();
  }

  void _handleAutoReconnected() {
    isConnected = true;
    statusMessage = 'Reconectado. Aguardando atualizacoes dos dispositivos...';
    _notify();
  }

  void _handleStreamError(String message) {
    statusMessage = message;
    _notify();
  }

  void _handlePayload(String topic, String payload) {
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

    _latestByDevice[deviceId] = sample;
    _syncStateFromTelemetry(deviceId: deviceId, sample: sample);

    final List<TelemetrySample> deviceHistory = _historyByDevice.putIfAbsent(
      deviceId,
      () => <TelemetrySample>[],
    );
    deviceHistory.add(sample);
    if (deviceHistory.length > maxHistory) {
      deviceHistory.removeAt(0);
    }

    if (deviceId == selectedDeviceId) {
      statusMessage =
          '${_buildDeviceStateSummary(deviceId)} Ultimo pacote em ${formatTimestamp(sample.timestamp)}';
    }
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

  TelemetrySample? _buildCombinedLatestSample() {
    if (_latestByDevice.isEmpty) {
      return null;
    }

    double? voltage;
    DateTime? voltageAt;
    double? current;
    DateTime? currentAt;
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

  void _notifyConnectedDevicesIfChanged() {
    final Set<String> current = connectedDeviceIds.toSet();
    if (_hasSameDevices(current, _lastConnectedDevices)) {
      return;
    }
    _lastConnectedDevices = current;
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
        MotorCommandType.start(id: normalizedId, label: label, mode: mode),
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
    _service.disconnect(silent: true);

    brokerController.dispose();
    portController.dispose();
    clientIdController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    topicPrefixController.dispose();
    super.dispose();
  }
}
