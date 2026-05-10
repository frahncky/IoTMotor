import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/mqtt_connection_config.dart';
import 'package:iotmotor/features/iot_motor/services/mqtt_motor_service.dart';

const MqttConnectionConfig _testConfig = MqttConnectionConfig(
  host: 'localhost',
  port: 1883,
  clientId: 'motor_test',
  topicPrefix: 'iotmotor',
  deviceId: 'esp_test',
  useTls: false,
);

class _FakeMqttMotorService extends MqttMotorService {
  MqttConnectionConfig? _activeConfig = _testConfig;

  @override
  MqttConnectionConfig? get activeConfig => _activeConfig;

  @override
  Future<MqttConnectResult> connect(MqttConnectionConfig config) async {
    _activeConfig = config;
    return const MqttConnectResult(
      success: true,
      message: 'Conectado em teste',
    );
  }

  @override
  Future<void> disconnect({bool silent = false}) async {
    if (!silent) {
      onDisconnected?.call(manual: true);
    }
  }
}

void main() {
  test(
    'Teste de Estresse: Alta carga de telemetria e Pruning de Histórico',
    () {
      final service = _FakeMqttMotorService();
      final controller = MotorControlController(
        service: service,
        loadSettings: false,
      );
      addTearDown(controller.dispose);

      const int deviceCount = 50;
      const int payloadCount = 2500;

      for (int p = 0; p < payloadCount; p++) {
        final String deviceId = 'esp_${p % deviceCount}';
        final String payload = jsonEncode(<String, Object>{
          'voltage': 220.0 + (p % 10),
          'current': 5.0,
          'motor_on': true,
        });

        service.onPayload?.call('iotmotor/$deviceId/telemetry', payload);
      }

      expect(controller.knownDeviceCount, deviceCount);
      expect(controller.historyEntryCount, MotorControlController.maxHistory);
      expect(controller.latestSample, isNotNull);
    },
  );

  test('Teste de Robustez: Network Flapping', () async {
    final controller = MotorControlController(
      service: _FakeMqttMotorService(),
      loadSettings: false,
    );
    addTearDown(controller.dispose);

    for (int i = 0; i < 20; i++) {
      controller.isConnected = true;
      // Simula perda de conexão súbita
      await controller.disconnect();

      // Simula reconexão rápida
      await controller.connect();
    }

    expect(controller.isBusy, isFalse);
    expect(controller.isConnected, isTrue);
  });
}
