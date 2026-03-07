import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iotmotor/app/iot_motor_app.dart';

void main() {
  testWidgets('renderiza tabs de início, histórico e configurações', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MotorControlApp());
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((Widget widget) {
        if (widget is! RichText) {
          return false;
        }
        return widget.text.toPlainText() == 'IoTMotor';
      }),
      findsOneWidget,
    );
    expect(find.text('Direta'), findsOneWidget);
    expect(find.text('Ligar'), findsOneWidget);
    expect(find.text('Desligar'), findsNothing);
    expect(find.textContaining('Tens'), findsOneWidget);
    expect(find.byIcon(Icons.electric_bolt_rounded), findsAtLeastNWidgets(1));
    expect(
      find.byIcon(Icons.precision_manufacturing_rounded),
      findsAtLeastNWidgets(1),
    );
    expect(find.byIcon(Icons.settings_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.precision_manufacturing_rounded).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Vibra'), findsOneWidget);
    expect(find.text('Temperatura'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.history_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Dados de Conexão'), findsOneWidget);
    expect(find.text('Tipo de Ligação'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Conexão MQTT'), findsOneWidget);
    expect(find.text('Formato da Telemetria'), findsOneWidget);
  });
}

