import 'package:flutter_test/flutter_test.dart';
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
}
