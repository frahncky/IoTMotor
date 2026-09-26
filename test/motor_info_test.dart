import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/models/motor_info.dart';

void main() {
  test('dupla tensão: corrente e tensão da ligação em uso', () {
    final MotorInfo info = MotorInfo.tryParse(
      '{"voltage_v":220,"voltage_y_v":380,"current_a":12.6,"current_y_a":7.3,"phases":3,"connection":"star","rpm":1730}',
    )!;
    expect(info.currentInUse, 7.3);
    expect(info.voltageInUse, 380);
    expect(info.connectionLabel, 'estrela');
    expect(motorLoad(3.65, info.currentInUse), 50);
  });

  test('uso e manutenção, com os mesmos textos do painel', () {
    final MotorUsage uso = MotorUsage.fromMap(<String, dynamic>{
      'run_s_total': 3600 * 1950,
      'starts_today': 3,
      'session_s': 725,
    })!;
    expect(usageLine(uso), 'Ligado há 12 min · Horímetro 1950,0 h · 3 partidas hoje');
    const MotorInfo info = MotorInfo(maintIntervalH: 2000, maintDoneRunS: 0);
    final MaintenanceStatus perto = MaintenanceStatus.of(info, uso.runSTotal)!;
    expect(perto.perto, isTrue);
    expect(perto.texto, 'Próxima manutenção em 50 h de uso (a cada 2000 h)');
    expect(MaintenanceStatus.of(info, 3600 * 2100.5)!.vencida, isTrue);
    expect(MaintenanceStatus.of(const MotorInfo(), 100), isNull);
  });

  test('vibração pela ISO 10816 igual ao painel', () {
    expect(VibrationSeverity.of(0.01, 1800, 5)!.label, 'Boa');
    expect(VibrationSeverity.of(0.05, 1800, 5)!.label, 'Alerta');
    expect(VibrationSeverity.of(0.05, 1800, 50)!.label, 'Aceitável');
    expect(VibrationSeverity.of(0.1, 1800, 5)!.label, 'Crítica');
    expect(VibrationSeverity.of(0.01, null, 5), isNull);
  });

  test('firmware: em dia, desatualizado ou sem versão', () {
    expect(firmwareSituation(firmwarePublicado[0], firmwarePublicado[0]).atualizar, isFalse);
    expect(firmwareSituation('v11', firmwarePublicado[0]).atualizar, isTrue);
    expect(firmwareSituation(null, firmwarePublicado[0]).atualizar, isTrue);
  });

  test('histórico da placa: escalas e horas inválidas', () {
    final List<BoardHistoryHour> horas = BoardHistoryHour.parseDay(
      '{"device_id":"esp32-02","day":20000,"v":1,"hours":[[10,912,1034,2201,452,480,31,55,45],[30,1,1,1,1,1,1,1,1]]}',
    );
    expect(horas, hasLength(1));
    expect(horas.first.currentAvg, 9.12);
    expect(horas.first.temperatureMax, 48);
    expect(horas.first.vibrationAvg, 0.031);
    expect(horas.first.minutesOn, 45);
    expect(horas.first.time.toUtc(), DateTime.utc(2024, 10, 4, 10));
  });
}
