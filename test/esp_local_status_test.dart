import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/models/esp_local_status.dart';

void main() {
  group('EspHealth', () {
    test('le o payload de /health do Modulo 1', () {
      final EspHealth? health = EspHealth.tryParse(
        '{"ok":true,"device_id":"esp32-01","firmware_version":"1.1.0",'
        '"uptime_s":3600,"free_heap":180000,"wifi_connected":true,"rssi":-58,'
        '"ip":"192.168.0.50","fallback_ap":false,"updating":false,'
        '"ota_local_enabled":true,'
        '"module":{"role":"actuator","state":"rodando","motor_on":true}}',
      );

      expect(health, isNotNull);
      expect(health!.deviceId, 'esp32-01');
      expect(health.firmwareVersion, '1.1.0');
      expect(health.wifiConnected, isTrue);
      expect(health.rssi, -58);
      expect(health.role, 'actuator');
      expect(health.module['state'], 'rodando');
    });

    test('aceita payload sem o bloco module', () {
      final EspHealth? health = EspHealth.tryParse(
        '{"device_id":"esp32-02","firmware_version":"1.1.0"}',
      );

      expect(health, isNotNull);
      expect(health!.module, isEmpty);
      expect(health.role, isNull);
      expect(health.wifiConnected, isFalse);
    });

    test('devolve null para payload invalido', () {
      expect(EspHealth.tryParse('nao e json'), isNull);
      expect(EspHealth.tryParse('[1,2,3]'), isNull);
    });
  });

  group('EspWifiNetwork', () {
    test('ordena por sinal e descarta SSID vazio', () {
      final List<EspWifiNetwork> redes = EspWifiNetwork.listFromPayload(
        '{"ok":true,"networks":['
        '{"ssid":"Fraca","rssi":-80,"secure":true},'
        '{"ssid":"","rssi":-40,"secure":false},'
        '{"ssid":"Forte","rssi":-45,"secure":true}]}',
      );

      expect(redes.map((EspWifiNetwork r) => r.ssid), <String>['Forte', 'Fraca']);
    });

    test('mantem so o melhor sinal de um SSID repetido em varios canais', () {
      final List<EspWifiNetwork> redes = EspWifiNetwork.listFromPayload(
        '{"networks":['
        '{"ssid":"Planta","rssi":-75,"secure":true},'
        '{"ssid":"Planta","rssi":-52,"secure":true}]}',
      );

      expect(redes, hasLength(1));
      expect(redes.single.rssi, -52);
    });

    test('devolve lista vazia quando nao ha o campo networks', () {
      expect(EspWifiNetwork.listFromPayload('{"ok":true}'), isEmpty);
    });
  });

  group('EspProvisionConfig', () {
    test('le o payload de /provision', () {
      final EspProvisionConfig? config = EspProvisionConfig.tryParse(
        '{"ok":true,"provisioned":true,"ssid":"RedeDaPlanta",'
        '"mqttHost":"broker.exemplo.com","mqttPort":8883,"mqttUser":"iotmotor",'
        '"topicPrefix":"iotmotor-ifma-7f3a","useTls":true,'
        '"hasWifiPassword":true,"hasMqttPassword":true}',
      );

      expect(config, isNotNull);
      expect(config!.provisioned, isTrue);
      expect(config.ssid, 'RedeDaPlanta');
      expect(config.mqttPort, 8883);
      expect(config.useTls, isTrue);
      expect(config.hasWifiPassword, isTrue);
    });

    test('cai na porta padrao quando o campo falta', () {
      final EspProvisionConfig? config = EspProvisionConfig.tryParse(
        '{"provisioned":false,"ssid":"BotComp","mqttHost":"test.mosquitto.org"}',
      );

      expect(config, isNotNull);
      expect(config!.mqttPort, 1883);
      expect(config.useTls, isFalse);
      expect(config.provisioned, isFalse);
    });
  });
}
