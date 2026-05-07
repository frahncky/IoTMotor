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

  test('filtra historico por dispositivo, metrica e estado', () {
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
      '{"voltage":220,"current":4,"motor_on":true}',
    );
    service.emit(
      'iotmotor/esp-2/telemetry',
      '{"vibration":0.42,"temperature":45,"motor_on":false}',
    );
    service.emit('iotmotor/esp-1/telemetry', '{"current":5}');

    expect(controller.historyEntryCount, 3);

    controller.setHistoryDeviceFilter('esp-2');
    expect(controller.filteredHistoryEntryCount, 1);
    expect(controller.filteredHistoryEntries.single.deviceId, 'esp-2');

    controller.clearHistoryFilters();
    controller.setHistoryMetricFilter(
      MotorControlController.historyMetricCurrent,
    );
    expect(controller.filteredHistoryEntryCount, 2);

    controller.setHistoryStateFilter(MotorControlController.historyStateOn);
    expect(controller.filteredHistoryEntryCount, 1);
    expect(controller.filteredHistoryEntries.single.sample.motorOn, isTrue);

    controller.clearHistoryFilters();
    controller.setHistoryStateFilter(MotorControlController.historyStateOff);
    expect(controller.filteredHistoryEntries.single.deviceId, 'esp-2');

    controller.dispose();
  });
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
