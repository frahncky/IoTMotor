import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/mqtt_connection_config.dart';

const String _eventConfigure = 'configure_mqtt';
const String _eventStop = 'stop_mqtt';

const int _notificationId = 9101;
const String _notificationTitle = 'IoTMotor';

class BackgroundMqttService {
  BackgroundMqttService._();

  static final BackgroundMqttService instance = BackgroundMqttService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _initialized = false;

  bool get _supportsBackground =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (!_supportsBackground) {
      _initialized = true;
      return;
    }

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _backgroundEntryPoint,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        initialNotificationTitle: _notificationTitle,
        initialNotificationContent: 'Monitoramento MQTT em segundo plano',
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: <AndroidForegroundType>[
          AndroidForegroundType.dataSync,
        ],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _backgroundEntryPoint,
        onBackground: _onIosBackground,
      ),
    );

    _initialized = true;
  }

  Future<void> startMonitoring(MqttConnectionConfig config) async {
    if (!_supportsBackground) {
      return;
    }

    await initialize();

    final bool running = await _service.isRunning();
    if (!running) {
      await _service.startService();
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }

    _service.invoke(_eventConfigure, <String, dynamic>{
      'host': config.host,
      'port': config.port,
      'client_id': config.clientId,
      'topic_prefix': config.topicPrefix,
      'username': config.username ?? '',
      'password': config.password ?? '',
      'use_tls': config.useTls,
    });
  }

  Future<void> stopMonitoring() async {
    if (!_supportsBackground || !_initialized) {
      return;
    }

    final bool running = await _service.isRunning();
    if (!running) {
      return;
    }

    _service.invoke(_eventStop);
  }
}

@pragma('vm:entry-point')
void _backgroundEntryPoint(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();

  final _BackgroundRuntime runtime = _BackgroundRuntime(service);
  runtime.start();
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

class _BackgroundRuntime {
  _BackgroundRuntime(this.service);

  final ServiceInstance service;

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  _BackgroundConfig? _config;

  void start() {
    service.on(_eventConfigure).listen(_handleConfigure);
    service.on(_eventStop).listen((_) {
      unawaited(_handleStop());
    });
  }

  Future<void> _handleConfigure(Map<String, dynamic>? event) async {
    final _BackgroundConfig? parsed = _BackgroundConfig.tryFromMap(event);
    if (parsed == null) {
      return;
    }

    _config = parsed;
    await _disconnectClient();

    final String backgroundClientId =
        parsed.clientId.endsWith('_bg')
            ? parsed.clientId
            : '${parsed.clientId}_bg';

    final MqttServerClient client = MqttServerClient.withPort(
      parsed.host,
      backgroundClientId,
      parsed.port,
    );
    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.secure = parsed.useTls;
    client.onAutoReconnected = _subscribeTopics;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(backgroundClientId)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    try {
      await client.connect(
        parsed.username.isEmpty ? null : parsed.username,
        parsed.password.isEmpty ? null : parsed.password,
      );
    } catch (_) {
      client.disconnect();
      return;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      return;
    }

    _client = client;
    _subscribeTopics();

    _updatesSub = client.updates?.listen((
      List<MqttReceivedMessage<MqttMessage>> packets,
    ) {
      for (final MqttReceivedMessage<MqttMessage> packet in packets) {
        final MqttPublishMessage message = packet.payload as MqttPublishMessage;
        final String payload = MqttPublishPayload.bytesToStringAsString(
          message.payload.message,
        );
        service.invoke('mqtt_background_packet', <String, dynamic>{
          'topic': packet.topic,
          'payload': payload,
        });
      }
    });
  }

  Future<void> _handleStop() async {
    await _disconnectClient();
    service.stopSelf();
  }

  void _subscribeTopics() {
    final MqttServerClient? client = _client;
    final _BackgroundConfig? config = _config;
    if (client == null || config == null) {
      return;
    }

    client.subscribe(config.telemetryWildcardTopic, MqttQos.atMostOnce);
    client.subscribe(config.statusWildcardTopic, MqttQos.atMostOnce);
  }

  Future<void> _disconnectClient() async {
    await _updatesSub?.cancel();
    _updatesSub = null;

    final MqttServerClient? client = _client;
    _client = null;

    if (client != null) {
      client.disconnect();
    }
  }
}

class _BackgroundConfig {
  _BackgroundConfig({
    required this.host,
    required this.port,
    required this.clientId,
    required this.topicPrefix,
    required this.username,
    required this.password,
    required this.useTls,
  });

  static _BackgroundConfig? tryFromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return null;
    }

    final String host = map['host']?.toString().trim() ?? '';
    final int port = int.tryParse(map['port']?.toString() ?? '') ?? 0;
    final String clientId = map['client_id']?.toString().trim() ?? '';
    final String topicPrefix = map['topic_prefix']?.toString().trim() ?? '';

    if (host.isEmpty || port <= 0 || clientId.isEmpty || topicPrefix.isEmpty) {
      return null;
    }

    return _BackgroundConfig(
      host: host,
      port: port,
      clientId: clientId,
      topicPrefix: topicPrefix,
      username: map['username']?.toString() ?? '',
      password: map['password']?.toString() ?? '',
      useTls: map['use_tls'] == true,
    );
  }

  final String host;
  final int port;
  final String clientId;
  final String topicPrefix;
  final String username;
  final String password;
  final bool useTls;

  String get telemetryWildcardTopic => '$topicPrefix/+/telemetry';
  String get statusWildcardTopic => '$topicPrefix/+/status';
}
