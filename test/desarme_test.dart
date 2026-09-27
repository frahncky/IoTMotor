import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/board_alarm.dart';
import 'package:iotmotor/features/iot_motor/models/motor_command_type.dart';
import 'package:iotmotor/features/iot_motor/services/alertas_da_bancada.dart';
import 'package:iotmotor/features/iot_motor/view/widgets/motor_animation_card.dart';

String quadro({String? desarme}) => jsonEncode(<String, dynamic>{
  'device_id': 'esp32-01',
  'boot': '0123456789abcdef',
  'relays': <bool>[false, false, false, false],
  if (desarme != null) 'trip_alarm': 'temp',
  if (desarme != null) 'trip_field': desarme,
});

void main() {
  test('o alarme leva o desarme para a placa, desligado por padrão', () {
    final BoardAlarm padrao = BoardAlarm.fromMap(<String, dynamic>{
      'id': 'temp', 'field': 'temperature', 'board': 'sensors', 'above': true, 'limit': 60,
    })!;
    expect(padrao.trip, isFalse);
    expect(padrao.toBoard()['trip'], isFalse);

    final BoardAlarm desarma = padrao.copyWith(trip: true);
    expect(desarma.toBoard()['trip'], isTrue);
    // Ligar/desligar o alarme não perde a escolha do desarme.
    expect(desarma.copyWith(enabled: false).trip, isTrue);
    expect(BoardAlarm.listFromPayload(jsonEncode(<String, dynamic>{
      'alarms': <Map<String, dynamic>>[desarma.toBoard()],
    })).single.trip, isTrue);
  });

  test('o controlador sabe qual alarme desligou o motor, até a próxima partida', () {
    final MotorControlController c = MotorControlController(loadSettings: false);
    addTearDown(c.dispose);
    c.handlePayloadForTest('iotmotor/esp32-01/telemetry', quadro(desarme: 'temperature'));
    expect(c.desarmeCampo, 'temperature');
    c.handlePayloadForTest('iotmotor/esp32-01/telemetry', quadro());
    expect(c.desarmeCampo, isNull);
  });

  testWidgets('o cartão do motor diz por que ele parou', (WidgetTester tester) async {
    final MotorControlController c = MotorControlController(loadSettings: false);
    c.isConnected = true;
    c.handlePayloadForTest('iotmotor/esp32-01/telemetry', quadro(desarme: 'temperature'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MotorAnimationCard(controller: c, startType: MotorCommandType.directStart)),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Desligado pelo alarme de temperatura'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  test('no celular, o alarme com desarme avisa que desliga o motor', () {
    final AlertasDaBancada alertas = AlertasDaBancada(agora: () => DateTime(2026, 9, 27, 10));
    alertas.receber('iotmotor/esp32-02/alarms', jsonEncode(<String, dynamic>{
      'device_id': 'esp32-02',
      'alarms': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'temp', 'field': 'temperature', 'board': 'sensors', 'above': true, 'limit': 60, 'trip': true},
      ],
    }));
    final AvisoDoCelular aviso = alertas.receber('iotmotor/esp32-02/telemetry', jsonEncode(<String, dynamic>{
      'device_id': 'esp32-02', 'temperature': 64, 'alarms_firing': <String>['temp'],
    })).single;
    expect(aviso.texto, endsWith('agora 64 °C · desliga o motor'));
  });
}
