import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

const String _defaultHost = 'test.mosquitto.org';
const int _defaultPort = 1883;
const String _defaultTopicPrefix = 'iotmotor';
const String _defaultDeviceId = 'esp32-03';
const int _defaultIntervalMs = 1000;
const Set<String> _supportedFields = <String>{
  'voltage',
  'current',
  'vibration',
  'temperature',
};

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final _SimConfig config = _SimConfig.fromArgs(args);
  final String telemetryTopic =
      '${config.topicPrefix}/${config.deviceId}/telemetry';
  final String statusTopic = '${config.topicPrefix}/${config.deviceId}/status';
  final String directCommandTopic =
      '${config.topicPrefix}/${config.deviceId}/command';
  final String requestCommandTopic = '${config.topicPrefix}/request/command';
  final String requestTelemetryTopic =
      '${config.topicPrefix}/request/telemetry';
  final String capabilitiesTopic =
      '${config.topicPrefix}/${config.deviceId}/capabilities';
  final String clientId =
      config.clientId.isEmpty
          ? 'esp32_sim_${config.deviceId}_${DateTime.now().millisecondsSinceEpoch}'
          : config.clientId;

  final MqttServerClient client = MqttServerClient.withPort(
    config.host,
    clientId,
    config.port,
  );
  client.logging(on: false);
  client.keepAlivePeriod = 30;
  client.autoReconnect = true;
  client.resubscribeOnAutoReconnect = true;
  client.connectionMessage = MqttConnectMessage()
      .withClientIdentifier(clientId)
      .startClean()
      .withWillQos(MqttQos.atMostOnce);

  stdout.writeln(
    'Conectando simulador ${config.deviceId} em ${config.host}:${config.port} '
    '(telemetry: $telemetryTopic, command request: $requestCommandTopic)',
  );

  try {
    await client.connect(
      config.username?.isEmpty ?? true ? null : config.username,
      config.password?.isEmpty ?? true ? null : config.password,
    );
  } catch (error) {
    stderr.writeln('Falha ao conectar no broker MQTT: $error');
    client.disconnect();
    exitCode = 1;
    return;
  }

  if (client.connectionStatus?.state != MqttConnectionState.connected) {
    stderr.writeln(
      'Conexao recusada: ${client.connectionStatus?.returnCode ?? 'desconhecida'}',
    );
    client.disconnect();
    exitCode = 1;
    return;
  }

  final Completer<void> done = Completer<void>();
  final Random random = Random();

  double simPhase = 0.0;
  double simulatedTemp = 29.0;
  bool motorOn = false;
  String motorMode = 'manual_stop';
  int sentCount = 0;

  void publishRaw(
    String topic,
    String payload, {
    MqttQos qos = MqttQos.atMostOnce,
  }) {
    final MqttClientPayloadBuilder builder =
        MqttClientPayloadBuilder()..addString(payload);
    client.publishMessage(topic, qos, builder.payload!);
  }

  void publishStatus(String value, {MqttQos qos = MqttQos.atMostOnce}) {
    publishRaw(statusTopic, value, qos: qos);
  }

  void publishCommandStateTelemetry({required String origin}) {
    final String payload = jsonEncode(<String, dynamic>{
      'device_id': config.deviceId,
      'timestamp': DateTime.now().toIso8601String(),
      'motor_on': motorOn,
      'mode': motorMode,
    });
    publishRaw(telemetryTopic, payload, qos: MqttQos.atLeastOnce);
    sentCount += 1;
    stdout.writeln('[$sentCount][$origin] $telemetryTopic $payload');
  }

  void publishCapabilities() {
    final String payload = jsonEncode(<String, dynamic>{
      'device_id': config.deviceId,
      'fields': _supportedFields.toList(growable: false),
      'accepts_command_request': config.acceptCommandRequests,
      'accepts_direct_command': config.acceptDirectCommands,
      'command_topic': directCommandTopic,
      'request_command_topic': requestCommandTopic,
      'request_telemetry_topic': requestTelemetryTopic,
      'telemetry_topic': telemetryTopic,
      'timestamp': DateTime.now().toIso8601String(),
    });
    publishRaw(capabilitiesTopic, payload, qos: MqttQos.atLeastOnce);
  }

  Set<String> parseRequestedFields(dynamic rawFields) {
    if (rawFields is! List<dynamic>) {
      return <String>{};
    }
    final Set<String> values = <String>{};
    for (final dynamic item in rawFields) {
      final String normalized = item.toString().trim().toLowerCase();
      if (normalized.isEmpty) {
        continue;
      }
      values.add(normalized);
    }
    return values;
  }

  void applyCommand({
    required String command,
    required String mode,
    required String origin,
  }) {
    final String normalizedCommand = command.trim().toLowerCase();
    if (normalizedCommand == 'start') {
      motorOn = true;
      motorMode = mode.trim().isEmpty ? 'direct' : mode.trim();
      publishStatus('motor_started', qos: MqttQos.atLeastOnce);
      publishCommandStateTelemetry(origin: 'command_start');
      stdout.writeln('[cmd][$origin] start ($motorMode)');
      return;
    }

    if (normalizedCommand == 'stop') {
      motorOn = false;
      motorMode = 'manual_stop';
      publishStatus('motor_stopped', qos: MqttQos.atLeastOnce);
      publishCommandStateTelemetry(origin: 'command_stop');
      stdout.writeln('[cmd][$origin] stop');
      return;
    }

    publishStatus('unknown_command');
  }

  Map<String, dynamic>? buildTelemetryPayload({
    required Set<String> requestedFields,
    String? requestId,
  }) {
    simPhase += 0.22;
    if (simPhase >= 2.0 * pi) {
      simPhase -= 2.0 * pi;
    }

    final bool wantsAll = requestedFields.isEmpty;

    final double voltage = _clamp(
      220.0 +
          (sin(simPhase) * 3.2) +
          (sin(simPhase * 0.5) * 1.1) +
          _rand(random, -0.5, 0.5),
      210.0,
      230.0,
    );

    final double current =
        motorOn
            ? _clamp(
              5.2 + (sin(simPhase * 1.6) * 1.3) + _rand(random, -0.35, 0.35),
              3.2,
              8.9,
            )
            : _clamp(0.14 + _rand(random, -0.04, 0.04), 0.02, 0.30);

    final double vibration =
        motorOn
            ? _clamp(
              0.38 +
                  (sin(simPhase * 2.4).abs() * 0.24) +
                  _rand(random, -0.05, 0.05),
              0.12,
              1.2,
            )
            : _clamp(0.04 + _rand(random, -0.02, 0.02), 0.0, 0.12);

    final double targetTemp = motorOn ? 47.0 : 29.0;
    simulatedTemp = _clamp(
      simulatedTemp +
          ((targetTemp - simulatedTemp) * 0.08) +
          _rand(random, -0.08, 0.08),
      24.0,
      70.0,
    );

    final Map<String, dynamic> payload = <String, dynamic>{
      'device_id': config.deviceId,
      'timestamp': DateTime.now().toIso8601String(),
      'motor_on': motorOn,
      'mode': motorMode,
    };

    if (wantsAll || requestedFields.contains('voltage')) {
      payload['voltage'] = double.parse(voltage.toStringAsFixed(2));
    }
    if (wantsAll || requestedFields.contains('current')) {
      payload['current'] = double.parse(current.toStringAsFixed(3));
    }
    if (wantsAll || requestedFields.contains('vibration')) {
      payload['vibration'] = double.parse(vibration.toStringAsFixed(3));
    }
    if (wantsAll || requestedFields.contains('temperature')) {
      payload['temperature'] = double.parse(simulatedTemp.toStringAsFixed(2));
    }

    if (requestId != null && requestId.isNotEmpty) {
      payload['request_id'] = requestId;
    }

    final bool hasMetrics =
        payload.containsKey('voltage') ||
        payload.containsKey('current') ||
        payload.containsKey('vibration') ||
        payload.containsKey('temperature');
    if (!hasMetrics) {
      return null;
    }

    return payload;
  }

  void publishTelemetry({
    Set<String> requestedFields = const <String>{},
    String? requestId,
    String origin = 'periodic',
  }) {
    final Map<String, dynamic>? payloadMap = buildTelemetryPayload(
      requestedFields: requestedFields,
      requestId: requestId,
    );
    if (payloadMap == null) {
      return;
    }

    final String payload = jsonEncode(payloadMap);
    publishRaw(telemetryTopic, payload);

    sentCount += 1;
    stdout.writeln('[$sentCount][$origin] $telemetryTopic $payload');
  }

  void handleTelemetryRequestMessage(String payload) {
    try {
      final dynamic decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final Set<String> requestedFields = parseRequestedFields(
        decoded['fields'],
      );
      final String requestId = decoded['request_id']?.toString().trim() ?? '';

      if (requestedFields.isNotEmpty &&
          requestedFields.intersection(_supportedFields).isEmpty) {
        return;
      }

      publishTelemetry(
        requestedFields: requestedFields,
        requestId: requestId,
        origin: 'request',
      );
    } catch (_) {
      // Ignore malformed request payloads.
    }
  }

  void handleCommandMessage(String payload, {required bool fromRequestTopic}) {
    try {
      final dynamic decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      if (fromRequestTopic && !config.acceptCommandRequests) {
        return;
      }
      if (!fromRequestTopic && !config.acceptDirectCommands) {
        return;
      }

      final String command = decoded['command']?.toString() ?? '';
      final String mode = decoded['mode']?.toString() ?? 'direct';
      applyCommand(
        command: command,
        mode: mode,
        origin: fromRequestTopic ? 'request' : 'direct',
      );
    } catch (_) {
      publishStatus('invalid_command_json');
    }
  }

  final StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? updatesSub =
      client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> packets) {
        for (final MqttReceivedMessage<MqttMessage> packet in packets) {
          final MqttPublishMessage message =
              packet.payload as MqttPublishMessage;
          final String payload = MqttPublishPayload.bytesToStringAsString(
            message.payload.message,
          );

          if (packet.topic == requestTelemetryTopic) {
            handleTelemetryRequestMessage(payload);
            continue;
          }

          if (packet.topic == requestCommandTopic) {
            handleCommandMessage(payload, fromRequestTopic: true);
            continue;
          }

          if (packet.topic == directCommandTopic) {
            handleCommandMessage(payload, fromRequestTopic: false);
          }
        }
      });

  client.subscribe(requestTelemetryTopic, MqttQos.atLeastOnce);
  client.subscribe(requestCommandTopic, MqttQos.atLeastOnce);
  client.subscribe(directCommandTopic, MqttQos.atLeastOnce);

  publishStatus('online', qos: MqttQos.atLeastOnce);
  publishCapabilities();

  Future<void> stopSimulator(String reason) async {
    if (done.isCompleted) {
      return;
    }
    stdout.writeln(reason);
    client.autoReconnect = false;
    client.resubscribeOnAutoReconnect = false;
    publishStatus('offline', qos: MqttQos.atLeastOnce);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await updatesSub?.cancel();
    client.disconnect();
    done.complete();
  }

  final StreamSubscription<ProcessSignal> sigintSub = ProcessSignal.sigint
      .watch()
      .listen((_) {
        unawaited(stopSimulator('Encerrando simulador (Ctrl+C).'));
      });

  StreamSubscription<ProcessSignal>? sigtermSub;
  if (!Platform.isWindows) {
    try {
      sigtermSub = ProcessSignal.sigterm.watch().listen((_) {
        unawaited(stopSimulator('Encerrando simulador (SIGTERM).'));
      });
    } catch (_) {
      sigtermSub = null;
    }
  }

  Timer? timer;
  if (!config.onRequestOnly) {
    timer = Timer.periodic(Duration(milliseconds: config.intervalMs), (_) {
      if (done.isCompleted) {
        return;
      }
      publishTelemetry();
      if (config.count > 0 && sentCount >= config.count) {
        unawaited(stopSimulator('Limite de mensagens atingido.'));
      }
    });

    publishTelemetry();
    if (config.count == 1) {
      await stopSimulator('Limite de mensagens atingido.');
    }
  } else {
    stdout.writeln('Modo on-request ativo: sem envio periodico.');
  }

  await done.future;
  timer?.cancel();
  await sigintSub.cancel();
  await sigtermSub?.cancel();
}

class _SimConfig {
  _SimConfig({
    required this.host,
    required this.port,
    required this.topicPrefix,
    required this.deviceId,
    required this.intervalMs,
    required this.count,
    required this.clientId,
    required this.onRequestOnly,
    required this.acceptCommandRequests,
    required this.acceptDirectCommands,
    this.username,
    this.password,
  });

  factory _SimConfig.fromArgs(List<String> args) {
    final String host = _readArg(args, 'host') ?? _defaultHost;
    final int port = int.tryParse(_readArg(args, 'port') ?? '') ?? _defaultPort;
    final String topicPrefix = _normalizePrefix(
      _readArg(args, 'prefix') ?? _defaultTopicPrefix,
    );
    final String deviceId =
        (_readArg(args, 'device-id') ?? _defaultDeviceId).trim();
    final int intervalMs =
        int.tryParse(_readArg(args, 'interval-ms') ?? '') ?? _defaultIntervalMs;
    final int count = int.tryParse(_readArg(args, 'count') ?? '') ?? 0;
    final String clientId = (_readArg(args, 'client-id') ?? '').trim();
    final String? username = _readArg(args, 'username');
    final String? password = _readArg(args, 'password');
    final bool onRequestOnly = args.contains('--on-request-only');
    final bool acceptCommandRequests = !args.contains('--no-command-request');
    final bool acceptDirectCommands = !args.contains('--no-direct-command');

    return _SimConfig(
      host: host.trim(),
      port: port > 0 ? port : _defaultPort,
      topicPrefix: topicPrefix,
      deviceId: deviceId.isEmpty ? _defaultDeviceId : deviceId,
      intervalMs: intervalMs > 100 ? intervalMs : _defaultIntervalMs,
      count: count < 0 ? 0 : count,
      clientId: clientId,
      username: username,
      password: password,
      onRequestOnly: onRequestOnly,
      acceptCommandRequests: acceptCommandRequests,
      acceptDirectCommands: acceptDirectCommands,
    );
  }

  final String host;
  final int port;
  final String topicPrefix;
  final String deviceId;
  final int intervalMs;
  final int count;
  final String clientId;
  final bool onRequestOnly;
  final bool acceptCommandRequests;
  final bool acceptDirectCommands;
  final String? username;
  final String? password;
}

String? _readArg(List<String> args, String name) {
  final String long = '--$name';
  for (int i = 0; i < args.length; i++) {
    final String arg = args[i];
    if (arg == long && i + 1 < args.length) {
      return args[i + 1];
    }
    final String prefix = '$long=';
    if (arg.startsWith(prefix)) {
      return arg.substring(prefix.length);
    }
  }
  return null;
}

double _rand(Random random, double min, double max) {
  return min + ((max - min) * random.nextDouble());
}

double _clamp(double value, double min, double max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

String _normalizePrefix(String raw) {
  final String normalized = raw.trim().replaceAll('\\', '/');
  final List<String> parts =
      normalized.split('/').where((String part) => part.isNotEmpty).toList();
  return parts.isEmpty ? _defaultTopicPrefix : parts.join('/');
}

void _printUsage() {
  stdout.writeln(
    'Simulador MQTT esp32-03 (voltage + current + vibration + temperature)',
  );
  stdout.writeln('');
  stdout.writeln('Uso:');
  stdout.writeln('  dart run tool/esp32_03_simulator.dart [opcoes]');
  stdout.writeln('');
  stdout.writeln('Opcoes:');
  stdout.writeln(
    '  --host <broker>         Broker MQTT (padrao: $_defaultHost)',
  );
  stdout.writeln(
    '  --port <porta>          Porta MQTT (padrao: $_defaultPort)',
  );
  stdout.writeln(
    '  --prefix <topico>       Prefixo (padrao: $_defaultTopicPrefix)',
  );
  stdout.writeln(
    '  --device-id <id>        Device ID (padrao: $_defaultDeviceId)',
  );
  stdout.writeln(
    '  --interval-ms <ms>      Intervalo de envio (padrao: $_defaultIntervalMs)',
  );
  stdout.writeln(
    '  --count <n>             Envia n mensagens e encerra (0 = infinito)',
  );
  stdout.writeln(
    '  --on-request-only       Nao envia periodico; responde apenas requests',
  );
  stdout.writeln('  --no-command-request    Ignora request/command');
  stdout.writeln('  --no-direct-command     Ignora <prefix>/<device>/command');
  stdout.writeln('  --client-id <id>        Client ID MQTT customizado');
  stdout.writeln('  --username <user>       Usuario MQTT');
  stdout.writeln('  --password <pass>       Senha MQTT');
  stdout.writeln('  --help, -h              Mostra ajuda');
}
