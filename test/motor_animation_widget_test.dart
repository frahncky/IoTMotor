import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/motor_command_type.dart';
import 'package:iotmotor/features/iot_motor/view/widgets/motor_animation_card.dart';

void main() {
  testWidgets('cartão animado mostra estado e partida selecionada', (
    WidgetTester tester,
  ) async {
    final MotorControlController controller = MotorControlController(
      loadSettings: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MotorAnimationCard(
            controller: controller,
            startType: MotorCommandType.directStart,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byKey(const ValueKey<String>('motor_animation_paint')),
      findsOneWidget,
    );
    expect(find.text('Desconectado'), findsOneWidget);
    expect(find.textContaining('Rotação de placa:'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  testWidgets('desconexão interrompe imediatamente a animação do motor', (
    WidgetTester tester,
  ) async {
    final MotorControlController controller = MotorControlController(
      loadSettings: false,
    )..isConnected = true;

    controller.handlePayloadForTest(
      'iotmotor/esp32-01/telemetry',
      '{"relays":[true,false,false,false],"motor_running":true}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MotorAnimationCard(
            controller: controller,
            startType: MotorCommandType.directStart,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Motor '), findsOneWidget);

    controller.isConnected = false;
    controller.notifyListeners();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('Desconectado'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('motor parado não mantém o desenho animando', (
    WidgetTester tester,
  ) async {
    final MotorControlController controller = MotorControlController(
      loadSettings: false,
    )..isConnected = true;
    controller.handlePayloadForTest(
      'iotmotor/esp32-01/telemetry',
      '{"relays":[false,false,false,false],"motor_running":false,"voltage":220,"current":0,"pzem_ok":true}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MotorAnimationCard(
            controller: controller,
            startType: MotorCommandType.directStart,
          ),
        ),
      ),
    );
    // Sem quadros pendentes: pumpAndSettle termina.
    await tester.pumpAndSettle();
    expect(find.text('Motor desligado'), findsOneWidget);

    // Liga: anima; desliga: desacelera e volta a dormir.
    controller.handlePayloadForTest(
      'iotmotor/esp32-01/telemetry',
      '{"relays":[true,false,false,false],"motor_running":true}',
    );
    controller.notifyListeners();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Motor partindo'), findsOneWidget);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Motor ligado'), findsOneWidget);

    controller.handlePayloadForTest(
      'iotmotor/esp32-01/telemetry',
      '{"relays":[false,false,false,false],"motor_running":false}',
    );
    controller.notifyListeners();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Motor desacelerando'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Motor desligado'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('PZEM sem leitura identifica partida bloqueada', (
    WidgetTester tester,
  ) async {
    final MotorControlController controller = MotorControlController(
      loadSettings: false,
    )..isConnected = true;
    controller.handlePayloadForTest(
      'iotmotor/esp32-01/telemetry',
      '{"relays":[false,false,false,false],"motor_running":false,"pzem_ok":false}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MotorAnimationCard(
            controller: controller,
            startType: MotorCommandType.directStart,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Partida bloqueada'), findsOneWidget);
    expect(find.text('Sem medição válida de tensão/corrente'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('movimento reduzido mostra o estado final sem animar', (
    WidgetTester tester,
  ) async {
    final MotorControlController controller = MotorControlController(
      loadSettings: false,
    )..isConnected = true;
    controller.handlePayloadForTest(
      'iotmotor/esp32-01/telemetry',
      '{"relays":[true,false,false,false],"motor_running":true}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: MotorAnimationCard(
              controller: controller,
              startType: MotorCommandType.directStart,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Motor ligado'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Desenho do motor: Motor ligado')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('alarme de corrente acende o cartão sem ícone no desenho', (
    WidgetTester tester,
  ) async {
    final MotorControlController controller = MotorControlController(
      loadSettings: false,
    )..isConnected = true;
    controller.handlePayloadForTest(
      'iotmotor/esp32-01/telemetry',
      '{"relays":[false,false,false,false],"motor_running":false,"voltage":220,"current":0,"pzem_ok":true,"alarms_firing":["current"]}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MotorAnimationCard(
            controller: controller,
            startType: MotorCommandType.directStart,
          ),
        ),
      ),
    );
    // Sem ícone piscando, o desenho não precisa de quadros.
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('Motor desligado, outro alarme ativo')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
