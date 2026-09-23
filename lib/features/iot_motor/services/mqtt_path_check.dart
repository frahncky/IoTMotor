import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'mqtt_settings_validators.dart';

/// Um caminho possível até o broker: endereço, porta e TLS.
class MqttPathCandidate {
  const MqttPathCandidate({
    required this.label,
    required this.host,
    required this.port,
    required this.useTls,
  });

  /// Como o caminho aparece na tela: "WebSocket · porta 8080".
  final String label;

  /// O que vai para o campo "Broker host" se a pessoa aplicar este caminho.
  final String host;
  final int port;
  final bool useTls;
}

/// O que aconteceu ao tentar um caminho.
class MqttPathResult {
  const MqttPathResult({
    required this.candidate,
    required this.ok,
    required this.detail,
  });

  final MqttPathCandidate candidate;
  final bool ok;

  /// "conectou" ou a causa da falha, em uma linha.
  final String detail;
}

/// Os caminhos conhecidos até um broker, na ordem em que vale tentar.
///
/// A ordem não é arbitrária: na bancada da escola a rede bloqueia portas
/// diferentes em dias diferentes, e a 8080 é a única que sempre passou — é por
/// ela que as duas placas conectam.
List<MqttPathCandidate> caminhosConhecidos(String broker) {
  final String host = MqttSettingsValidators.brokerHost(broker);
  if (host.isEmpty) return const <MqttPathCandidate>[];
  return <MqttPathCandidate>[
    MqttPathCandidate(
      label: 'WebSocket · porta 8080',
      host: 'ws://$host',
      port: 8080,
      useTls: false,
    ),
    MqttPathCandidate(
      label: 'WebSocket com TLS · porta 8081',
      host: 'wss://$host',
      port: 8081,
      useTls: false,
    ),
    MqttPathCandidate(
      label: 'MQTT direto · porta 1883',
      host: host,
      port: 1883,
      useTls: false,
    ),
    MqttPathCandidate(
      label: 'MQTT com TLS · porta 8883',
      host: host,
      port: 8883,
      useTls: true,
    ),
  ];
}

/// Tenta um caminho e diz o que aconteceu.
///
/// Usa um cliente próprio, encerrado em seguida: não mexe na conexão ativa.
Future<MqttPathResult> verificarCaminho(
  MqttPathCandidate candidato, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final String motivo = await _tentar(candidato, timeout);
  return MqttPathResult(
    candidate: candidato,
    ok: motivo.isEmpty,
    detail: motivo.isEmpty ? 'conectou' : motivo,
  );
}

/// Devolve vazio quando conectou, ou a causa resumida da falha.
Future<String> _tentar(MqttPathCandidate candidato, Duration timeout) async {
  final MqttServerClient cliente = MqttServerClient.withPort(
    candidato.host,
    'iotmotor_teste_${DateTime.now().microsecondsSinceEpoch % 1000000}',
    candidato.port,
  );
  cliente.logging(on: false);
  cliente.keepAlivePeriod = 20;
  cliente.autoReconnect = false;
  cliente.connectTimeoutPeriod = timeout.inMilliseconds;
  if (MqttSettingsValidators.brokerUsaWebSocket(candidato.host)) {
    cliente.useWebSocket = true;
    cliente.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
    cliente.secure = false;
  } else {
    cliente.secure = candidato.useTls;
  }
  cliente.connectionMessage = MqttConnectMessage()
      .withClientIdentifier(cliente.clientIdentifier)
      .startClean();

  try {
    await cliente.connect().timeout(timeout + const Duration(seconds: 2));
    final bool conectou =
        cliente.connectionStatus?.state == MqttConnectionState.connected;
    final String motivo = conectou
        ? ''
        : 'recusado (${cliente.connectionStatus?.returnCode})';
    cliente.disconnect();
    return motivo;
  } catch (erro) {
    cliente.disconnect();
    return resumirFalhaDeConexao(erro);
  }
}

/// Cada falha aponta para um lado: rede, porta ou endereço.
String resumirFalhaDeConexao(Object erro) {
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
