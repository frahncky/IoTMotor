import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'mqtt_settings_validators.dart';

/// Resultado de um caminho testado até o broker.
class MqttPathResult {
  const MqttPathResult({
    required this.label,
    required this.host,
    required this.port,
    required this.useTls,
    required this.ok,
    required this.detail,
  });

  /// Como o caminho aparece na tela: "WebSocket · porta 8080".
  final String label;

  /// O que vai para o campo "Broker host" se a pessoa aplicar este caminho.
  final String host;
  final int port;
  final bool useTls;
  final bool ok;

  /// "conectou" ou a causa da falha, em uma linha.
  final String detail;
}

/// Tenta os caminhos conhecidos até o broker e diz qual funciona.
///
/// Serve para a bancada da escola, onde a rede bloqueia portas diferentes em
/// dias diferentes: em vez de adivinhar, o app tenta e mostra o que passou.
/// Cada tentativa usa um cliente próprio e é encerrada em seguida, então isso
/// não mexe na conexão que estiver ativa.
Future<List<MqttPathResult>> verificarCaminhos({
  required String broker,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final String host = MqttSettingsValidators.brokerHost(broker);
  final List<MqttPathResult> resultados = <MqttPathResult>[];
  if (host.isEmpty) return resultados;

  final List<List<Object>> candidatos = <List<Object>>[
    <Object>['WebSocket · porta 8080', 'ws://$host', 8080, false],
    <Object>['WebSocket com TLS · porta 8081', 'wss://$host', 8081, false],
    <Object>['MQTT direto · porta 1883', host, 1883, false],
    <Object>['MQTT com TLS · porta 8883', host, 8883, true],
  ];

  for (final List<Object> candidato in candidatos) {
    final String label = candidato[0] as String;
    final String servidor = candidato[1] as String;
    final int porta = candidato[2] as int;
    final bool tls = candidato[3] as bool;
    final String detalhe = await _tentar(servidor, porta, tls, timeout);
    resultados.add(
      MqttPathResult(
        label: label,
        host: servidor,
        port: porta,
        useTls: tls,
        ok: detalhe.isEmpty,
        detail: detalhe.isEmpty ? 'conectou' : detalhe,
      ),
    );
  }
  return resultados;
}

/// Devolve vazio quando conectou, ou a causa resumida da falha.
Future<String> _tentar(
  String servidor,
  int porta,
  bool tls,
  Duration timeout,
) async {
  final MqttServerClient cliente = MqttServerClient.withPort(
    servidor,
    'iotmotor_teste_${DateTime.now().microsecondsSinceEpoch % 1000000}',
    porta,
  );
  cliente.logging(on: false);
  cliente.keepAlivePeriod = 20;
  cliente.autoReconnect = false;
  cliente.connectTimeoutPeriod = timeout.inMilliseconds;
  if (MqttSettingsValidators.brokerUsaWebSocket(servidor)) {
    cliente.useWebSocket = true;
    cliente.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
    cliente.secure = false;
  } else {
    cliente.secure = tls;
  }
  cliente.connectionMessage =
      MqttConnectMessage()
          .withClientIdentifier(cliente.clientIdentifier)
          .startClean();

  try {
    await cliente.connect().timeout(timeout + const Duration(seconds: 2));
    final bool conectou =
        cliente.connectionStatus?.state == MqttConnectionState.connected;
    final String motivo =
        conectou ? '' : 'recusado (${cliente.connectionStatus?.returnCode})';
    cliente.disconnect();
    return motivo;
  } catch (erro) {
    cliente.disconnect();
    return _resumir(erro);
  }
}

/// Cada falha aponta para um lado: rede, porta ou endereço.
String _resumir(Object erro) {
  final String texto = erro.toString();
  if (texto.contains('timed out') || texto.contains('TimeoutException')) {
    return 'sem resposta: a rede está bloqueando esta porta';
  }
  if (texto.contains('refused')) {
    return 'recusada: o broker não atende nesta porta';
  }
  if (texto.contains('HandshakeException') || texto.contains('CERTIFICATE')) {
    return 'falha de TLS nesta porta';
  }
  if (texto.contains('Failed host lookup') || texto.contains('lookup')) {
    return 'não resolveu o nome: sem internet ou host errado';
  }
  if (texto.contains('scheme')) return 'endereço inválido';
  final String curto = texto.replaceAll('\n', ' ');
  return curto.length > 90 ? '${curto.substring(0, 90)}…' : curto;
}
