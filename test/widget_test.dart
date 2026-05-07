import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iotmotor/app/iot_motor_app.dart';

void main() {
  testWidgets('renderiza tabs de início, histórico e configurações', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MotorControlApp());
    await tester.pump(const Duration(milliseconds: 400));

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
    expect(find.byIcon(Icons.sensors_rounded), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.settings_rounded), findsNothing);

    await tester.tap(find.text('Mecânica'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Vibra'), findsOneWidget);
    expect(find.textContaining('Temperatura'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.history_outlined));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Histórico'), findsWidgets);
    expect(find.text('Dispositivo'), findsOneWidget);
    expect(find.text('Periodo'), findsOneWidget);
    expect(find.text('Ainda sem eventos no histórico.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Conexão MQTT'), findsOneWidget);
    expect(find.text('Alertas de Telemetria'), findsOneWidget);
    expect(find.text('Formato da Telemetria'), findsOneWidget);
  });
}
