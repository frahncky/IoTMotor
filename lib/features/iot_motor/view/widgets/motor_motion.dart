import 'dart:math' as math;

import '../../models/motor_command_type.dart';

/// Tipo de partida, do ponto de vista da animação.
///
/// Mesmos nomes e números de `dashboard-cloudflare/motor-animation.js`, para
/// o app e o painel web girarem igual.
enum MotorStartKind { direct, sequenced, starDelta }

/// Tipo de partida visual de um perfil de comando.
MotorStartKind motorStartKindFor(MotorCommandType type) {
  if (type.sequence) return MotorStartKind.starDelta;
  final List<ContactorTiming>? timings = type.timings;
  if (timings == null) return MotorStartKind.direct;
  final Set<int> onTimes = timings
      .where((ContactorTiming item) => item.use)
      .map((ContactorTiming item) => item.onMs)
      .toSet();
  final bool escalonada = onTimes.length > 1 ||
      timings.any((ContactorTiming item) => item.use && item.offMs > 0);
  return escalonada ? MotorStartKind.sequenced : MotorStartKind.direct;
}

double _clamp01(double v) => v.clamp(0.0, 1.0).toDouble();

double _smoothstep(double x) {
  final double v = _clamp01(x);
  return v * v * (3 - 2 * v);
}

/// Velocidade visual, em graus por segundo, para o RPM de placa.
///
/// A animação representa a rotação sem desenhar dezenas de voltas por
/// segundo: o RPM só escala a velocidade visual.
double visualDpsForRpm(double? rpm) {
  final double nominal = rpm != null && rpm.isFinite && rpm > 0 ? rpm : 1750;
  final double x = _clamp01((nominal - 600) / 3000);
  return 540 + 720 * math.pow(x, 0.72).toDouble();
}

/// Duração da partida visual, em segundos.
double startupDurationFor(MotorStartKind kind) {
  switch (kind) {
    case MotorStartKind.starDelta:
      return 2.8;
    case MotorStartKind.sequenced:
      return 2.2;
    case MotorStartKind.direct:
      return 1.5;
  }
}

/// Velocidade (0 a 1) no ponto [progress] da partida.
///
/// Direta: aceleração contínua. Escalonada/estrela-triângulo: pequena queda
/// visual na comutação, sem inventar uma parada do motor.
double startupSpeed(double progress, MotorStartKind kind) {
  final double x = _clamp01(progress);
  final double base = _smoothstep(x);
  if (kind == MotorStartKind.direct) return base;
  final bool estrela = kind == MotorStartKind.starDelta;
  final double centro = estrela ? 0.61 : 0.64;
  final double largura = estrela ? 0.055 : 0.075;
  final double profundidade = estrela ? 0.16 : 0.08;
  final double z = (x - centro) / largura;
  final double dip = profundidade * math.exp(-(z * z));
  return _clamp01(base * (1 - dip));
}

/// Tempo de inércia de referência (motor em regime), em segundos.
const double motorCoastSeconds = 3.6;

/// Duração da parada por inércia a partir da velocidade [from].
///
/// Um pouco mais longa quando o motor estava perto do regime, sem "cortar" a
/// rotação de forma digital.
double coastDurationFor(double from) =>
    motorCoastSeconds * math.max(0.28, math.pow(_clamp01(from), 0.72).toDouble());

/// Velocidade durante a parada, [elapsed] segundos depois de desligar.
double coastSpeed(double from, double elapsed, double total) {
  final double x = total > 0 ? elapsed / total : 1;
  if (x >= 1) return 0;
  const double k = 2.35;
  final double ease = (1 - math.exp(-k * x)) / (1 - math.exp(-k));
  return from * (1 - ease);
}

/// Borrão e transparência das pás conforme a velocidade.
class MotionAppearance {
  const MotionAppearance({
    required this.blurPx,
    required this.bladeOpacity,
    required this.markerOpacity,
  });

  final double blurPx;
  final double bladeOpacity;
  final double markerOpacity;
}

MotionAppearance motionAppearance(double speed) {
  final double fast = _clamp01((_clamp01(speed) - 0.48) / 0.52);
  return MotionAppearance(
    blurPx: 1.15 * fast,
    bladeOpacity: 1 - 0.38 * fast,
    markerOpacity: 1 - 0.72 * fast,
  );
}

/// Estado mecânico da animação: ângulo do eixo e velocidade relativa.
///
/// Ventoinha, rotor e ponta do eixo são solidários: todos usam o mesmo ângulo.
class MotorMotion {
  double angle = 0;
  double speed = 0;
  double _progress = 0;
  double? _coastFrom;
  double _coastElapsed = 0;
  double _coastTotal = 0;
  bool _wasRunning = false;

  /// `true` enquanto ainda há movimento a desenhar.
  bool get moving => speed > 0;

  /// Avança [elapsed] segundos. Devolve `true` se ainda precisa de quadros.
  bool step(
    double elapsed, {
    required bool running,
    required MotorStartKind kind,
    double? rpm,
  }) {
    final double e = math.max(0.0, elapsed);
    // Um quadro atrasado não deve dar um salto no ângulo.
    final double dt = math.min(0.064, e);

    if (running) {
      if (!_wasRunning) _progress = _progressFor(speed, kind);
      _coastFrom = null;
      _progress = math.min(1.0, _progress + e / startupDurationFor(kind));
      speed = startupSpeed(_progress, kind);
    } else if (speed > 0) {
      if (_coastFrom == null) {
        _coastFrom = speed;
        _coastElapsed = 0;
        _coastTotal = coastDurationFor(speed);
      }
      _coastElapsed += e;
      speed = coastSpeed(_coastFrom!, _coastElapsed, _coastTotal);
      if (speed == 0) {
        _progress = 0;
        _coastFrom = null;
      }
    }
    _wasRunning = running;

    if (speed > 0) {
      angle = (angle + visualDpsForRpm(rpm) * speed * dt) % 360;
    }
    return running || speed > 0;
  }

  /// Para na hora (sem telemetria ao vivo, não animamos o último estado).
  void halt() {
    speed = 0;
    _progress = 0;
    _coastFrom = null;
    _wasRunning = false;
  }

  /// Vai direto ao estado final, sem transição (movimento reduzido).
  void settle({required bool running}) {
    speed = running ? 1 : 0;
    _progress = running ? 1 : 0;
    _coastFrom = null;
    _wasRunning = running;
  }

  /// Ponto da partida em que a velocidade vale [value]: religar durante a
  /// parada continua de onde o motor está, sem voltar ao zero.
  static double _progressFor(double value, MotorStartKind kind) {
    double lo = 0, hi = 1;
    for (int i = 0; i < 24; i += 1) {
      final double mid = (lo + hi) / 2;
      if (startupSpeed(mid, kind) < value) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }
}
