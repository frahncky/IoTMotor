import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iotmotor/features/iot_motor/controller/motor_control_controller.dart';
import 'package:iotmotor/features/iot_motor/models/motor_command_type.dart';
import 'package:iotmotor/features/iot_motor/models/mqtt_connection_config.dart';
import 'package:iotmotor/features/iot_motor/services/motor_animation_prefs.dart';
import 'package:iotmotor/features/iot_motor/services/mqtt_motor_service.dart';
import 'package:iotmotor/features/iot_motor/view/widgets/motor_animation_card.dart';

/// Efeitos do desenho escolhidos em Configurações › Motor › Animação do motor.
void main() {
  // Com uma conexao ativa (servico falso), como no app: so assim a
  // telemetria da placa de sensores entra no controlador.
  MotorControlController motorGirando({double? vibracaoMmS}) {
    final _ServicoFalso servico = _ServicoFalso();
    final MotorControlController c = MotorControlController(
      service: servico,
      loadSettings: false,
    )..isConnected = true;
    servico.emitir(
      'iotmotor/esp32-01/telemetry',
      '{"device_id":"esp32-01","relays":[true,false,false,false],"motor_running":true}',
    );
    if (vibracaoMmS != null) {
      servico.emitir(
        'iotmotor/esp32-02/telemetry',
        '{"device_id":"esp32-02","vibration_mms":$vibracaoMmS,"mpu_ok":true,"motor_on":true}',
      );
    }
    return c;
  }

  Future<void> mostrar(
    WidgetTester tester,
    MotorControlController c,
    MotorAnimationEffects efeitos,
  ) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MotorAnimationCard(
          controller: c,
          startType: MotorCommandType.directStart,
          efeitos: efeitos,
        ),
      ),
    ),
  );

  testWidgets('sem giro, o motor ligado aparece parado e o cartão dorme', (
    WidgetTester tester,
  ) async {
    final MotorControlController c = motorGirando();
    await mostrar(tester, c, const MotorAnimationEffects(giro: false));
    await tester.pumpAndSettle(); // Termina: nada pede quadros.
    expect(find.text('Motor ligado'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('vibração crítica faz o desenho tremer, mesmo sem giro', (
    WidgetTester tester,
  ) async {
    final MotorControlController c = motorGirando(vibracaoMmS: 6);
    await mostrar(tester, c, const MotorAnimationEffects(giro: false));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'tremendo');

    // Com o tremor desligado, volta a dormir.
    await mostrar(
      tester,
      c,
      const MotorAnimationEffects(giro: false, tremor: false),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('vibração aceitável não treme', (WidgetTester tester) async {
    final MotorControlController c = motorGirando(vibracaoMmS: 1.2);
    await mostrar(tester, c, const MotorAnimationEffects(giro: false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  test('a escolha fica guardada no aparelho', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final MotorAnimationPrefs a = MotorAnimationPrefs();
    await Future<void>.delayed(Duration.zero);
    expect(a.efeitos, const MotorAnimationEffects());
    await a.set(a.efeitos.copyWith(tremor: false, calor: false));

    final MotorAnimationPrefs b = MotorAnimationPrefs();
    await Future<void>.delayed(Duration.zero);
    expect(b.efeitos, const MotorAnimationEffects(tremor: false, calor: false));
  });
}

class _ServicoFalso extends MqttMotorService {
  @override
  MqttConnectionConfig? get activeConfig => const MqttConnectionConfig(
    host: 'broker',
    port: 1883,
    clientId: 't',
    topicPrefix: 'iotmotor',
    deviceId: 'auto',
    useTls: false,
  );

  void emitir(String topico, String dados) => onPayload?.call(topico, dados);

  @override
  Future<void> disconnect({bool silent = false}) async {}
}
