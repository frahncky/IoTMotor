import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/board_alarm.dart';

/// Payload igual ao que o ESP32-S3 publica, retido, em iotmotor/esp32-02/alarms.
String alarmesDaPlaca() => jsonEncode(<String, dynamic>{
  'device_id': 'esp32-02',
  'enabled': true,
  'sounds': true,
  'max': 8,
  'alarms': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'vib',
      'field': 'vibration_peak',
      'board': 'sensors',
      'above': true,
      'limit': 0.5,
      'on': true,
      'firing': false,
    },
    <String, dynamic>{
      'id': 'current',
      'field': 'current',
      'board': 'command',
      'above': true,
      'limit': 12.5,
      'on': true,
      'firing': false,
    },
    // Sem limite: a placa nunca manda assim, mas o app não pode quebrar.
    <String, dynamic>{'id': 'ruim', 'field': 'voltage'},
  ],
});

void main() {
  test('a lista de alarmes da placa aparece no app', () {
    final MotorControlController c = MotorControlController(loadSettings: false);
    addTearDown(c.dispose);
    expect(c.hasBoardAlarms, isFalse);

    c.handlePayloadForTest('iotmotor/esp32-02/alarms', alarmesDaPlaca());

    expect(c.hasBoardAlarms, isTrue);
    expect(c.alarmsDeviceId, 'esp32-02');
    expect(c.boardAlarmsMax, 8);
    expect(
      c.boardAlarms.map((BoardAlarm a) => a.id),
      <String>['vib', 'current'],
      reason: 'o alarme sem limite é descartado',
    );
    final BoardAlarm corrente = c.boardAlarms[1];
    expect(corrente.fromCommandBoard, isTrue);
    expect(corrente.limit, 12.5);
    expect(describeAlarm(corrente), 'Corrente (A) acima de 12.5');
  });

  test('a telemetria diz quais alarmes estão disparados agora', () {
    final MotorControlController c = MotorControlController(loadSettings: false);
    addTearDown(c.dispose);
    c.handlePayloadForTest('iotmotor/esp32-02/alarms', alarmesDaPlaca());

    c.handlePayloadForTest(
      'iotmotor/esp32-02/telemetry',
      jsonEncode(<String, dynamic>{
        'device_id': 'esp32-02',
        'alarm_active': true,
        'alarms_firing': <String>['current'],
      }),
    );

    expect(c.firingAlarmIds, <String>{'current'});
    expect(c.boardAlarms.firstWhere((BoardAlarm a) => a.id == 'vib').firing, isFalse);
    expect(
      c.boardAlarms.firstWhere((BoardAlarm a) => a.id == 'current').firing,
      isTrue,
    );

    c.handlePayloadForTest(
      'iotmotor/esp32-02/telemetry',
      jsonEncode(<String, dynamic>{
        'device_id': 'esp32-02',
        'alarm_active': false,
        'alarms_firing': <String>[],
      }),
    );
    expect(c.firingAlarmIds, isEmpty);
    expect(c.boardAlarms.every((BoardAlarm a) => !a.firing), isTrue);
  });

  test('id novo não colide com o que já está na placa', () {
    final MotorControlController c = MotorControlController(loadSettings: false);
    addTearDown(c.dispose);
    c.handlePayloadForTest('iotmotor/esp32-02/alarms', alarmesDaPlaca());

    expect(c.newAlarmId('voltage'), 'voltage');
    expect(c.newAlarmId('current'), 'current2');
  });

  test('o que vai para a placa é o mesmo formato que ela publica', () {
    const BoardAlarm alarme = BoardAlarm(
      id: 'temp',
      field: 'temperature',
      fromCommandBoard: false,
      above: false,
      limit: 12,
      enabled: false,
    );
    expect(alarme.toBoard(), <String, dynamic>{
      'id': 'temp',
      'field': 'temperature',
      'board': 'sensors',
      'above': false,
      'limit': 12.0,
      'on': false,
    });
    final BoardAlarm? volta = BoardAlarm.fromMap(alarme.toBoard());
    expect(volta?.enabled, isFalse);
    expect(volta?.above, isFalse);
    expect(volta?.limit, 12);
  });

  test('sem broker, gravar um alarme avisa em vez de falhar calado', () async {
    final MotorControlController c = MotorControlController(loadSettings: false);
    addTearDown(c.dispose);
    c.handlePayloadForTest('iotmotor/esp32-02/alarms', alarmesDaPlaca());

    const BoardAlarm alarme = BoardAlarm(
      id: 'vib',
      field: 'vibration_peak',
      fromCommandBoard: false,
      above: true,
      limit: 0.8,
    );
    expect(await c.saveBoardAlarm(alarme), isFalse);
    expect(await c.removeBoardAlarm('vib'), isFalse);
  });
}
