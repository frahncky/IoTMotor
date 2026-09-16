import 'dart:convert';

/// Estado devolvido por `GET /health` no servico local do modulo.
class EspHealth {
  const EspHealth({
    required this.deviceId,
    required this.firmwareVersion,
    required this.ip,
    required this.wifiConnected,
    required this.fallbackAp,
    required this.updating,
    required this.uptimeSeconds,
    required this.freeHeap,
    required this.rssi,
    required this.otaLocalEnabled,
    this.module = const <String, dynamic>{},
  });

  final String deviceId;
  final String firmwareVersion;
  final String ip;
  final bool wifiConnected;
  final bool fallbackAp;
  final bool updating;
  final int uptimeSeconds;
  final int freeHeap;
  final int rssi;
  final bool otaLocalEnabled;

  /// Bloco `module`: varia entre o Modulo 1 e o Modulo 2.
  final Map<String, dynamic> module;

  static EspHealth? tryParse(String payload) {
    try {
      final dynamic decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return EspHealth.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  factory EspHealth.fromMap(Map<String, dynamic> map) {
    return EspHealth(
      deviceId: '${map['device_id'] ?? ''}',
      firmwareVersion: '${map['firmware_version'] ?? ''}',
      ip: '${map['ip'] ?? ''}',
      wifiConnected: map['wifi_connected'] == true,
      fallbackAp: map['fallback_ap'] == true,
      updating: map['updating'] == true,
      uptimeSeconds: _readInt(map['uptime_s']),
      freeHeap: _readInt(map['free_heap']),
      rssi: _readInt(map['rssi']),
      otaLocalEnabled: map['ota_local_enabled'] == true,
      module:
          map['module'] is Map<String, dynamic>
              ? map['module'] as Map<String, dynamic>
              : const <String, dynamic>{},
    );
  }

  /// Papel do modulo, quando o firmware informa: `actuator` ou `sensor`.
  String? get role {
    final String texto = '${module['role'] ?? ''}'.trim();
    return texto.isEmpty ? null : texto;
  }
}

/// Rede encontrada por `GET /wifi-networks`.
class EspWifiNetwork {
  const EspWifiNetwork({
    required this.ssid,
    required this.rssi,
    required this.secure,
  });

  final String ssid;
  final int rssi;
  final bool secure;

  factory EspWifiNetwork.fromMap(Map<String, dynamic> map) {
    return EspWifiNetwork(
      ssid: '${map['ssid'] ?? ''}',
      rssi: _readInt(map['rssi']),
      secure: map['secure'] == true,
    );
  }

  /// Lista ordenada por sinal, sem SSID vazio (redes ocultas) nem repetido.
  static List<EspWifiNetwork> listFromPayload(String payload) {
    final dynamic decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      return const <EspWifiNetwork>[];
    }

    final dynamic bruto = decoded['networks'];
    if (bruto is! List) {
      return const <EspWifiNetwork>[];
    }

    final Map<String, EspWifiNetwork> porSsid = <String, EspWifiNetwork>{};
    for (final dynamic item in bruto) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final EspWifiNetwork rede = EspWifiNetwork.fromMap(item);
      if (rede.ssid.isEmpty) {
        continue;
      }
      // A mesma rede pode aparecer em varios canais: fica a de melhor sinal.
      final EspWifiNetwork? atual = porSsid[rede.ssid];
      if (atual == null || rede.rssi > atual.rssi) {
        porSsid[rede.ssid] = rede;
      }
    }

    final List<EspWifiNetwork> redes = porSsid.values.toList();
    redes.sort((EspWifiNetwork a, EspWifiNetwork b) => b.rssi.compareTo(a.rssi));
    return redes;
  }
}

/// Configuracao em uso, devolvida por `GET /provision`. Sem as senhas.
class EspProvisionConfig {
  const EspProvisionConfig({
    required this.provisioned,
    required this.ssid,
    required this.mqttHost,
    required this.mqttPort,
    required this.mqttUser,
    required this.topicPrefix,
    required this.useTls,
    required this.hasWifiPassword,
    required this.hasMqttPassword,
  });

  final bool provisioned;
  final String ssid;
  final String mqttHost;
  final int mqttPort;
  final String mqttUser;
  final String topicPrefix;
  final bool useTls;
  final bool hasWifiPassword;
  final bool hasMqttPassword;

  static EspProvisionConfig? tryParse(String payload) {
    try {
      final dynamic decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return EspProvisionConfig.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  factory EspProvisionConfig.fromMap(Map<String, dynamic> map) {
    return EspProvisionConfig(
      provisioned: map['provisioned'] == true,
      ssid: '${map['ssid'] ?? ''}',
      mqttHost: '${map['mqttHost'] ?? ''}',
      mqttPort: _readInt(map['mqttPort'], fallback: 1883),
      mqttUser: '${map['mqttUser'] ?? ''}',
      topicPrefix: '${map['topicPrefix'] ?? ''}',
      useTls: map['useTls'] == true,
      hasWifiPassword: map['hasWifiPassword'] == true,
      hasMqttPassword: map['hasMqttPassword'] == true,
    );
  }
}

int _readInt(dynamic value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}
