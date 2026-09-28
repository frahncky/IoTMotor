import 'package:flutter_test/flutter_test.dart';

import 'package:iotmotor/features/iot_motor/models/telemetry_history_entry.dart';
import 'package:iotmotor/features/iot_motor/models/telemetry_sample.dart';

final DateTime _t0 = DateTime(2026, 9, 28, 10);

TelemetryHistoryEntry _leitura(
  String placa,
  int minuto, {
  bool? ligado,
  String? modo,
}) => TelemetryHistoryEntry(
  deviceId: placa,
  sample: TelemetrySample(
    timestamp: _t0.add(Duration(minutes: minuto)),
    motorOn: ligado,
    mode: modo,
  ),
);

void main() {
  test('leituras repetidas não viram evento; só as mudanças', () {
    final List<HistoryEvent> eventos =
        historyEventsFrom(<TelemetryHistoryEntry>[
          _leitura('esp32-01', 0, ligado: false),
          _leitura('esp32-01', 1, ligado: false),
          _leitura('esp32-01', 2, ligado: true, modo: 'direta'),
          _leitura('esp32-01', 3, ligado: true, modo: 'direta'),
          _leitura('esp32-01', 4, ligado: true, modo: 'direta'),
          _leitura('esp32-01', 92, ligado: false),
          _leitura('esp32-01', 93, ligado: false),
        ], placaDoMotor: 'esp32-01');

    expect(eventos.map((HistoryEvent e) => e.kind), <HistoryEventKind>[
      HistoryEventKind.ligou,
      HistoryEventKind.desligou,
    ]);
    expect(eventos.first.mode, 'direta');
    expect(eventos.last.ligadoPor, const Duration(minutes: 90));
  });

  test('a primeira leitura só diz o estado: não é evento', () {
    final List<HistoryEvent> eventos =
        historyEventsFrom(<TelemetryHistoryEntry>[
          _leitura('esp32-01', 0, ligado: true),
          _leitura('esp32-01', 1, ligado: true),
          _leitura('esp32-01', 5, ligado: false),
        ], placaDoMotor: 'esp32-01');

    expect(eventos, hasLength(1));
    expect(eventos.single.kind, HistoryEventKind.desligou);
    // Não se sabe quando ligou: sem duração inventada.
    expect(eventos.single.ligadoPor, isNull);
  });

  test('as duas placas informando o mesmo motor não duplicam eventos', () {
    final List<HistoryEvent> eventos = historyEventsFrom(
      <TelemetryHistoryEntry>[
        _leitura('esp32-01', 0, ligado: false),
        _leitura('esp32-02', 0, ligado: false),
        _leitura('esp32-01', 1, ligado: true),
        // A placa de sensores ainda não percebeu a partida.
        _leitura('esp32-02', 1, ligado: false),
        _leitura('esp32-02', 2, ligado: true),
        _leitura('esp32-01', 2, ligado: true),
      ],
      placaDoMotor: 'esp32-01',
    );

    expect(eventos, hasLength(1));
    expect(eventos.single.kind, HistoryEventKind.ligou);
    expect(eventos.single.deviceId, 'esp32-01');
  });

  test('sem leituras do quadro, usa as da outra placa', () {
    final List<HistoryEvent> eventos = historyEventsFrom(
      <TelemetryHistoryEntry>[
        _leitura('esp32-02', 0, ligado: false),
        _leitura('esp32-02', 1, ligado: true),
      ],
      placaDoMotor: 'esp32-01',
    );

    expect(eventos.single.kind, HistoryEventKind.ligou);
  });

  test('troca de modo com o motor ligado vira evento', () {
    final List<HistoryEvent> eventos =
        historyEventsFrom(<TelemetryHistoryEntry>[
          _leitura('esp32-01', 0, ligado: false, modo: 'direta'),
          _leitura('esp32-01', 1, ligado: true, modo: 'direta'),
          _leitura('esp32-01', 2, ligado: true, modo: 'estrela'),
          _leitura('esp32-01', 3, ligado: true, modo: 'estrela'),
        ], placaDoMotor: 'esp32-01');

    expect(eventos.map((HistoryEvent e) => e.kind), <HistoryEventKind>[
      HistoryEventKind.ligou,
      HistoryEventKind.modo,
    ]);
    expect(eventos.last.mode, 'estrela');
  });

  test('o quadro de comando conta como ligado pelos contatores', () {
    TelemetrySample? ler(String json) =>
        TelemetrySample.tryParsePayload(json, timestamp: _t0);

    // Firmware atual do quadro: sem motor_on, só relays e motor_running.
    expect(
      ler(
        '{"voltage":220,"relays":[true,false,false,false],"motor_running":true}',
      )?.motorOn,
      isTrue,
    );
    expect(
      ler(
        '{"voltage":220,"relays":[false,false,false,false],"motor_running":false}',
      )?.motorOn,
      isFalse,
    );
    // Sem relays, vale o motor_running; motor_on, quando vem, manda.
    expect(ler('{"voltage":220,"motor_running":true}')?.motorOn, isTrue);
    expect(
      ler('{"motor_on":false,"relays":[true,false,false,false]}')?.motorOn,
      isFalse,
    );
  });

  test('gravação guarda as mudanças mesmo entre dois registros', () {
    // Registro a cada 30 s; o motor liga e desliga entre dois deles.
    final List<TelemetryHistoryEntry> origem = <TelemetryHistoryEntry>[
      for (int s = 0; s <= 60; s += 5)
        TelemetryHistoryEntry(
          deviceId: 'esp32-01',
          sample: TelemetrySample(
            timestamp: _t0.add(Duration(seconds: s)),
            motorOn: s >= 10 && s < 20,
          ),
        ),
    ];

    final List<TelemetryHistoryEntry> gravadas = historyEntriesToPersist(
      origem,
      recordMs: 30000,
    );

    expect(
      gravadas.map((TelemetryHistoryEntry e) => e.sample.timestamp.second),
      <int>[0, 10, 20, 50],
    );
    expect(
      historyEventsFrom(
        gravadas,
        placaDoMotor: 'esp32-01',
      ).map((HistoryEvent e) => e.kind),
      <HistoryEventKind>[HistoryEventKind.ligou, HistoryEventKind.desligou],
    );
  });
}
