import 'package:flutter_test/flutter_test.dart';

import 'package:iotmotor/features/iot_motor/models/motor_command_type.dart';
import 'package:iotmotor/features/iot_motor/view/widgets/motor_motion.dart';

void main() {
  test('mesmos números do painel web (motor-animation.js)', () {
    expect(visualDpsForRpm(null), closeTo(visualDpsForRpm(1750), 1e-9));
    expect(visualDpsForRpm(600), 540);
    expect(visualDpsForRpm(3600), 1260);
    expect(startupDurationFor(MotorStartKind.direct), 1.5);
    expect(startupDurationFor(MotorStartKind.sequenced), 2.2);
    expect(startupDurationFor(MotorStartKind.starDelta), 2.8);
    expect(startupSpeed(0.5, MotorStartKind.direct), 0.5);
    // Queda visual na comutação estrela-triângulo.
    expect(
      startupSpeed(0.61, MotorStartKind.starDelta),
      lessThan(startupSpeed(0.61, MotorStartKind.direct) * 0.9),
    );
    final MotionAppearance parado = motionAppearance(0);
    expect(parado.blurPx, 0);
    expect(parado.bladeOpacity, 1);
    final MotionAppearance regime = motionAppearance(1);
    expect(regime.blurPx, closeTo(1.15, 1e-9));
    expect(regime.markerOpacity, closeTo(0.28, 1e-9));
  });

  test('tipo de partida visual vem do perfil', () {
    expect(motorStartKindFor(MotorCommandType.directStart), MotorStartKind.direct);
  });

  test('parada por inércia: curva suave até zero, mais longa em regime', () {
    expect(coastDurationFor(1), closeTo(motorCoastSeconds, 1e-9));
    expect(coastDurationFor(0.01), closeTo(motorCoastSeconds * 0.28, 1e-9));
    const double total = motorCoastSeconds;
    final double meio = coastSpeed(1, total / 2, total);
    // Exponencial: perde mais da metade da velocidade na primeira metade.
    expect(meio, lessThan(0.5));
    expect(meio, greaterThan(0));
    expect(coastSpeed(1, total, total), 0);
  });

  test('parte, chega ao regime, desliga e para sozinho', () {
    final MotorMotion m = MotorMotion();
    for (int i = 0; i < 120; i++) {
      m.step(1 / 60, running: true, kind: MotorStartKind.direct, rpm: 1750);
    }
    expect(m.speed, 1);
    final double angulo = m.angle;
    m.step(1 / 60, running: true, kind: MotorStartKind.direct, rpm: 1750);
    expect(m.angle, isNot(angulo));

    bool precisaQuadros = true;
    int quadros = 0;
    while (precisaQuadros && quadros < 600) {
      precisaQuadros =
          m.step(1 / 60, running: false, kind: MotorStartKind.direct, rpm: 1750);
      quadros++;
    }
    expect(m.speed, 0);
    expect(precisaQuadros, isFalse);
    // ~3,6 s de inércia a 60 quadros por segundo.
    expect(quadros, inInclusiveRange(200, 230));
  });

  test('religar durante a parada continua da velocidade atual', () {
    final MotorMotion m = MotorMotion();
    for (int i = 0; i < 120; i++) {
      m.step(1 / 60, running: true, kind: MotorStartKind.starDelta);
    }
    for (int i = 0; i < 30; i++) {
      m.step(1 / 60, running: false, kind: MotorStartKind.starDelta);
    }
    final double antes = m.speed;
    expect(antes, inExclusiveRange(0.2, 1));
    m.step(1 / 60, running: true, kind: MotorStartKind.starDelta);
    expect(m.speed, closeTo(antes, 0.05));
  });

  test('halt e settle não deixam transição pendente', () {
    final MotorMotion m = MotorMotion()..settle(running: true);
    expect(m.speed, 1);
    m.halt();
    expect(m.speed, 0);
    expect(m.step(1 / 60, running: false, kind: MotorStartKind.direct), isFalse);
  });
}
