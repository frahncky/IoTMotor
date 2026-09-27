import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/motor_command_type.dart';
import 'package:iotmotor/features/iot_motor/view/widgets/motor_animation_card.dart';

void main() {
  testWidgets('cartão animado mostra estado e partida selecionada', (
    WidgetTester tester,
  ) async {
    final MotorControlController controller =
        MotorControlController(loadSettings: false);

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

    expect(find.byKey(const ValueKey<String>('motor_animation_paint')), findsOneWidget);
    expect(find.text('Motor desligado'), findsOneWidget);
    expect(find.textContaining('Rotação de placa:'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
