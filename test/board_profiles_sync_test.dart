import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/motor_command_type.dart';

/// Payload igual ao que o ESP32-01 publica em iotmotor/esp32-01/profiles.
String perfisDaPlaca() => jsonEncode(<String, dynamic>{
  'device_id': 'esp32-01',
  'max': 6,
  'limit_ms': 300000,
  'profiles': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'direta',
      'name': 'Direta',
      'cnt': <Map<String, dynamic>>[
        <String, dynamic>{'use': true, 'on': 500, 'off': 0},
        <String, dynamic>{'use': false, 'on': 0, 'off': 0},
        <String, dynamic>{'use': false, 'on': 0, 'off': 0},
        <String, dynamic>{'use': false, 'on': 0, 'off': 0},
      ],
    },
    <String, dynamic>{
      'id': 'estrela',
      'name': 'Estrela-triangulo',
      'cnt': <Map<String, dynamic>>[
        <String, dynamic>{'use': true, 'on': 500, 'off': 0},
        <String, dynamic>{'use': true, 'on': 500, 'off': 5500},
        <String, dynamic>{'use': true, 'on': 6200, 'off': 0},
        <String, dynamic>{'use': false, 'on': 0, 'off': 0},
      ],
    },
  ],
});

void main() {
  test('a lista de partidas da placa substitui a lista local do app', () {
    final MotorControlController c = MotorControlController(loadSettings: false);
    addTearDown(c.dispose);
    expect(c.startTypesFromBoard, isFalse);

    c.handlePayloadForTest('iotmotor/esp32-01/profiles', perfisDaPlaca());

    expect(c.startTypesFromBoard, isTrue);
    expect(c.startTypes.map((MotorCommandType t) => t.id), <String>['direta', 'estrela']);
    final MotorCommandType estrela = c.startTypes.last;
    expect(estrela.label, 'Estrela-triangulo');
    expect(estrela.timings?[1], const ContactorTiming(use: true, onMs: 500, offMs: 5500));
    // O resumo mostra os tempos de cada contator, como no painel.
    expect(estrela.profileSummary, contains('CNT 2: 0.5s a 5.5s'));
    expect(estrela.profileSummary, contains('CNT 3: 6.2s até parar'));
  });

  test('lista inválida ou vazia não apaga o que o app já mostrava', () {
    final MotorControlController c = MotorControlController(loadSettings: false);
    addTearDown(c.dispose);
    c.handlePayloadForTest('iotmotor/esp32-01/profiles', perfisDaPlaca());
    final int antes = c.startTypes.length;

    c.handlePayloadForTest('iotmotor/esp32-01/profiles', '{"device_id":"esp32-01","profiles":[]}');
    c.handlePayloadForTest('iotmotor/esp32-01/profiles', 'isto nao e json');

    expect(c.startTypes.length, antes);
  });

  test('partidas antigas do app viram tempos por contator para a placa', () {
    final MotorCommandType direta = MotorCommandType.start(
      id: 'd', label: 'Direta 1 e 4', mode: 'direta', sequence: false, mask: 0x9,
    );
    expect(direta.timingsToBoard(), <Map<String, dynamic>>[
      <String, dynamic>{'use': true, 'on': 500, 'off': 0},
      <String, dynamic>{'use': false, 'on': 500, 'off': 0},
      <String, dynamic>{'use': false, 'on': 500, 'off': 0},
      <String, dynamic>{'use': true, 'on': 500, 'off': 0},
    ]);

    final MotorCommandType estrela = MotorCommandType.start(
      id: 'e', label: 'ET', mode: 'et', sequence: true,
      main: 1, star: 2, delta: 3, seconds: 8,
    );
    final List<Map<String, dynamic>> saida = estrela.timingsToBoard();
    expect(saida[0], <String, dynamic>{'use': true, 'on': 500, 'off': 0});
    expect(saida[1], <String, dynamic>{'use': true, 'on': 500, 'off': 8500});
    // Triângulo entra depois do tempo morto de 700 ms.
    expect(saida[2], <String, dynamic>{'use': true, 'on': 9200, 'off': 0});
    expect(saida[3]['use'], isFalse);
  });

  test('app segue a partida que a placa informa estar em andamento', () {
    final MotorControlController c = MotorControlController(loadSettings: false);
    addTearDown(c.dispose);
    c.handlePayloadForTest('iotmotor/esp32-01/profiles', perfisDaPlaca());
    c.deviceIdController.text = 'esp32-01';

    String telemetria({String? emExecucao}) => jsonEncode(<String, dynamic>{
      'device_id': 'esp32-01',
      'boot': '0123456789abcdef',
      'relays': <bool>[emExecucao != null, false, false, false],
      if (emExecucao != null) 'profile': emExecucao,
    });

    c.handlePayloadForTest('iotmotor/esp32-01/telemetry', telemetria());
    expect(c.runningProfileId, isNull);

    // Partida acionada em outro lugar (painel ou outro celular).
    c.handlePayloadForTest('iotmotor/esp32-01/telemetry', telemetria(emExecucao: 'estrela'));
    expect(c.runningProfileId, 'estrela');
    expect(c.selectedDeviceConnectionType?.id, 'estrela');

    // Ao parar, o app deixa de apontar uma partida em andamento.
    c.handlePayloadForTest('iotmotor/esp32-01/telemetry', telemetria());
    expect(c.runningProfileId, isNull);
  });
}
