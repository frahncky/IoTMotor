import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/models/motor_info.dart';
import 'package:iotmotor/features/iot_motor/view/widgets/board_history_panel.dart';

// Índices na ordem dos botões do painel.
const int corrente = 0, temperatura = 1, tensao = 3, ligado = 4;

BoardHistoryHour hora(
  int h, {
  double? currentAvg,
  double? currentMax,
  double? temperatureAvg,
  double? temperatureMax,
  double? voltageAvg,
  int minutesOn = 0,
}) => BoardHistoryHour(
  time: DateTime.utc(2026, 9, 30, h),
  currentAvg: currentAvg,
  currentMax: currentMax,
  temperatureAvg: temperatureAvg,
  temperatureMax: temperatureMax,
  voltageAvg: voltageAvg,
  minutesOn: minutesOn,
);

List<TipoLegenda> tipos(List<BoardHistoryHour> horas, int grandeza) =>
    legendaDoHistorico(horas, grandeza).map((i) => i.tipo).toList();

void main() {
  // 10 h ligado 45 min; 11 h parado (sem corrente, com temperatura e tensão).
  final List<BoardHistoryHour> dia = <BoardHistoryHour>[
    hora(
      10,
      currentAvg: 9.12,
      currentMax: 10.34,
      temperatureAvg: 45.2,
      temperatureMax: 48,
      voltageAvg: 220.1,
      minutesOn: 45,
    ),
    hora(11, temperatureAvg: 40.1, temperatureMax: 41, voltageAvg: 221),
  ];

  test('legenda só com o que aparece no gráfico', () {
    expect(tipos(dia, corrente), <TipoLegenda>[TipoLegenda.ponto]);
    expect(tipos(dia, temperatura), <TipoLegenda>[
      TipoLegenda.media,
      TipoLegenda.maximo,
    ]);
    expect(tipos(dia, tensao), <TipoLegenda>[TipoLegenda.media]);
    expect(tipos(dia, ligado), <TipoLegenda>[TipoLegenda.barra]);
    expect(legendaDoHistorico(const <BoardHistoryHour>[], corrente), isEmpty);
  });

  test('corrente com zero e lacuna avisa os dois', () {
    final String textos = legendaDoHistorico(<BoardHistoryHour>[
      hora(6, currentAvg: 0, currentMax: 0, minutesOn: 1),
      hora(8, currentAvg: 3.5, currentMax: 3.8, minutesOn: 30),
      hora(9, currentAvg: 3.6, currentMax: 3.9, minutesOn: 40),
    ], corrente).map((i) => i.texto).join(' | ');
    expect(textos, contains('com o motor girando'));
    expect(textos, contains('Zero: motor marcado como ligado sem corrente'));
    expect(textos, contains('Espaço vazio: motor parado'));
  });
}
