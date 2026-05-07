class MqttSettingsValidators {
  static final RegExp _brokerPattern = RegExp(r'^[a-zA-Z0-9.-]+$');

  static String? validateBroker(String? value) {
    final String broker = value?.trim() ?? '';
    if (broker.isEmpty) {
      return 'Informe o broker MQTT.';
    }
    if (broker.startsWith('http://') || broker.startsWith('https://')) {
      return 'Informe apenas host/IP do broker, sem http:// ou https://.';
    }
    if (broker.contains('/') || broker.contains(' ')) {
      return 'Broker inválido. Use apenas host ou IP.';
    }
    if (!_brokerPattern.hasMatch(broker)) {
      return 'Broker inválido. Use letras, números, ponto e hífen.';
    }
    return null;
  }

  static String? validateClientId(String? value) {
    final String clientId = value?.trim() ?? '';
    if (clientId.isEmpty) {
      return 'Informe o Client ID.';
    }
    if (clientId.contains(' ')) {
      return 'Client ID não pode conter espaços.';
    }
    if (clientId.length > 50) {
      return 'Client ID muito longo (máximo de 50 caracteres).';
    }
    return null;
  }

  static String? validatePort(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Informe a porta MQTT.';
    }
    final int? parsed = int.tryParse(text);
    if (parsed == null) {
      return 'Porta inválida. Use apenas números.';
    }
    if (parsed < 1 || parsed > 65535) {
      return 'A porta deve estar entre 1 e 65535.';
    }
    return null;
  }

  static String? validateTopicPrefix(String? value) {
    final String topic = value?.trim() ?? '';
    if (topic.isEmpty) {
      return 'Informe o topic prefix.';
    }
    if (topic.contains(' ')) {
      return 'O tópico não pode conter espaços.';
    }
    if (topic.startsWith('/') || topic.endsWith('/')) {
      return 'Evite / no início ou no fim do tópico.';
    }
    if (topic.contains('//')) {
      return 'O tópico contém níveis vazios (//).';
    }
    if (topic.contains('#') || topic.contains('+')) {
      return 'Use um prefixo específico sem curingas (#/+).';
    }
    return null;
  }

  static String? validateDecimal(
    String? value, {
    required String fieldLabel,
    double min = 0,
    double? max,
    bool allowZero = true,
  }) {
    final String text = value?.trim().replaceAll(',', '.') ?? '';
    if (text.isEmpty) {
      return 'Informe $fieldLabel.';
    }

    final double? parsed = double.tryParse(text);
    if (parsed == null) {
      return 'Valor inválido. Use apenas números.';
    }
    if (!allowZero && parsed == 0) {
      return 'O valor deve ser maior que zero.';
    }
    if (parsed < min) {
      return 'O valor mínimo permitido é $min.';
    }
    if (max != null && parsed > max) {
      return 'O valor máximo permitido é $max.';
    }
    return null;
  }

  static String? firstConnectionError({
    required String broker,
    required String port,
    required String clientId,
    required String topicPrefix,
  }) {
    return validateBroker(broker) ??
        validatePort(port) ??
        validateClientId(clientId) ??
        validateTopicPrefix(topicPrefix);
  }
}
