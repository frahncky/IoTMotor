import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/motor_info.dart';
import 'package:iotmotor/features/iot_motor/models/mqtt_connection_config.dart';
import 'package:iotmotor/features/iot_motor/services/mqtt_motor_service.dart';

const MqttConnectionConfig _config = MqttConnectionConfig(
  host: 'ws://test.mosquitto.org',
  port: 8080,
  clientId: 'teste_ota',
  topicPrefix: 'iotmotor',
  deviceId: 'auto',
  useTls: false,
);

class _FakeMqttMotorService extends MqttMotorService {
  int _seq = 0;

  @override
  MqttConnectionConfig? get activeConfig => _config;

  @override
  String? sendMaintenanceCommand(String action, {String? deviceId}) =>
      '${++_seq}';

  @override
  Future<void> disconnect({bool silent = false}) async {}
}

MotorControlController _controller() {
  final MotorControlController c = MotorControlController(
    service: _FakeMqttMotorService(),
    loadSettings: false,
  )..isConnected = true;
  c.handlePayloadForTest('iotmotor/esp32-01/status', 'online');
  c.handlePayloadForTest(
    'iotmotor/esp32-01/capabilities',
    '{"device_id":"esp32-01","firmware_version":"v16-antigo"}',
  );
  return c;
}

void main() {
  test('OTA fica como atualizando durante reboot e confirma ao voltar', () async {
    final MotorControlController c = _controller();
    addTearDown(c.dispose);

    expect(c.boardsToUpdate, contains('esp32-01'));

    await c.sendMaintenanceCommand('update', const <String>['esp32-01']);
    expect(c.isFirmwareUpdating('esp32-01'), isTrue);
    expect(c.firmwareUpdateLabel('esp32-01'), contains('aguardando confirmação'));

    c.handlePayloadForTest(
      'iotmotor/esp32-01/command_ack',
      '{"device_id":"esp32-01","seq":"1","action":"update","accepted":true,"reason":"baixando firmware"}',
    );
    expect(c.firmwareUpdateLabel('esp32-01'), contains('download e gravação'));

    c.handlePayloadForTest('iotmotor/esp32-01/status', 'offline');
    expect(c.deviceStatusLabel('esp32-01'), 'atualizando firmware');
    expect(c.firmwareUpdateLabel('esp32-01'), contains('reiniciando e reconectando'));

    c.handlePayloadForTest('iotmotor/esp32-01/status', 'online');
    expect(c.firmwareUpdateLabel('esp32-01'), contains('confirmando versão'));

    c.handlePayloadForTest(
      'iotmotor/esp32-01/capabilities',
      '{"device_id":"esp32-01","firmware_version":"${firmwarePublicado[0]}"}',
    );
    expect(c.isFirmwareUpdating('esp32-01'), isFalse);
    expect(c.firmwareUpdateSucceeded('esp32-01'), isTrue);
    expect(c.deviceStatusLabel('esp32-01'), 'atualizado · conectado');
    expect(c.firmwareUpdateLabel('esp32-01'), contains('Atualizado · Conectado'));
  });

  test('falha tardia do download encerra o estado de atualização', () async {
    final MotorControlController c = _controller();
    addTearDown(c.dispose);

    await c.sendMaintenanceCommand('update', const <String>['esp32-01']);
    c.handlePayloadForTest(
      'iotmotor/esp32-01/command_ack',
      '{"device_id":"esp32-01","seq":"1","action":"update","accepted":true,"reason":"baixando firmware"}',
    );
    c.handlePayloadForTest(
      'iotmotor/esp32-01/command_ack',
      '{"device_id":"esp32-01","seq":"1","action":"update","accepted":false,"reason":"falha -1: erro de download"}',
    );

    expect(c.isFirmwareUpdating('esp32-01'), isFalse);
    expect(c.firmwareUpdateLabel('esp32-01'), isNull);
    expect(c.consumePendingMessage(), contains('erro de download'));
  });
}
