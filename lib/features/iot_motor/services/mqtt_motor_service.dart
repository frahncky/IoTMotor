import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/motor_command_type.dart';
import '../models/mqtt_connection_config.dart';

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

    final MqttServerClient client = MqttServerClient.withPort(
      config.host,
      config.clientId,
      config.port,
    );
    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.secure = config.useTls;
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
    final DateTime now = DateTime.now();
    final String payload = jsonEncode(<String, dynamic>{
      'v': 1,
      'device_id': targetDeviceId,
      'seq': '${now.millisecondsSinceEpoch}${now.microsecond.toString().padLeft(3, '0')}',
      'action': action,
      'boot': '',
      'mode': 'none',
      'mask': 0,
      'main': 0,
      'star': 0,
      'delta': 0,
      'seconds': 0,
    });

    final MqttClientPayloadBuilder builder =
        MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(
      config.commandTopicForDevice(targetDeviceId),
      MqttQos.atLeastOnce,
      builder.payload!,
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
