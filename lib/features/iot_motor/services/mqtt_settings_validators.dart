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
      return 'Broker invalido. Use apenas host ou IP.';
    }
    if (!_brokerPattern.hasMatch(broker)) {
      return 'Broker invalido. Use letras, numeros, ponto e hifen.';
    }
    return null;
  }

  static String? validateClientId(String? value) {
    final String clientId = value?.trim() ?? '';
    if (clientId.isEmpty) {
      return 'Informe o Client ID.';
    }
    if (clientId.contains(' ')) {
      return 'Client ID nao pode conter espacos.';
    }
    if (clientId.length > 50) {
      return 'Client ID muito longo (maximo de 50 caracteres).';
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
      return 'Porta invalida. Use apenas numeros.';
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
      return 'O topico nao pode conter espacos.';
    }
    if (topic.startsWith('/') || topic.endsWith('/')) {
      return 'Evite / no inicio ou no fim do topico.';
    }
    if (topic.contains('//')) {
      return 'O topico contem niveis vazios (//).';
    }
    if (topic.contains('#') || topic.contains('+')) {
      return 'Use um prefixo especifico sem curingas (#/+).';
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
      return 'Valor invalido. Use apenas numeros.';
    }
    if (!allowZero && parsed == 0) {
      return 'O valor deve ser maior que zero.';
    }
    if (parsed < min) {
      return 'O valor minimo permitido e $min.';
    }
    if (max != null && parsed > max) {
      return 'O valor maximo permitido e $max.';
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
