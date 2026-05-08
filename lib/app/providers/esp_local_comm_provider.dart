import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final espLocalCommProvider = Provider<EspLocalCommService>((ref) {
  return EspLocalCommService();
});

class EspLocalCommService {
  Future<http.Response> sendProvisionCommand({
    required String espHost,
    required Map<String, String> body,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final uri = Uri.parse('http://$espHost/provision');
    return await http.post(uri, body: body).timeout(timeout);
  }

  Future<http.Response> getWifiNetworks({
    required String espHost,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = Uri.parse('http://$espHost/wifi-networks');
    return await http.get(uri).timeout(timeout);
  }
}
