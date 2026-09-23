import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/motor_command_type.dart';
import '../models/mqtt_connection_config.dart';
import 'command_seal.dart';
import 'mqtt_settings_validators.dart';

typedef MqttPayloadCallback = void Function(String topic, String payload);
typedef MqttDisconnectedCallback = void Function({required bool manual});

class MqttConnectResult {
  const MqttConnectResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class MqttMotorService {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>?
  _updatesSubscription;
  MqttConnectionConfig? _activeConfig;

  bool _disconnectRequested = false;
  bool _suppressDisconnectEvent = false;

  MqttPayloadCallback? onPayload;
  VoidCallback? onConnected;
  MqttDisconnectedCallback? onDisconnected;
  VoidCallback? onAutoReconnect;
  VoidCallback? onAutoReconnected;
  ValueChanged<String>? onStreamError;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;
  MqttConnectionConfig? get activeConfig => _activeConfig;

  Future<MqttConnectResult> connect(MqttConnectionConfig config) async {
    await disconnect(silent: true);

    // ws:// e wss:// passam por WebSocket. É o caminho que funciona em rede
    // que bloqueia as portas MQTT: as placas usam ws://...:8080 por isso.
    final bool porWebSocket = MqttSettingsValidators.brokerUsaWebSocket(
      config.host,
    );
    final MqttServerClient client = MqttServerClient.withPort(
      config.host,
      config.clientId,
      config.port,
    );
    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    if (porWebSocket) {
      client.useWebSocket = true;
      client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      client.secure = false;  // wss:// já carrega o TLS no próprio endereço.
    } else {
      client.secure = config.useTls;
    }
    client.onConnected = _handleConnected;
    client.onDisconnected = _handleDisconnected;
    client.onAutoReconnect = _handleAutoReconnect;
    client.onAutoReconnected = _handleAutoReconnected;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(config.clientId)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    _client = client;
    _activeConfig = config;

    try {
      await client.connect(
        config.username?.isEmpty ?? true ? null : config.username,
        config.password?.isEmpty ?? true ? null : config.password,
      );
    } catch (error) {
      client.disconnect();
      return MqttConnectResult(
        success: false,
        message: 'Erro ao conectar: $error',
      );
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      final MqttConnectReturnCode? code = client.connectionStatus?.returnCode;
      client.disconnect();
      return MqttConnectResult(
        success: false,
        message: 'Conexão recusada: $code',
      );
    }

    _updatesSubscription?.cancel();
    _updatesSubscription = client.updates?.listen(
      _handleIncomingMessages,
      onError: (Object error) {
        onStreamError?.call('Erro no stream MQTT: $error');
      },
    );

    _subscribeToDefaultTopics();
    return MqttConnectResult(
      success: true,
      message: 'Conectado em ${config.host}:${config.port}',
    );
  }

  Future<void> disconnect({bool silent = false}) async {
    _disconnectRequested = true;
    _suppressDisconnectEvent = silent;

    await _updatesSubscription?.cancel();
    _updatesSubscription = null;

    final MqttServerClient? client = _client;
    _client = null;
    _activeConfig = null;

    if (client != null) {
      client.disconnect();
      return;
    }

    if (!silent) {
      onDisconnected?.call(manual: true);
    }
  }

  bool sendCommand(MotorCommandType type, {String? deviceId}) {
    final MqttServerClient? client = _client;
    final MqttConnectionConfig? config = _activeConfig;
    if (client == null ||
        config == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return false;
    }

    final String targetDeviceId = _resolveTargetDeviceId(
      config: config,
      requestedDeviceId: deviceId,
    );
    final String commandTopic = config.commandTopicForDevice(targetDeviceId);

    final String payload = jsonEncode(<String, dynamic>{
      'device_id': targetDeviceId,
      'command': type.command,
      'mode': type.mode,
      'origin': 'flutter_app',
      'timestamp': DateTime.now().toIso8601String(),
    });

    final MqttClientPayloadBuilder builder =
        MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(commandTopic, MqttQos.atLeastOnce, builder.payload!);
    return true;
  }

  /// Cifra os comandos quando a placa exige senha (ver command_seal.dart).
  final CommandSeal seal = CommandSeal();

  /// Guarda o desafio publicado por uma placa no topico auth dela.
  void registrarAuth(String topic, String payload) {
    final List<String> partes = topic.split('/');
    if (partes.length < 3 || partes.last != 'auth') return;
    try {
      final Object? dados = jsonDecode(payload);
      if (dados is Map<String, dynamic>) {
        seal.registrarAuth(partes[partes.length - 2], dados);
      }
    } catch (_) {
      // auth ilegivel: a placa republica a cada conexao.
    }
  }

  /// Publica um comando ja montado, selando quando a placa exigir.
  void _publicarComando(
    MqttServerClient client,
    String topic,
    String deviceId,
    Map<String, dynamic> comando,
  ) {
    void enviar(String texto) {
      final MqttClientPayloadBuilder builder =
          MqttClientPayloadBuilder()..addString(texto);
      client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    }

    final String? aberto = seal.empacotarAberto(deviceId, comando);
    if (aberto != null) {
      enviar(aberto);
      return;
    }
    seal.empacotar(deviceId, comando).then(enviar);
  }

  int _ultimaSequencia = 0;

  /// Número de sequência crescente exigido pelo firmware (recusa repetidos).
  String _proximaSequencia() {
    final DateTime agora = DateTime.now();
    final int candidata = agora.microsecondsSinceEpoch;
    _ultimaSequencia =
        candidata > _ultimaSequencia ? candidata : _ultimaSequencia + 1;
    return '$_ultimaSequencia';
  }

  /// Partida e parada da bancada no formato do firmware (v:1).
  ///
  /// Mesmo protocolo da página: `start` exige o `boot` publicado na telemetria
  /// atual da placa e um perfil (direta com máscara ou sequência
  /// estrela-triângulo); `stop` é sempre aceito.
  bool sendBenchCommand({
    required String deviceId,
    required String action,
    String boot = '',
    String mode = 'none',
    int mask = 0,
    int main = 0,
    int star = 0,
    int delta = 0,
    int seconds = 0,
    /// Partida gravada na placa; quando informada, os campos acima são ignorados.
    String profile = '',
  }) {
    final MqttServerClient? client = _client;
    final MqttConnectionConfig? config = _activeConfig;
    if (client == null ||
        config == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return false;
    }
    if (seal.impedimento(deviceId) != null) return false;
    _publicarComando(
      client,
      config.commandTopicForDevice(deviceId),
      deviceId,
      <String, dynamic>{
        'v': 1,
        'device_id': deviceId,
        'seq': _proximaSequencia(),
        'action': action,
        'boot': boot,
        'mode': mode,
        'mask': mask,
        'main': main,
        'star': star,
        'delta': delta,
        'seconds': seconds,
        if (profile.isNotEmpty) 'profile': profile,
      },
    );
    return true;
  }

  /// Publica um comando `v:1` com campos livres e devolve o `seq` enviado.
  ///
  /// Usado pelas partidas (`profile_save`, `profile_remove`, `profile_list`),
  /// que são gravadas na placa para valerem também no painel.
  String? sendRawCommand({
    required String deviceId,
    required String action,
    Map<String, dynamic> body = const <String, dynamic>{},
  }) {
    final MqttServerClient? client = _client;
    final MqttConnectionConfig? config = _activeConfig;
    if (client == null ||
        config == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return null;
    }
    if (seal.impedimento(deviceId) != null) return null;
    final String seq = _proximaSequencia();
    _publicarComando(
      client,
      config.commandTopicForDevice(deviceId),
      deviceId,
      <String, dynamic>{
        'v': 1,
        'device_id': deviceId,
        'seq': seq,
        'action': action,
        ...body,
      },
    );
    return seq;
  }

  /// Comandos de manutenção do ESP32: `wifi_portal` e `update`.
  ///
  /// A senha do Wi-Fi nunca é enviada por aqui: `wifi_portal` só pede que a
  /// placa abra a própria rede de configuração, porque o broker é público.
  bool sendMaintenanceCommand(String action, {String? deviceId}) {
    final MqttServerClient? client = _client;
    final MqttConnectionConfig? config = _activeConfig;
    if (client == null ||
        config == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return false;
    }

    final String targetDeviceId = _resolveTargetDeviceId(
      config: config,
      requestedDeviceId: deviceId,
    );
    if (seal.impedimento(targetDeviceId) != null) return false;
    final DateTime now = DateTime.now();
    _publicarComando(
      client,
      config.commandTopicForDevice(targetDeviceId),
      targetDeviceId,
      <String, dynamic>{
        'v': 1,
        'device_id': targetDeviceId,
        'seq':
            '${now.millisecondsSinceEpoch}${now.microsecond.toString().padLeft(3, '0')}',
        'action': action,
        'boot': '',
        'mode': 'none',
        'mask': 0,
        'main': 0,
        'star': 0,
        'delta': 0,
        'seconds': 0,
      },
    );
    return true;
  }

  String? requestCommand({
    required MotorCommandType type,
    String reason = 'auto_dispatch',
  }) {
    final MqttServerClient? client = _client;
    final MqttConnectionConfig? config = _activeConfig;
    if (client == null ||
        config == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return null;
    }

    final DateTime now = DateTime.now();
    final String requestId =
        'cmd_${now.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch % 1000}';

    final String payload = jsonEncode(<String, dynamic>{
      'type': 'command_request',
      'request_id': requestId,
      'command': type.command,
      'mode': type.mode,
      'reason': reason,
      'origin': 'flutter_app',
      'timestamp': now.toIso8601String(),
    });

    final MqttClientPayloadBuilder builder =
        MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(
      config.commandRequestTopic,
      MqttQos.atLeastOnce,
      builder.payload!,
    );

    return requestId;
  }

  String? requestTelemetry({
    List<String> fields = const <String>[],
    String reason = 'manual_refresh',
  }) {
    final MqttServerClient? client = _client;
    final MqttConnectionConfig? config = _activeConfig;
    if (client == null ||
        config == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return null;
    }

    final DateTime now = DateTime.now();
    final String requestId =
        'req_${now.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch % 1000}';
    final List<String> normalizedFields = _normalizeRequestedFields(fields);

    final String payload = jsonEncode(<String, dynamic>{
      'type': 'telemetry_request',
      'request_id': requestId,
      'fields': normalizedFields,
      'reason': reason,
      'origin': 'flutter_app',
      'timestamp': now.toIso8601String(),
    });

    final MqttClientPayloadBuilder builder =
        MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(
      config.telemetryRequestTopic,
      MqttQos.atLeastOnce,
      builder.payload!,
    );

    return requestId;
  }

  String? configureRemoteStorageRetention({
    required int retentionDays,
    String? deviceId,
    String reason = 'storage_retention_update',
  }) {
    final MqttServerClient? client = _client;
    final MqttConnectionConfig? config = _activeConfig;
    if (client == null ||
        config == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return null;
    }

    final DateTime now = DateTime.now();
    final int normalizedDays = retentionDays.clamp(1, 3650);
    final String requestId =
        'storage_${now.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch % 1000}';
    final String targetDeviceId = deviceId?.trim() ?? '';

    final String payload = jsonEncode(<String, dynamic>{
      'type': 'storage_config',
      'request_id': requestId,
      if (targetDeviceId.isNotEmpty) 'device_id': targetDeviceId,
      'storage': <String, dynamic>{
        'medium': 'sdcard',
        'retention_days': normalizedDays,
      },
      'remote_retention_days': normalizedDays,
      'retention_days': normalizedDays,
      'reason': reason,
      'origin': 'flutter_app',
      'timestamp': now.toIso8601String(),
    });

    final MqttClientPayloadBuilder builder =
        MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(
      config.commandRequestTopic,
      MqttQos.atLeastOnce,
      builder.payload!,
    );

    return requestId;
  }

  void _subscribeToDefaultTopics() {
    final MqttServerClient? client = _client;
    final MqttConnectionConfig? config = _activeConfig;

    if (client == null ||
        config == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }

    client.subscribe(config.telemetryWildcardTopic, MqttQos.atMostOnce);
    client.subscribe(config.statusWildcardTopic, MqttQos.atMostOnce);
    // Partidas e respostas: a lista de partidas mora no ESP32 de comandos.
    client.subscribe(config.profilesWildcardTopic, MqttQos.atLeastOnce);
    client.subscribe(config.commandAckWildcardTopic, MqttQos.atLeastOnce);
    // Lista de alarmes da placa de sensores (retida).
    client.subscribe(config.alarmsWildcardTopic, MqttQos.atLeastOnce);
    // Desafio das placas: sem ele nao ha como cifrar um comando.
    client.subscribe(config.authWildcardTopic, MqttQos.atLeastOnce);
  }

  void _handleIncomingMessages(List<MqttReceivedMessage<MqttMessage>> packets) {
    for (final MqttReceivedMessage<MqttMessage> packet in packets) {
      final MqttPublishMessage message = packet.payload as MqttPublishMessage;
      final String payload = MqttPublishPayload.bytesToStringAsString(
        message.payload.message,
      );
      onPayload?.call(packet.topic, payload);
    }
  }

  void _handleConnected() {
    onConnected?.call();
  }

  void _handleDisconnected() {
    final bool manual = _disconnectRequested;
    final bool suppress = _suppressDisconnectEvent;

    _disconnectRequested = false;
    _suppressDisconnectEvent = false;

    if (!suppress || !manual) {
      onDisconnected?.call(manual: manual);
    }
  }

  void _handleAutoReconnect() {
    onAutoReconnect?.call();
  }

  void _handleAutoReconnected() {
    _subscribeToDefaultTopics();
    onAutoReconnected?.call();
  }

  String _resolveTargetDeviceId({
    required MqttConnectionConfig config,
    required String? requestedDeviceId,
  }) {
    final String candidate = requestedDeviceId?.trim() ?? '';
    if (candidate.isNotEmpty) {
      return candidate;
    }
    return config.deviceId;
  }

  List<String> _normalizeRequestedFields(List<String> fields) {
    final Set<String> normalized = <String>{};
    for (final String raw in fields) {
      final String value = raw.trim().toLowerCase();
      if (value.isEmpty) {
        continue;
      }
      normalized.add(value);
    }
    return normalized.toList(growable: false);
  }
}
