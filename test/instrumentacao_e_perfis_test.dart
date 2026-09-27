import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/app/providers/mqtt_profiles_provider.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/mqtt_connection_config.dart';

String telemetriaDoQuadro({required List<bool> reles, bool? girando}) => jsonEncode(<String, dynamic>{
  'device_id': 'esp32-01',
  'boot': '0123456789abcdef',
  'relays': reles,
  'current': 4.2,
  'voltage': 220,
  if (girando != null) 'motor_running': girando,
});

void main() {
  test('modo instrumentação: motor girando sem contator da placa', () {
    final MotorControlController c = MotorControlController(loadSettings: false);
    addTearDown(c.dispose);
    c.handlePayloadForTest('iotmotor/esp32-01/telemetry',
        telemetriaDoQuadro(reles: <bool>[false, false, false, false], girando: true));
    // Ligar/Desligar segue os contatores; o desenho, o som e a carga seguem o motor.
    expect(c.isBenchMotorOn, isFalse);
    expect(c.isMotorRunning, isTrue);

    c.handlePayloadForTest('iotmotor/esp32-01/telemetry',
        telemetriaDoQuadro(reles: <bool>[false, false, false, false], girando: false));
    expect(c.isMotorRunning, isFalse);
  });

  test('placa antiga, sem motor_running, segue pelos contatores', () {
    final MotorControlController c = MotorControlController(loadSettings: false);
    addTearDown(c.dispose);
    c.handlePayloadForTest('iotmotor/esp32-01/telemetry',
        telemetriaDoQuadro(reles: <bool>[true, false, true, false]));
    expect(c.isMotorRunning, isTrue);
    c.handlePayloadForTest('iotmotor/esp32-01/telemetry',
        telemetriaDoQuadro(reles: <bool>[false, false, false, false]));
    expect(c.isMotorRunning, isFalse);
  });

  test('perfil padrão aponta para o broker das placas, com clientId único', () {
    final MqttProfile a = MqttProfilesNotifier.perfilPadrao();
    expect(a.config.host, 'ws://test.mosquitto.org');
    expect(a.config.port, 8080);
    expect(a.config.clientId, startsWith('motor_app_'));
    expect(a.config.clientId, isNot('motor_app'));
  });

  test('perfis antigos: o padrão intocado migra, o editado fica', () {
    MqttProfile perfil(String id, String host, int port, String clientId) => MqttProfile(
          id: id,
          name: id,
          config: MqttConnectionConfig(
            host: host,
            port: port,
            clientId: clientId,
            topicPrefix: 'iotmotor',
            deviceId: 'default',
            useTls: false,
          ),
        );

    final MqttProfile antigo =
        MqttProfilesNotifier.migrarPerfil(perfil('default', 'broker.hivemq.com', 1883, 'motor_app'));
    expect(antigo.config.host, 'ws://test.mosquitto.org');
    expect(antigo.config.port, 8080);
    expect(antigo.config.clientId, startsWith('motor_app_'));

    final MqttProfile editado = perfil('lab', 'wss://test.mosquitto.org', 8081, 'meu_celular');
    expect(identical(MqttProfilesNotifier.migrarPerfil(editado), editado), isTrue);

    // Broker escolhido pela pessoa fica; só o clientId fixo muda.
    final MqttProfile soId =
        MqttProfilesNotifier.migrarPerfil(perfil('lab', 'ws://test.mosquitto.org', 8080, 'motor_app'));
    expect(soId.config.host, 'ws://test.mosquitto.org');
    expect(soId.config.clientId, isNot('motor_app'));
  });
}
