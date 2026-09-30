import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/models/motor_info.dart';
import 'package:iotmotor/features/iot_motor/models/telemetry_sample.dart';

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

  test('lê os dados complementares da placa do motor', () {
    final MotorInfo info = MotorInfo.tryParse(
      '{"frequency_hz":60,"power_factor":0.82,"efficiency_pct":91.7,'
      '"efficiency_class":"IE3","duty":"S1","insulation_class":"F",'
      '"ambient_temp_c":40,"temperature_rise_k":80,"ip_rating":"IP55",'
      '"manufacturer":"WEG","model":"W22","serial_number":"ABC123"}',
    )!;
    expect(info.frequencyHz, 60);
    expect(info.powerFactor, 0.82);
    expect(info.efficiencyPct, 91.7);
    expect(info.efficiencyClass, 'IE3');
    expect(info.duty, 'S1');
    expect(info.insulationClass, 'F');
    expect(info.ambientTempC, 40);
    expect(info.temperatureRiseK, 80);
    expect(info.ipRating, 'IP55');
    expect(info.manufacturer, 'WEG');
    expect(info.model, 'W22');
    expect(info.serialNumber, 'ABC123');
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
    // Dia do firmware antigo (sem "vib"): vibração em g fica de fora.
    expect(horas.first.vibrationAvg, isNull);
    expect(horas.first.minutesOn, 45);
    expect(horas.first.time.toUtc(), DateTime.utc(2024, 10, 4, 10));
    final BoardHistoryHour mms = BoardHistoryHour.parseDay(
      '{"day":20000,"v":1,"vib":"mm/s","hours":[[10,912,1034,2201,452,480,231,455,45]]}',
    ).single;
    expect(mms.vibrationAvg, 2.31);
    expect(mms.vibrationMax, 4.55);
  });

  test('vibração medida em mm/s: zona direta, sem precisar da rotação', () {
    expect(VibrationSeverity.zone(0.5, null)!.label, 'Boa');
    expect(VibrationSeverity.zone(2.3, 5)!.label, 'Alerta');
    expect(VibrationSeverity.zone(2.3, 50)!.label, 'Aceitável');
    expect(VibrationSeverity.zone(12, 500)!.label, 'Crítica');
    expect(VibrationSeverity.zone(double.nan, 5), isNull);
  });

  test('telemetria: só a vibração em mm/s; aceleração em g é ignorada', () {
    final TelemetrySample s = TelemetrySample.tryParsePayload(
      '{"device_id":"esp32-02","vibration":0.12,"vibration_mms":2.5}',
    )!;
    expect(s.vibration, 2.5);
    expect(s.toStoredMap().containsKey('vibration'), isFalse);
    expect(TelemetrySample.tryParsePayload('{"vibration":0.12}'), isNull);
    final TelemetrySample volta = TelemetrySample.fromStoredMap(s.toStoredMap())!;
    expect(volta.vibration, 2.5);
  });
}
