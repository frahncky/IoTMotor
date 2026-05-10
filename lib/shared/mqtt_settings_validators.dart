class MqttSettingsValidators {
  static bool isValidHost(String host) => host.isNotEmpty && host.contains('.');
  static bool isValidPort(int port) => port > 0 && port < 65536;
  static bool isValidTopic(String topic) => topic.isNotEmpty;
}
