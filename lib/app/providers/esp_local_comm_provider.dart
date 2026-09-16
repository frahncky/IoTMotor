import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../features/iot_motor/models/esp_local_status.dart';

final espLocalCommProvider = Provider<EspLocalCommService>((ref) {
  return EspLocalCommService();
});

/// Falha vinda do servico local do modulo, ja com a mensagem que o firmware
/// devolveu quando havia uma.
class EspLocalCommException implements Exception {
  const EspLocalCommException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Cliente das rotas locais do firmware (IoTMotorNet).
///
/// `/health` e `/wifi-networks` sao abertas. As demais exigem a chave no
/// cabecalho `X-IoTMotor-OTA-Key` — a mesma usada para gravar firmware.
class EspLocalCommService {
  static const String otaKeyHeader = 'X-IoTMotor-OTA-Key';

  Uri _uri(String espHost, String path) {
    final String host = espHost.trim();
    // Aceita tanto "192.168.0.50" quanto "http://esp32-01.local".
    if (host.startsWith('http://') || host.startsWith('https://')) {
      return Uri.parse('$host$path');
    }
    return Uri.parse('http://$host$path');
  }

  Map<String, String> _headers(String? otaKey) {
    final String chave = otaKey?.trim() ?? '';
    return <String, String>{if (chave.isNotEmpty) otaKeyHeader: chave};
  }

  /// Extrai a mensagem do corpo JSON; cai no status quando nao houver.
  Never _falhar(http.Response resposta) {
    String mensagem = 'HTTP ${resposta.statusCode}';
    try {
      final dynamic decoded = jsonDecode(resposta.body);
      if (decoded is Map<String, dynamic>) {
        final String texto = '${decoded['message'] ?? ''}'.trim();
        if (texto.isNotEmpty) {
          mensagem = texto;
        }
      }
    } catch (_) {
      // Corpo nao-JSON: fica a mensagem de status.
    }
    throw EspLocalCommException(mensagem, statusCode: resposta.statusCode);
  }

  Future<EspHealth> fetchHealth({
    required String espHost,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final http.Response resposta =
        await http.get(_uri(espHost, '/health')).timeout(timeout);
    if (resposta.statusCode != 200) {
      _falhar(resposta);
    }

    final EspHealth? estado = EspHealth.tryParse(resposta.body);
    if (estado == null) {
      throw const EspLocalCommException('Resposta de /health ilegivel.');
    }
    return estado;
  }

  Future<List<EspWifiNetwork>> fetchWifiNetworks({
    required String espHost,
    // A varredura no ESP32 bloqueia por alguns segundos.
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final http.Response resposta =
        await http.get(_uri(espHost, '/wifi-networks')).timeout(timeout);
    if (resposta.statusCode != 200) {
      _falhar(resposta);
    }

    try {
      return EspWifiNetwork.listFromPayload(resposta.body);
    } catch (_) {
      throw const EspLocalCommException('Resposta de /wifi-networks ilegivel.');
    }
  }

  Future<EspProvisionConfig> fetchProvision({
    required String espHost,
    required String otaKey,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final http.Response resposta = await http
        .get(_uri(espHost, '/provision'), headers: _headers(otaKey))
        .timeout(timeout);
    if (resposta.statusCode != 200) {
      _falhar(resposta);
    }

    final EspProvisionConfig? config = EspProvisionConfig.tryParse(resposta.body);
    if (config == null) {
      throw const EspLocalCommException('Resposta de /provision ilegivel.');
    }
    return config;
  }

  /// Grava o provisionamento. O modulo responde e reinicia em seguida, entao
  /// nao ha confirmacao posterior: o sucesso e a resposta 200.
  Future<String> applyProvision({
    required String espHost,
    required String otaKey,
    required String ssid,
    required String mqttHost,
    required String topicPrefix,
    String wifiPassword = '',
    int mqttPort = 1883,
    String mqttUser = '',
    String mqttPassword = '',
    bool useTls = false,
    String newOtaKey = '',
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final Map<String, String> corpo = <String, String>{
      'ssid': ssid,
      'wifiPassword': wifiPassword,
      'mqttHost': mqttHost,
      'mqttPort': '$mqttPort',
      'mqttUser': mqttUser,
      'mqttPassword': mqttPassword,
      'topicPrefix': topicPrefix,
      'useTls': useTls ? '1' : '0',
      if (newOtaKey.trim().isNotEmpty) 'otaKey': newOtaKey.trim(),
    };

    final http.Response resposta = await http
        .post(_uri(espHost, '/provision'), headers: _headers(otaKey), body: corpo)
        .timeout(timeout);
    if (resposta.statusCode != 200) {
      _falhar(resposta);
    }

    return _mensagemDeSucesso(resposta, 'Provisionamento gravado.');
  }

  Future<String> resetProvision({
    required String espHost,
    required String otaKey,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final http.Response resposta = await http
        .post(_uri(espHost, '/provision/reset'), headers: _headers(otaKey))
        .timeout(timeout);
    if (resposta.statusCode != 200) {
      _falhar(resposta);
    }

    return _mensagemDeSucesso(resposta, 'Provisionamento apagado.');
  }

  String _mensagemDeSucesso(http.Response resposta, String padrao) {
    try {
      final dynamic decoded = jsonDecode(resposta.body);
      if (decoded is Map<String, dynamic>) {
        final String texto = '${decoded['message'] ?? ''}'.trim();
        if (texto.isNotEmpty) {
          return texto;
        }
      }
    } catch (_) {
      // Sem corpo util: fica a mensagem padrao.
    }
    return padrao;
  }
}
