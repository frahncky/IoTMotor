import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/mqtt_connection_config.dart';
import 'package:iotmotor/features/iot_motor/services/mqtt_motor_service.dart';

void main() {
  test(
    'registra alertas de telemetria sem repetir enquanto limite segue ativo',
    () {
      final _FakeMqttMotorService service = _FakeMqttMotorService();
      final MotorControlController controller = MotorControlController(
        service: service,
      );
      service.config = const MqttConnectionConfig(
        host: 'broker.hivemq.com',
        port: 1883,
        clientId: 'test_client',
        topicPrefix: 'iotmotor',
        deviceId: 'auto',
        useTls: false,
      );
      controller.isConnected = true;

      service.emit(
        'iotmotor/esp-1/telemetry',
        '{"voltage":250,"current":12,"temperature":72}',
      );
      service.emit(
        'iotmotor/esp-1/telemetry',
        '{"voltage":251,"current":13,"temperature":73}',
      );

      expect(controller.alerts.length, 3);
      expect(controller.pendingAlertsCount, 3);
      expect(
        controller.alerts.map((alert) => alert.metric),
        contains('voltage'),
      );
      expect(
        controller.alerts.map((alert) => alert.metric),
        contains('current'),
      );
      expect(
        controller.alerts.map((alert) => alert.metric),
        contains('temperature'),
      );

      controller.acknowledgeAlert(controller.alerts.first.id);
      expect(controller.pendingAlertsCount, 2);

      controller.dispose();
    },
  );
}

class _FakeMqttMotorService extends MqttMotorService {
  MqttConnectionConfig? config;

  @override
  MqttConnectionConfig? get activeConfig => config;

  void emit(String topic, String payload) {
    onPayload?.call(topic, payload);
  }

  @override
  Future<void> disconnect({bool silent = false}) async {}
}
