class MqttConnectionConfig {
  const MqttConnectionConfig({
    required this.host,
    required this.port,
    required this.clientId,
    required this.topicPrefix,
    required this.deviceId,
    required this.useTls,
    this.username,
    this.password,
  });

  final String host;
  final int port;
  final String clientId;
  final String topicPrefix;
  final String deviceId;
  final String? username;
  final String? password;
  final bool useTls;

  String commandTopicForDevice(String targetDeviceId) =>
      '$topicPrefix/$targetDeviceId/command';

  String get commandTopic => commandTopicForDevice(deviceId);
  String get commandRequestTopic => '$topicPrefix/request/command';
  String get telemetryTopic => '$topicPrefix/$deviceId/telemetry';
  String get statusTopic => '$topicPrefix/$deviceId/status';
  String get telemetryRequestTopic => '$topicPrefix/request/telemetry';
  String get telemetryWildcardTopic => '$topicPrefix/+/telemetry';
  String get statusWildcardTopic => '$topicPrefix/+/status';

  /// Lista de partidas publicada (retida) pelo ESP32 de comandos, e as
  /// respostas dele: é dela que o app e o painel tiram as mesmas partidas.
  String get profilesWildcardTopic => '$topicPrefix/+/profiles';

  /// Lista de alarmes gravada em cada placa.
  String get alarmsWildcardTopic => '$topicPrefix/+/alarms';

  /// Desafio publicado por cada placa para os comandos cifrados.
  String get authWildcardTopic => '$topicPrefix/+/auth';
  String get commandAckWildcardTopic => '$topicPrefix/+/command_ack';
}
