import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/motor_info.dart';

/// Lê a versão de firmware publicada para OTA (`firmware-latest.json`, gravado
/// pelo CI). Primeiro pela ponte da Cloudflare, que passa em redes que
/// bloqueiam o GitHub; depois direto no release.
class FirmwarePublicadoService {
  FirmwarePublicadoService({http.Client? client})
    : _client = client ?? http.Client();

  static const List<String> enderecos = <String>[
    'https://iotmotor.pages.dev/firmware/firmware-latest.json',
    'https://github.com/frahncky/IoTMotor/releases/download/firmware-latest/firmware-latest.json',
  ];

  final http.Client _client;

  /// [quadro, sensores], ou null se nenhum endereço respondeu direito.
  Future<List<String>?> buscar() async {
    for (final String endereco in enderecos) {
      try {
        final http.Response resposta = await _client
            .get(Uri.parse(endereco))
            .timeout(const Duration(seconds: 10));
        if (resposta.statusCode != 200) continue;
        final List<String>? lido = lerFirmwarePublicado(
          jsonDecode(utf8.decode(resposta.bodyBytes)),
        );
        if (lido != null) return lido;
      } catch (_) {
        // Tenta o próximo; sem nenhum, fica a reserva do app.
      }
    }
    return null;
  }
}
