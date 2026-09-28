import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/view/tabs/settings_tab.dart';

void main() {
  testWidgets('perfil de aquisição acompanha a configuração vinda da placa', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final MotorControlController controller =
        MotorControlController(loadSettings: false);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: ConfiguracoesTab(controller: controller)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey<String>('config_Aquisição')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Tempo real'), findsOneWidget);

    // Outra tela gravou o perfil Econômico: o campo precisa mostrar isso.
    controller.handlePayloadForTest(
      'iotmotor/system/acquisition',
      '{"revision":2,"pzem_read_ms":5000,"publish_ms":5000,"chart_ms":5000,"record_ms":30000}',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Econômico'), findsOneWidget);
    expect(find.text('Tempo real'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
