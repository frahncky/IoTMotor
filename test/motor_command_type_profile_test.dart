import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/models/motor_command_type.dart';

void main() {
  test('partidas padrão usam os mesmos contatores da página', () {
    expect(MotorCommandType.directStart.sequence, isFalse);
    expect(MotorCommandType.directStart.mask, 1);
    expect(MotorCommandType.starDeltaStart.sequence, isTrue);
    expect(
      <int>[
        MotorCommandType.starDeltaStart.main,
        MotorCommandType.starDeltaStart.star,
        MotorCommandType.starDeltaStart.delta,
        MotorCommandType.starDeltaStart.seconds,
      ],
      <int>[1, 2, 3, 5],
    );
  });

  test('direta aceita qualquer combinação de CNT 1 a CNT 4', () {
    final MotorCommandType tipo = MotorCommandType.start(
      id: 'x',
      label: 'Direta 1 e 4',
      mode: 'direta_1_4',
      sequence: false,
      mask: 0x9,
    );
    expect(tipo.profileIsValid, isTrue);
    expect(tipo.profileSummary, 'Direta: CNT 1 + CNT 4');
    expect(tipo.copyAsStart(label: 'x', mode: 'x', mask: 0).profileIsValid, isFalse);
  });

  test('estrela-triângulo exige contatores distintos e 2 a 30 s', () {
    MotorCommandType perfil({int main = 2, int star = 3, int delta = 4, int s = 8}) =>
        MotorCommandType.start(
          id: 'y',
          label: 'ET',
          mode: 'et',
          sequence: true,
          main: main,
          star: star,
          delta: delta,
          seconds: s,
        );
    expect(perfil().profileIsValid, isTrue);
    expect(perfil().profileSummary, contains('principal CNT 2'));
    expect(perfil(star: 2).profileIsValid, isFalse);
    expect(perfil(s: 1).profileIsValid, isFalse);
    expect(perfil(s: 31).profileIsValid, isFalse);
  });

  test('modo antigo com "star" continua virando estrela-triângulo', () {
    expect(
      MotorCommandType.start(id: 'z', label: 'Antiga', mode: 'star_delta').sequence,
      isTrue,
    );
    expect(
      MotorCommandType.start(id: 'w', label: 'Soft', mode: 'soft_starter').sequence,
      isFalse,
    );
  });
}
