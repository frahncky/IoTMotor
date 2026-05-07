import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/models/motor_app_settings.dart';
import 'package:iotmotor/features/iot_motor/services/mqtt_settings_validators.dart';

void main() {
  group('MqttSettingsValidators', () {
    test('aceita configuracao MQTT valida', () {
      final String? error = MqttSettingsValidators.firstConnectionError(
        broker: 'broker.hivemq.com',
        port: '1883',
        clientId: 'iotmotor_app',
        topicPrefix: 'iotmotor/planta1',
      );

      expect(error, isNull);
    });

    test('rejeita broker com protocolo e porta fora da faixa', () {
      expect(
        MqttSettingsValidators.validateBroker('https://broker.hivemq.com'),
        isNotNull,
      );
      expect(MqttSettingsValidators.validatePort('70000'), isNotNull);
    });

    test('rejeita topic prefix com curingas ou niveis vazios', () {
      expect(
        MqttSettingsValidators.validateTopicPrefix('iotmotor/+'),
        isNotNull,
      );
      expect(
        MqttSettingsValidators.validateTopicPrefix('iotmotor//esp'),
        isNotNull,
      );
    });
  });

  test('MotorAppSettings serializa configuracoes operacionais', () {
    const MotorAppSettings settings = MotorAppSettings(
      broker: 'broker.hivemq.com',
      port: '8883',
      clientId: 'iotmotor_app',
      topicPrefix: 'iotmotor',
      username: 'operador',
      useTls: true,
      telemetryAlertsEnabled: true,
      voltageMin: '190',
      voltageMax: '240',
      currentMax: '10',
      vibrationMax: '1.5',
      temperatureMax: '70',
    );

    final MotorAppSettings? restored = MotorAppSettings.fromMap(
      settings.toMap(),
    );

    expect(restored, isNotNull);
    expect(restored!.broker, settings.broker);
    expect(restored.port, settings.port);
    expect(restored.clientId, settings.clientId);
    expect(restored.useTls, isTrue);
    expect(restored.telemetryAlertsEnabled, isTrue);
    expect(restored.temperatureMax, '70');
  });
}
