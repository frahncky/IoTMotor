import 'dart:convert';
import 'dart:math' as math;

/// Versão do firmware publicada para OTA (release firmware-latest), a mesma que
/// o painel usa (FIRMWARE_PUBLICADO em wifi-manager.js): [quadro, sensores].
/// O CI confere que é a mesma do firmware_version de cada .ino.
const List<String> firmwarePublicado = <String>['v16-desarme', 's3-sensors-1.8-desarme'];

double? _numero(Object? valor) =>
    valor is num && valor.isFinite ? valor.toDouble() : null;

/// Dados de placa do motor, gravados no quadro de comando (tópico retido
/// `motor_info`) pelo painel. Tudo opcional.
class MotorInfo {
  const MotorInfo({
    this.powerCv,
    this.voltageV,
    this.currentA,
    this.voltageYV,
    this.currentYA,
    this.star = false,
    this.serviceFactor,
    this.rpm,
    this.phases,
    this.maintIntervalH,
    this.maintDoneRunS,
    this.maintDoneUtc,
  });

  final double? powerCv;
  final double? voltageV;
  final double? currentA;

  /// Trifásico de dupla tensão: valores da estrela (os de cima são do triângulo).
  final double? voltageYV;
  final double? currentYA;

  /// Ligação em uso: estrela (true) ou triângulo.
  final bool star;
  final double? serviceFactor;
  final double? rpm;
  final int? phases;
  final double? maintIntervalH;
  final double? maintDoneRunS;
  final double? maintDoneUtc;

  static MotorInfo? tryParse(String payload) {
    try {
      final Object? dados = jsonDecode(payload);
      if (dados is! Map<String, dynamic>) return null;
      final Object? fases = dados['phases'];
      return MotorInfo(
        powerCv: _numero(dados['power_cv']),
        voltageV: _numero(dados['voltage_v']),
        currentA: _numero(dados['current_a']),
        voltageYV: _numero(dados['voltage_y_v']),
        currentYA: _numero(dados['current_y_a']),
        star: dados['connection'] == 'star',
        serviceFactor: _numero(dados['service_factor']),
        rpm: _numero(dados['rpm']),
        phases: fases == 1 || fases == 3 ? fases as int : null,
        maintIntervalH: _numero(dados['maint_interval_h']),
        maintDoneRunS: _numero(dados['maint_done_run_s']),
        maintDoneUtc: _numero(dados['maint_done_utc']),
      );
    } catch (_) {
      return null;
    }
  }

  bool get dualVoltage => currentYA != null || voltageYV != null;

  /// Corrente e tensão da ligação em que o motor trabalha: é com elas que se
  /// calcula a carga.
  double? get currentInUse => star && currentYA != null ? currentYA : currentA;
  double? get voltageInUse => star && voltageYV != null ? voltageYV : voltageV;

  String? get connectionLabel =>
      dualVoltage ? (star ? 'estrela' : 'triângulo') : null;
}

/// Horímetro e partidas publicados na telemetria do quadro de comando.
class MotorUsage {
  const MotorUsage({
    this.runSTotal,
    this.startsTotal,
    this.startsToday,
    this.startsHour,
    this.sessionS,
  });

  final double? runSTotal;
  final double? startsTotal;
  final double? startsToday;
  final double? startsHour;
  final double? sessionS;

  static MotorUsage? fromMap(Map<String, dynamic> dados) {
    final MotorUsage uso = MotorUsage(
      runSTotal: _numero(dados['run_s_total']),
      startsTotal: _numero(dados['starts_total']),
      startsToday: _numero(dados['starts_today']),
      startsHour: _numero(dados['starts_hour']),
      sessionS: _numero(dados['session_s']),
    );
    return uso.runSTotal == null && uso.startsTotal == null ? null : uso;
  }
}

/// Carga do motor em % da corrente nominal; null sem cadastro.
int? motorLoad(double? corrente, double? nominal) {
  if (corrente == null || nominal == null || nominal <= 0) return null;
  return (corrente / nominal * 100).round();
}

String duracao(double segundos) {
  final int s = math.max(0, segundos.floor());
  if (s < 60) return '$s s';
  final int m = s ~/ 60;
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min';
}

String _decimal(double v, int casas) => v.toStringAsFixed(casas).replaceAll('.', ',');

/// Linha de uso: sessão, horímetro e partidas (mesmo texto do painel).
String usageLine(MotorUsage uso) {
  final List<String> partes = <String>[];
  if (uso.sessionS != null) partes.add('Ligado há ${duracao(uso.sessionS!)}');
  if (uso.runSTotal != null) partes.add('Horímetro ${_decimal(uso.runSTotal! / 3600, 1)} h');
  final double? partidas = uso.startsToday ?? uso.startsTotal;
  if (partidas != null) {
    final int n = partidas.round();
    partes.add('$n ${n == 1 ? 'partida' : 'partidas'} ${uso.startsToday != null ? 'hoje' : 'no total'}');
  }
  return partes.join(' · ');
}

/// Manutenção pelo horímetro: horas de uso desde a última contra o intervalo.
class MaintenanceStatus {
  const MaintenanceStatus({required this.intervaloH, required this.restanteH});

  final double intervaloH;
  final double restanteH;

  bool get vencida => restanteH <= 0;
  bool get perto => restanteH > 0 && restanteH <= intervaloH * 0.1;

  static MaintenanceStatus? of(MotorInfo? info, double? runSTotal) {
    final double? intervalo = info?.maintIntervalH;
    if (intervalo == null || intervalo <= 0 || runSTotal == null) return null;
    final double feitaEm = info?.maintDoneRunS ?? 0;
    return MaintenanceStatus(
      intervaloH: intervalo,
      restanteH: intervalo - math.max(0, runSTotal - feitaEm) / 3600,
    );
  }

  static String _horas(double h) =>
      '${h >= 10 ? h.round().toString() : _decimal(h, 1)} h';

  String get texto =>
      vencida
          ? 'Manutenção vencida há ${_horas(-restanteH)} de uso (a cada ${intervaloH.round()} h)'
          : 'Próxima manutenção em ${_horas(restanteH)} de uso (a cada ${intervaloH.round()} h)';
}

/// Severidade da vibração pela ISO 10816, com a velocidade estimada da
/// aceleração RMS na rotação do motor (mesma conta do painel).
class VibrationSeverity {
  const VibrationSeverity(this.mmS, this.zona);

  final double mmS;
  final int zona;

  static const List<String> _nomes = <String>['Boa', 'Aceitável', 'Alerta', 'Crítica'];
  static const List<(double, List<double>)> _classes = <(double, List<double>)>[
    (15, <double>[0.71, 1.8, 4.5]),
    (75, <double>[1.12, 2.8, 7.1]),
    (double.infinity, <double>[1.8, 4.5, 11.2]),
  ];

  String get label => _nomes[zona];

  static VibrationSeverity? of(double? rmsG, double? rpm, double? powerCv) {
    if (rmsG == null || rmsG < 0 || rpm == null || rpm <= 0) return null;
    final double mmS = rmsG * 9806.65 / (2 * math.pi * rpm / 60);
    final double kw = powerCv != null && powerCv > 0 ? powerCv * 0.7355 : 0;
    final List<double> zonas = _classes.firstWhere(((double, List<double>) c) => kw <= c.$1).$2;
    final int indice = zonas.indexWhere((double limite) => mmS < limite);
    return VibrationSeverity(mmS, indice < 0 ? 3 : indice);
  }
}

/// O que dizer sobre a versão do firmware de uma placa.
({String texto, bool atualizar}) firmwareSituation(String? instalado, String publicado) {
  if (instalado == null || instalado.isEmpty) {
    return (texto: 'a placa não informou a versão (firmware antigo?)', atualizar: true);
  }
  if (instalado == publicado) return (texto: '$instalado · em dia', atualizar: false);
  return (texto: '$instalado · nova versão publicada: $publicado', atualizar: true);
}

/// Uma hora do histórico guardado na placa de sensores (historico.h).
class BoardHistoryHour {
  const BoardHistoryHour({
    required this.time,
    this.currentAvg,
    this.currentMax,
    this.voltageAvg,
    this.temperatureAvg,
    this.temperatureMax,
    this.vibrationAvg,
    this.vibrationMax,
    this.minutesOn = 0,
  });

  final DateTime time;
  final double? currentAvg;
  final double? currentMax;
  final double? voltageAvg;
  final double? temperatureAvg;
  final double? temperatureMax;
  final double? vibrationAvg;
  final double? vibrationMax;
  final int minutesOn;

  /// Um dia publicado em `<prefixo>/<sensores>/history/<0..6>`.
  static List<BoardHistoryHour> parseDay(String payload) {
    try {
      final Object? dados = jsonDecode(payload);
      if (dados is! Map<String, dynamic>) return const <BoardHistoryHour>[];
      final Object? dia = dados['day'];
      final Object? horas = dados['hours'];
      if (dia is! int || dia <= 0 || horas is! List) return const <BoardHistoryHour>[];
      final List<BoardHistoryHour> saida = <BoardHistoryHour>[];
      for (final Object? linha in horas) {
        if (linha is! List || linha.length < 9) continue;
        final Object? h = linha[0];
        if (h is! int || h < 0 || h > 23) continue;
        double? v(int i, double escala) {
          final double? n = _numero(linha[i]);
          return n == null ? null : n / escala;
        }
        saida.add(BoardHistoryHour(
          time: DateTime.fromMillisecondsSinceEpoch((dia * 24 + h) * 3600000, isUtc: true).toLocal(),
          currentAvg: v(1, 100),
          currentMax: v(2, 100),
          voltageAvg: v(3, 10),
          temperatureAvg: v(4, 10),
          temperatureMax: v(5, 10),
          vibrationAvg: v(6, 1000),
          vibrationMax: v(7, 1000),
          minutesOn: (_numero(linha[8]) ?? 0).round(),
        ));
      }
      return saida;
    } catch (_) {
      return const <BoardHistoryHour>[];
    }
  }
}
