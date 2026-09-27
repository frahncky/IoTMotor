import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';

void main() {
  test('resume clientes ativos por App e Web usando presença MQTT', () {
    final MotorControlController controller =
        MotorControlController(loadSettings: false);
    addTearDown(controller.dispose);

    expect(controller.commandClientsSummary, '0 · App 0 · Web 0');

    controller.handlePayloadForTest(
      'iotmotor/clients/app_a/presence',
      '{"kind":"command_client","source":"app","client_id":"app_a","state":"online"}',
    );
    expect(controller.commandClientsSummary, '1 · App 1 · Web 0');

    controller.handlePayloadForTest(
      'iotmotor/clients/web_a/presence',
      '{"kind":"command_client","source":"web","client_id":"web_a","state":"online"}',
    );
    expect(controller.commandClientsSummary, '2 · App 1 · Web 1');

    controller.handlePayloadForTest(
      'iotmotor/clients/app_a/presence',
      '{"kind":"command_client","source":"app","client_id":"app_a","state":"offline"}',
    );
    expect(controller.commandClientsSummary, '1 · App 0 · Web 1');
  });

  test('ignora presença que não seja cliente App ou Web', () {
    final MotorControlController controller =
        MotorControlController(loadSettings: false);
    addTearDown(controller.dispose);

    controller.handlePayloadForTest(
      'iotmotor/clients/esp32-01/presence',
      '{"kind":"command_client","source":"esp","client_id":"esp32-01","state":"online"}',
    );

    expect(controller.commandClientsSummary, '0 · App 0 · Web 0');
  });
}
