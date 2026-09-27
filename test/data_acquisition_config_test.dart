import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/data_acquisition_config.dart';
import 'package:iotmotor/features/iot_motor/services/mqtt_motor_service.dart';

void main() {
  test('perfis técnicos de aquisição respeitam os limites', () {
    expect(DataAcquisitionConfig.realtime.validationMessage, isNull);
    expect(DataAcquisitionConfig.monitoring.validationMessage, isNull);
    expect(DataAcquisitionConfig.economic.validationMessage, isNull);

    const DataAcquisitionConfig invalida = DataAcquisitionConfig(
      mqttIntervalMs: 5000,
      chartIntervalMs: 1000,
      recordIntervalMs: 1000,
    );
    expect(invalida.validationMessage, contains('gráfico'));
  });

  test('sincroniza somente depois de receber as duas placas', () {
    final MotorControlController controller = MotorControlController(
      service: MqttMotorService(),
      loadSettings: false,
    );
    addTearDown(controller.dispose);

    controller.handlePayloadForTest(
      'iotmotor/esp32-01/data_config',
      '{"v":1,"device_id":"esp32-01","role":"command",'
      '"pzem_interval_ms":2000,"mqtt_interval_ms":2000}',
    );

    expect(controller.dataAcquisitionSynchronized, isFalse);
    expect(controller.dataAcquisitionConfig.pzemIntervalMs, 2000);

    controller.handlePayloadForTest(
      'iotmotor/esp32-02/data_config',
      '{"v":1,"device_id":"esp32-02","role":"sensor",'
      '"vibration_sampling_hz":1000,"vibration_window_ms":1000,'
      '"mqtt_interval_ms":2000,"chart_interval_ms":2000,'
      '"record_interval_ms":5000}',
    );

    expect(controller.dataAcquisitionSynchronized, isTrue);
    expect(controller.dataAcquisitionConfig.mqttIntervalMs, 2000);
    expect(controller.dataAcquisitionConfig.chartIntervalMs, 2000);
    expect(controller.dataAcquisitionConfig.recordIntervalMs, 5000);
    expect(controller.dataAcquisitionConfig.vibrationWindowMs, 1000);
  });

  test('detecta telemetria divergente entre as placas', () {
    final MotorControlController controller = MotorControlController(
      service: MqttMotorService(),
      loadSettings: false,
    );
    addTearDown(controller.dispose);

    controller.handlePayloadForTest(
      'iotmotor/esp32-01/data_config',
      '{"v":1,"device_id":"esp32-01","role":"command",'
      '"pzem_interval_ms":3000,"mqtt_interval_ms":1000}',
    );
    controller.handlePayloadForTest(
      'iotmotor/esp32-02/data_config',
      '{"v":1,"device_id":"esp32-02","role":"sensor",'
      '"vibration_window_ms":1000,"mqtt_interval_ms":5000,'
      '"chart_interval_ms":5000,"record_interval_ms":5000}',
    );

    expect(controller.dataAcquisitionSynchronized, isFalse);
  });
}
