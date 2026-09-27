import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iotmotor/features/iot_motor/services/alertas_da_bancada.dart';

const String sensores = 'iotmotor/esp32-02';

String lista() => jsonEncode(<String, dynamic>{
  'device_id': 'esp32-02',
  'alarms': <Map<String, dynamic>>[
    <String, dynamic>{'id': 'temp', 'field': 'temperature', 'board': 'sensors', 'above': true, 'limit': 60, 'on': true},
    <String, dynamic>{'id': 'a1', 'field': 'current', 'board': 'command', 'above': true, 'limit': 12.5, 'on': true},
  ],
});

String telemetria(List<String> disparados, {double temperatura = 55, bool monitorando = true}) =>
    jsonEncode(<String, dynamic>{
      'device_id': 'esp32-02',
      'temperature': temperatura,
      'alarm_enabled': monitorando,
      'alarms_firing': disparados,
    });

void main() {
  late DateTime relogio;
  late AlertasDaBancada alertas;

  setUp(() {
    relogio = DateTime(2026, 9, 27, 14, 30);
    alertas = AlertasDaBancada(agora: () => relogio);
    alertas.receber('$sensores/alarms', lista());
  });

  test('alarme que dispara avisa com som, com o limite e a leitura atual', () {
    expect(alertas.receber('$sensores/telemetry', telemetria(<String>[])), isEmpty);
    final List<AvisoDoCelular> avisos =
        alertas.receber('$sensores/telemetry', telemetria(<String>['temp'], temperatura: 65.3));
    expect(avisos, hasLength(1));
    expect(avisos.single.comSom, isTrue);
    expect(avisos.single.titulo, 'Alarme: Temperatura acima de 60 °C');
    expect(avisos.single.texto, 'Sensores do motor · às 14:30 · agora 65,3 °C');
  });

  test('enquanto continua disparado, não repete', () {
    alertas.receber('$sensores/telemetry', telemetria(<String>['temp']));
    expect(alertas.receber('$sensores/telemetry', telemetria(<String>['temp'])), isEmpty);
  });

  test('ao normalizar, atualiza a mesma notificação sem som', () {
    final AvisoDoCelular disparou = alertas.receber('$sensores/telemetry', telemetria(<String>['temp'])).single;
    relogio = relogio.add(const Duration(minutes: 3));
    final AvisoDoCelular voltou = alertas.receber('$sensores/telemetry', telemetria(<String>[])).single;
    expect(voltou.id, disparou.id);
    expect(voltou.comSom, isFalse);
    expect(voltou.titulo, 'Normalizado: Temperatura acima de 60 °C');
    expect(voltou.texto, contains('14:33'));
  });

  test('alarme oscilando no limite toca no máximo uma vez a cada 5 min', () {
    expect(alertas.receber('$sensores/telemetry', telemetria(<String>['temp'])).single.comSom, isTrue);
    alertas.receber('$sensores/telemetry', telemetria(<String>[]));
    relogio = relogio.add(const Duration(minutes: 1));
    expect(alertas.receber('$sensores/telemetry', telemetria(<String>['temp'])).single.comSom, isFalse);
    alertas.receber('$sensores/telemetry', telemetria(<String>[]));
    relogio = relogio.add(const Duration(minutes: 5));
    expect(alertas.receber('$sensores/telemetry', telemetria(<String>['temp'])).single.comSom, isTrue);
  });

  test('alarme elétrico usa a leitura do quadro de comando', () {
    alertas.receber('iotmotor/esp32-01/telemetry',
        jsonEncode(<String, dynamic>{'device_id': 'esp32-01', 'current': 13.2, 'relays': <bool>[true, false, false, false]}));
    final AvisoDoCelular aviso = alertas.receber('$sensores/telemetry', telemetria(<String>['a1'])).single;
    expect(aviso.titulo, 'Alarme: Corrente acima de 12,5 A');
    expect(aviso.texto, endsWith('agora 13,2 A'));
  });

  test('monitoramento da placa desligado: o celular fica quieto', () {
    expect(alertas.receber('$sensores/telemetry', telemetria(<String>['temp'], monitorando: false)), isEmpty);
  });

  test('alarme que não está na lista ainda avisa, pelo id', () {
    final AvisoDoCelular aviso = alertas.receber('$sensores/telemetry', telemetria(<String>['x9'])).single;
    expect(aviso.titulo, contains('x9'));
  });

  test('mensagem de outra placa no tópico, ou ilegível, é ignorada', () {
    expect(alertas.receber('$sensores/telemetry', '{"device_id":"esp32-09","alarms_firing":["temp"]}'), isEmpty);
    expect(alertas.receber('$sensores/telemetry', 'nao e json'), isEmpty);
    expect(alertas.receber('curto', '{}'), isEmpty);
  });

  test('ids de notificação são estáveis e ficam longe do serviço', () {
    expect(AlertasDaBancada.idDaNotificacao('esp32-02/temp'), AlertasDaBancada.idDaNotificacao('esp32-02/temp'));
    expect(AlertasDaBancada.idDaNotificacao('esp32-02/temp'), isNot(AlertasDaBancada.idDaNotificacao('esp32-02/vib')));
    expect(AlertasDaBancada.idDaNotificacao('esp32-02/temp'), greaterThanOrEqualTo(1000));
  });
}
