import 'dart:io';

class MqttSettingsValidators {
  static final RegExp _brokerPattern = RegExp(r'^[a-zA-Z0-9.-]+$');

  /// Aceita `host`, `ws://host` e `wss://host`.
  ///
  /// O WebSocket existe porque redes que bloqueiam as portas MQTT (1883 e
  /// 8883) costumam deixar passar a 8080 — é assim que as placas conectam.
  static String? validateBroker(String? value) {
    final String broker = value?.trim() ?? '';
    if (broker.isEmpty) {
      return 'Informe o broker MQTT.';
    }
    if (broker.startsWith('http://') || broker.startsWith('https://')) {
      return 'Para WebSocket use ws:// ou wss://, não http:// nem https://.';
    }
    final String host = brokerHost(broker);
    if (host.isEmpty || host.contains('/') || host.contains(' ')) {
      return 'Broker inválido. Use host, ws://host ou wss://host.';
    }
    if (!_brokerPattern.hasMatch(host)) {
      return 'Broker inválido. Use letras, números, ponto e hífen.';
    }
    return null;
  }

  /// Host sem o esquema, para mostrar e comparar.
  static String brokerHost(String broker) {
    final String limpo = broker.trim();
    for (final String esquema in <String>['ws://', 'wss://']) {
      if (limpo.startsWith(esquema)) return limpo.substring(esquema.length);
    }
    return limpo;
  }

  /// Endereço a usar na conexão, preferindo IPv4 quando não há TLS.
  ///
  /// Rede sem rota IPv6 devolve "Network is unreachable (errno 101)" assim que
  /// o app tenta o endereço AAAA do broker — foi o que apareceu na bancada.
  /// Sem TLS, conectar direto no IPv4 resolve; com TLS o nome precisa ficar,
  /// senão o certificado não bate.
  static Future<String> enderecoPreferindoIPv4(
    String broker, {
    required bool comTls,
  }) async {
    final String nome = brokerHost(broker);
    if (comTls || nome.isEmpty || InternetAddress.tryParse(nome) != null) {
      return broker;
    }
    try {
      final List<InternetAddress> encontrados = await InternetAddress.lookup(
        nome,
        type: InternetAddressType.IPv4,
      ).timeout(const Duration(seconds: 6));
      if (encontrados.isEmpty) return broker;
      final String ip = encontrados.first.address;
      return brokerUsaWebSocket(broker) ? 'ws://$ip' : ip;
    } catch (_) {
      return broker;  // Sem resolver, segue com o nome: o erro dirá o porquê.
    }
  }

  static bool brokerUsaWebSocket(String broker) {
    final String limpo = broker.trim();
    return limpo.startsWith('ws://') || limpo.startsWith('wss://');
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
