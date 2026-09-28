import 'telemetry_sample.dart';

class TelemetryHistoryEntry {
  const TelemetryHistoryEntry({required this.deviceId, required this.sample});

  final String deviceId;
  final TelemetrySample sample;
}

/// O que aconteceu com o motor num ponto do histórico.
enum HistoryEventKind { ligou, desligou, modo }

/// Mudança de estado do motor, tirada das leituras gravadas.
class HistoryEvent {
  const HistoryEvent({
    required this.kind,
    required this.time,
    required this.deviceId,
    this.mode,
    this.ligadoPor,
  });

  final HistoryEventKind kind;
  final DateTime time;
  final String deviceId;

  /// Modo de partida informado pela placa (bruto, como no payload).
  final String? mode;

  /// Só em [HistoryEventKind.desligou]: quanto tempo ficou ligado.
  final Duration? ligadoPor;
}

/// Reduz as leituras às mudanças: ligou, desligou e troca de modo com o motor
/// ligado. Leituras que só repetem o estado anterior não viram evento.
///
/// As duas placas informam se o motor está ligado; para uma não desmentir a
/// outra (e repetir o evento), vale a [placaDoMotor] quando ela tem leituras
/// no conjunto. [entries] deve vir em ordem de tempo crescente.
List<HistoryEvent> historyEventsFrom(
  List<TelemetryHistoryEntry> entries, {
  required String placaDoMotor,
}) {
  final bool temPlacaDoMotor = entries.any(
    (TelemetryHistoryEntry e) =>
        e.deviceId == placaDoMotor && e.sample.motorOn != null,
  );
  final List<HistoryEvent> eventos = <HistoryEvent>[];
  bool? ligado;
  String? modo;
  DateTime? ligouEm;

  for (final TelemetryHistoryEntry entry in entries) {
    if (temPlacaDoMotor && entry.deviceId != placaDoMotor) continue;
    final bool? agora = entry.sample.motorOn;
    final String? modoAgora =
        (entry.sample.mode?.trim().isEmpty ?? true)
            ? null
            : entry.sample.mode!.trim();

    if (agora != null && agora != ligado) {
      // A primeira leitura só diz como o motor estava: não é evento.
      if (ligado != null) {
        eventos.add(
          HistoryEvent(
            kind: agora ? HistoryEventKind.ligou : HistoryEventKind.desligou,
            time: entry.sample.timestamp,
            deviceId: entry.deviceId,
            mode: agora ? (modoAgora ?? modo) : null,
            ligadoPor:
                agora || ligouEm == null
                    ? null
                    : entry.sample.timestamp.difference(ligouEm),
          ),
        );
      }
      ligouEm = agora && ligado != null ? entry.sample.timestamp : null;
      ligado = agora;
    } else if (ligado == true &&
        modoAgora != null &&
        modo != null &&
        modoAgora != modo) {
      eventos.add(
        HistoryEvent(
          kind: HistoryEventKind.modo,
          time: entry.sample.timestamp,
          deviceId: entry.deviceId,
          mode: modoAgora,
        ),
      );
    }
    if (modoAgora != null) modo = modoAgora;
  }
  return eventos;
}
