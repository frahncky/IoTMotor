import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iotmotor/app/iot_motor_app.dart';

Widget _buildTestApp() {
  return const ProviderScope(child: MotorControlApp());
}

void main() {
  testWidgets('renderiza tabs de início, histórico e configurações', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
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
    expect(find.text('Medi\u00e7\u00f5es'), findsOneWidget);
    expect(find.text('El\u00e9trica'), findsOneWidget);
    expect(find.text('Mec\u00e2nica'), findsOneWidget);
    expect(find.text('Aparente'), findsOneWidget);
    expect(find.text('Ativa'), findsOneWidget);
    expect(find.text('Reativa'), findsOneWidget);
    expect(find.text('Energia'), findsOneWidget);
    expect(find.text('Frequência'), findsOneWidget);
    expect(find.text('Vibração'), findsOneWidget);
    expect(find.text('Temperatura'), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsNothing);

    await tester.tap(find.text('El\u00e9trica'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Tens\u00e3o (V)'), findsOneWidget);
    expect(find.text('Corrente (A)'), findsOneWidget);
    expect(find.text('Pot\u00eancia'), findsNothing);
    expect(find.text('Energia'), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsAtLeastNWidgets(2));
    expect(find.byIcon(Icons.settings_rounded), findsNothing);

    await tester.tap(find.text('Tens\u00e3o (V)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ativa'), findsOneWidget);
    expect(find.text('Aparente'), findsOneWidget);
    expect(find.text('Reativa'), findsOneWidget);
    expect(find.text('Energia'), findsOneWidget);
    expect(find.text('FP'), findsOneWidget);
    expect(find.text('Frequência'), findsOneWidget);

    await tester.tap(find.text('Ativa'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ativa (W)'), findsOneWidget);

    await tester.tap(find.text('Mec\u00e2nica'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Vibração (mm/s)'), findsOneWidget);
    expect(find.text('Temperatura (\u00b0C)'), findsOneWidget);
    expect(find.text('Ativa (W)'), findsNothing);

    await tester.tap(find.text('Vibração (mm/s)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Temperatura'), findsOneWidget);
    expect(find.text('Pot\u00eancia'), findsNothing);

    await tester.tap(find.text('Temperatura'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Temperatura (\u00b0C)'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Medi\u00e7\u00f5es'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Aparente'), findsOneWidget);
    expect(find.text('Ativa'), findsOneWidget);
    expect(find.text('Reativa'), findsOneWidget);
    expect(find.text('Tens\u00e3o'), findsOneWidget);
    expect(find.text('Corrente'), findsOneWidget);
    expect(find.text('Energia'), findsOneWidget);
    expect(find.text('Frequência'), findsOneWidget);
    expect(find.text('Vibração'), findsOneWidget);
    expect(find.text('Temperatura'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.history_outlined));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Histórico'), findsWidgets);
    expect(find.text('Dispositivo'), findsOneWidget);
    expect(find.text('Período'), findsOneWidget);
    expect(find.text('Ainda sem eventos no histórico.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notification_important_outlined));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alertas'), findsWidgets);
    expect(find.text('Nenhum alerta registrado.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.widgetWithText(Tab, 'Conexão'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Motor'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Perfis'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Armazenamento'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Alertas'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Telemetria'), findsOneWidget);
    expect(find.text('Conexão MQTT'), findsOneWidget);
    expect(find.text('Broker host'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Motor'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Dados do motor'), findsOneWidget);
    expect(find.text('Editar dados do motor'), findsOneWidget);
    expect(find.text('Manutenção feita'), findsOneWidget);
    expect(find.text('Zerar horímetro e partidas'), findsOneWidget);
    expect(find.text('Som do motor'), findsOneWidget);
    expect(find.text('Testar som'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(Tab, 'Armazenamento'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(Icons.storage_rounded));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Local do app'), findsOneWidget);
    expect(find.text('Remoto no ESP32'), findsOneWidget);
    expect(find.text('Retenção local'), findsOneWidget);
    expect(find.text('Retenção remota (ESP32 SD)'), findsOneWidget);
    expect(find.text('Dias'), findsWidgets);
    expect(find.text('Meses'), findsWidgets);
    expect(find.text('Anos'), findsWidgets);
    expect(find.text('7 dias'), findsNothing);
    expect(find.text('90 dias'), findsNothing);
    expect(find.text('365 dias'), findsNothing);
    expect(find.text('Aplicar local'), findsOneWidget);
    expect(find.text('Aplicar no ESP32'), findsOneWidget);

    final TabBar settingsTabs =
        tester.widget<TabBar>(find.byType(TabBar));

    settingsTabs.onTap!(4);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Alertas de Telemetria'), findsOneWidget);

    settingsTabs.onTap!(5);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Formato da Telemetria'), findsOneWidget);
  });

  testWidgets('medições não estouram em tela estreita', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildTestApp());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Medi\u00e7\u00f5es'), findsOneWidget);
    expect(find.text('Aparente'), findsOneWidget);
    expect(find.text('Temperatura'), findsOneWidget);
  });
}
