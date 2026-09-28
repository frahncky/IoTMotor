import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/view/tabs/settings_tab.dart';

void main() {
  testWidgets('campos de "Avançado" recolhidos continuam sendo validados', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final MotorControlController controller = MotorControlController(
      loadSettings: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: ConfiguracoesTab(controller: controller)),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('config_Conexão')));
    await tester.pumpAndSettle();

    // Abre, deixa um valor inválido e fecha "Avançado" antes de conectar.
    await tester.tap(find.text('Avançado'));
    await tester.pumpAndSettle();
    controller.clientIdController.text = '';
    await tester.tap(find.text('Avançado'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conectar'));
    await tester.pump();
    expect(find.textContaining('em "Avançado"'), findsOneWidget);
    expect(controller.isConnected, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
