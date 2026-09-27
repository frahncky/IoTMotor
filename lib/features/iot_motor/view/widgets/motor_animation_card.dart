import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/motor_command_type.dart';
import '../../models/board_alarm.dart';
import '../../models/motor_info.dart';
import 'glass_panel.dart';
import 'motor_motion.dart';
import 'motor_usage_strip.dart';

/// Representação vetorial nativa do motor para a tela Início.
///
/// Não comanda a bancada. A rotação acompanha somente o estado confirmado
/// pelos contatores do ESP32-01. RPM e temperatura vêm dos dados já recebidos
/// pelo app; não há deslocamento visual por vibração.
///
/// O desenho e o movimento são os mesmos do painel web
/// (`dashboard-cloudflare/motor-animation.js`). Com o motor parado e sem
/// alarme piscando o ticker dorme: nada é redesenhado.
class MotorAnimationCard extends StatefulWidget {
  const MotorAnimationCard({
    super.key,
    required this.controller,
    required this.startType,
  });

  final MotorControlController controller;
  final MotorCommandType startType;

  @override
  State<MotorAnimationCard> createState() => _MotorAnimationCardState();
}

class _MotorAnimationCardState extends State<MotorAnimationCard>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final MotorMotion _motion = MotorMotion();

  /// Avisa o desenho de um novo quadro sem reconstruir o cartão.
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  Duration _lastElapsed = Duration.zero;
  double _blinkSeconds = 0;
  bool _reduceMotion = false;
  String? _shownStatus;

  /// Reavalia o alarme a cada segundo enquanto ele existe: sem telemetria
  /// nova ele envelhece e some, mesmo sem aviso do controller.
  Timer? _alarmCheck;
  bool _alarmShown = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant MotorAnimationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    _sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _alarmCheck?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  bool get _connected => widget.controller.isConnected;
  bool get _running => _connected && widget.controller.isMotorRunning;

  _AlarmParts get _alarms =>
      _connected ? _AlarmParts.of(widget.controller) : const _AlarmParts();

  void _onControllerChanged() {
    if (!mounted) return;
    _sync();
    setState(() {});
  }

  /// Ajusta o movimento ao estado da bancada e liga/desliga o ticker.
  void _sync() {
    final bool running = _running;
    _alarmShown = _alarms.any;
    if (_alarmShown) {
      _alarmCheck ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _alarms.any != _alarmShown) _onControllerChanged();
      });
    } else {
      _alarmCheck?.cancel();
      _alarmCheck = null;
    }
    if (!_connected) {
      // Sem telemetria ao vivo, não animamos o último estado conhecido.
      _motion.halt();
    } else if (_reduceMotion) {
      _motion.settle(running: running);
    }
    final bool needsFrames = _connected &&
        !_reduceMotion &&
        (running || _motion.moving || _alarms.blinks);
    if (needsFrames && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    } else if (!needsFrames && _ticker.isActive) {
      _ticker.stop();
    }
    _frame.value++;
  }

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    final bool running = _running;
    _motion.step(
      dt,
      running: running,
      kind: motorStartKindFor(widget.startType),
      rpm: widget.controller.motorInfo?.rpm,
    );
    _blinkSeconds = (_blinkSeconds + dt) % 1;
    _frame.value++;

    if (_statusText() != _shownStatus) setState(() {});
    if (!running && !_motion.moving && !_alarms.blinks) _ticker.stop();
  }

  String _statusText() {
    if (!_connected) return 'Desconectado';
    if (_running) {
      return _motion.speed < 0.95 ? 'Motor partindo' : 'Motor ligado';
    }
    return _motion.speed > 0.03 ? 'Motor desacelerando' : 'Motor desligado';
  }

  /// Opacidade do ícone de alarme: 1 → 0,4 → 1 a cada segundo.
  double get _blinkOpacity {
    if (_reduceMotion) return 1;
    return 0.7 + 0.3 * math.cos(_blinkSeconds * 2 * math.pi);
  }

  @override
  Widget build(BuildContext context) {
    final bool connected = _connected;
    final bool running = _running;
    final MotorInfo? info = widget.controller.motorInfo;
    final double? temperature = widget.controller.latestSample?.temperature;
    final double rpm = info?.rpm ?? 1750;
    final String? desarme = widget.controller.desarmeCampo;
    final _AlarmParts alarms = _alarms;
    final String status = _shownStatus = _statusText();
    final double? heat = motorHeat(
      temperature,
      temperatureLimit(widget.controller.boardAlarms),
    );

    final List<String> falaDesenho = <String>[
      status,
      if (alarms.temperature) 'alarme de temperatura',
      if (alarms.vibration) 'alarme de vibração',
      if (alarms.other) 'outro alarme ativo',
    ];

    return SizedBox(
      width: double.infinity,
      child: GlassPanel(
        tint: alarms.any
            ? AppTheme.danger
            : running
                ? AppTheme.online
                : connected
                    ? AppTheme.brandBlue
                    : AppTheme.offline,
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compact = constraints.maxWidth < 600;
            final Widget drawing = Semantics(
              image: true,
              label: 'Desenho do motor: ${falaDesenho.join(', ')}',
              child: RepaintBoundary(
                child: SizedBox(
                  width: compact ? 150 : 210,
                  height: compact ? 86 : 120,
                  child: CustomPaint(
                    key: const ValueKey<String>('motor_animation_paint'),
                    painter: _MotorPainter(
                      repaint: _frame,
                      motion: _motion,
                      blinkOpacity: () => _blinkOpacity,
                      heat: heat,
                      alarmTemperature: alarms.temperature,
                      alarmVibration: alarms.vibration,
                      dimmed: !connected,
                      motionBlur: !_reduceMotion,
                    ),
                  ),
                ),
              ),
            );

            final Widget details = Column(
              crossAxisAlignment:
                  compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: running
                            ? AppTheme.online
                            : connected
                                ? AppTheme.labelSoft
                                : AppTheme.offline,
                        boxShadow: running
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: AppTheme.online.withValues(alpha: 0.35),
                                  blurRadius: 7,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        status,
                        key: const ValueKey<String>('motor_animation_status'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Desarme automático: por que o motor parou.
                if (desarme != null && connected && !running)
                  Text(
                    'Desligado pelo alarme de ${(alarmQuantityFor(desarme)?.label ?? desarme).toLowerCase().replaceAll(' (rms)', '')}',
                    key: const ValueKey<String>('motor_desarme'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  'Rotação de placa: ${rpm.round()} rpm',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (temperature != null)
                  Text(
                    'Temperatura: ${temperature.toStringAsFixed(1).replaceAll('.', ',')} °C',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            );

            final Widget uso = MotorUsageStrip(controller: widget.controller);

            if (compact) {
              // Em tela estreita, carga e avisos vão numa linha própria,
              // embaixo do desenho, ainda dentro do cartão.
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      drawing,
                      const SizedBox(width: 12),
                      Expanded(child: details),
                    ],
                  ),
                  uso,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                drawing,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      details,
                      uso,
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Aquecimento de 0 a 1 entre ~30 °C e o limite do alarme de temperatura.
///
/// Mesma regra de `motorHeat` no painel web; `null` sem leitura.
double? motorHeat(double? temperature, double limit) {
  if (temperature == null || !temperature.isFinite) return null;
  final double top = limit.isFinite && limit > 0 ? limit : 60;
  final double base = math.min(30, top - 10);
  return ((temperature - base) / (top - base)).clamp(0.0, 1.0).toDouble();
}

/// Menor limite "acima de" dos alarmes de temperatura ligados; 60 °C sem lista.
double temperatureLimit(List<BoardAlarm> alarms) {
  double? menor;
  for (final BoardAlarm a in alarms) {
    if (a.field != 'temperature' || !a.above || !a.enabled || !a.limit.isFinite) {
      continue;
    }
    menor = menor == null ? a.limit : math.min(menor, a.limit);
  }
  return menor ?? 60;
}

/// Partes do motor com alarme disparado agora, segundo a placa.
///
/// Temperatura e vibração ganham ícone no desenho; os demais (corrente,
/// tensão, potência...) só acendem o cartão, como `other` no painel web.
class _AlarmParts {
  const _AlarmParts({
    this.temperature = false,
    this.vibration = false,
    this.other = false,
  });

  factory _AlarmParts.of(MotorControlController controller) {
    bool temperatura = false, vibracao = false, outro = false;
    for (final String id in controller.liveFiringAlarmIds) {
      String field = id == 'temp'
          ? 'temperature'
          : id == 'vib'
              ? 'vibration_mms'
              : '';
      for (final BoardAlarm a in controller.boardAlarms) {
        if (a.id == id) field = a.field;
      }
      if (field == 'temperature') {
        temperatura = true;
      } else if (field.startsWith('vibration')) {
        vibracao = true;
      } else {
        outro = true;
      }
    }
    return _AlarmParts(temperature: temperatura, vibration: vibracao, other: outro);
  }

  final bool temperature;
  final bool vibration;
  final bool other;
  bool get any => temperature || vibration || other;

  /// Só temperatura e vibração piscam no desenho.
  bool get blinks => temperature || vibration;
}

/// Cor do aquecimento: laranja morno até vermelho.
Color _heatColor(double heat) =>
    Color.lerp(const Color(0xFFF5A524), const Color(0xFFE5484D), heat)!;

/// Desenho do motor. Coordenadas do SVG do painel web (760 x 430).
class _MotorPainter extends CustomPainter {
  _MotorPainter({
    required Listenable repaint,
    required this.motion,
    required this.blinkOpacity,
    required this.heat,
    required this.alarmTemperature,
    required this.alarmVibration,
    required this.dimmed,
    required this.motionBlur,
  }) : super(repaint: repaint);

  final MotorMotion motion;
  final double Function() blinkOpacity;
  final double? heat;
  final bool alarmTemperature;
  final bool alarmVibration;
  final bool dimmed;
  final bool motionBlur;

  static const double _w = 760, _h = 430;

  static const LinearGradient _rear = LinearGradient(
    colors: <Color>[Color(0xFF173F52), Color(0xFF2A7793), Color(0xFF0C3042)],
    stops: <double>[0, .55, 1],
  );
  static const LinearGradient _body = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF2D7D9B), Color(0xFF16556F), Color(0xFF0A3447)],
    stops: <double>[0, .46, 1],
  );
  static const LinearGradient _metal = LinearGradient(
    colors: <Color>[
      Color(0xFF778C95),
      Color(0xFFE2ECEF),
      Color(0xFF8FA9B3),
      Color(0xFFF4F8F9),
      Color(0xFF687D86),
    ],
    stops: <double>[0, .2, .48, .74, 1],
  );
  static const LinearGradient _flange = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF3E8BA7), Color(0xFF14516A), Color(0xFF082C3C)],
    stops: <double>[0, .55, 1],
  );
  static const LinearGradient _box = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFF438EA9), Color(0xFF17465A)],
  );
  static const RadialGradient _endcap = RadialGradient(
    center: Alignment(-.32, -.44),
    radius: .82,
    colors: <Color>[Color(0xFF4D9CB7), Color(0xFF16516A), Color(0xFF092B3B)],
    stops: <double>[0, .56, 1],
  );

  static Paint _fill(Color c) => Paint()..color = c;

  static Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w;

  static Paint _shader(Gradient g, Rect r) => Paint()..shader = g.createShader(r);

  /// Preenche e contorna a mesma forma, como `fill` + `stroke` no SVG.
  static void _shape(Canvas c, Path p, Paint fill, Paint stroke) {
    c.drawPath(p, fill);
    c.drawPath(p, stroke);
  }

  static Path _rrect(double x, double y, double w, double h, double r) =>
      Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)));

  static Path _oval(double cx, double cy, double rx, double ry) =>
      Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2));

  static Path _poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  static void _rotateAbout(Canvas c, double cx, double cy, double degrees) {
    c
      ..translate(cx, cy)
      ..rotate(degrees * math.pi / 180)
      ..translate(-cx, -cy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = math.min(size.width / _w, size.height / _h);
    canvas.save();
    canvas.translate((size.width - _w * scale) / 2, (size.height - _h * scale) / 2);
    canvas.scale(scale);
    if (dimmed) {
      canvas.saveLayer(
        const Rect.fromLTWH(0, 0, _w, _h),
        Paint()..color = const Color(0xC7000000),
      );
    }

    final double angle = motion.angle;
    final MotionAppearance look = motionAppearance(motion.speed);

    // Sombra no chão.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(355, 378), width: 540, height: 76),
      _fill(const Color(0xFF020F15).withValues(alpha: .48)),
    );

    // Tampa traseira da ventoinha.
    final Path rear = Path()
      ..moveTo(145, 155)
      ..cubicTo(112, 163, 94, 190, 94, 241)
      ..cubicTo(94, 289, 112, 318, 145, 327)
      ..lineTo(176, 328)
      ..lineTo(176, 155)
      ..close();
    _shape(
      canvas,
      rear,
      _shader(_rear, const Rect.fromLTRB(94, 155, 176, 328)),
      _stroke(const Color(0xFF6DA6B8), 5),
    );
    canvas.drawPath(
      Path()
        ..moveTo(129, 171)
        ..cubicTo(105, 181, 95, 205, 95, 240)
        ..cubicTo(95, 275, 105, 299, 129, 310),
      _stroke(const Color(0xFF8AC5D6).withValues(alpha: .18), 5),
    );
    _shape(
      canvas,
      _oval(111, 240, 24, 49),
      _fill(const Color(0xFF061A24)),
      _stroke(const Color(0xFF4F7F90), 4),
    );

    // Ventoinha vista de lado: achatada na horizontal.
    canvas.save();
    canvas
      ..translate(111, 240)
      ..scale(.46, 1)
      ..translate(-118, -240);
    _rotateAbout(canvas, 118, 240, angle);
    final Path blade = Path()
      ..moveTo(113, 231)
      ..cubicTo(104, 215, 107, 197, 118, 191)
      ..cubicTo(125, 204, 126, 219, 121, 234)
      ..close();
    final Paint bladeFill = _fill(const Color(0xFF15485D).withValues(alpha: look.bladeOpacity));
    final Paint bladeStroke =
        _stroke(const Color(0xFF73A9BB).withValues(alpha: look.bladeOpacity), 2);
    if (motionBlur && look.blurPx > 0) {
      final MaskFilter blur = MaskFilter.blur(BlurStyle.normal, look.blurPx);
      bladeFill.maskFilter = blur;
      bladeStroke.maskFilter = blur;
    }
    for (int i = 0; i < 5; i++) {
      canvas.save();
      _rotateAbout(canvas, 118, 240, i * 72.0);
      _shape(canvas, blade, bladeFill, bladeStroke);
      canvas.restore();
    }
    final double marker = motionBlur ? look.markerOpacity : 1;
    canvas.drawCircle(
      const Offset(117, 214),
      4.5,
      _fill(const Color(0xFFF0BB69).withValues(alpha: marker)),
    );
    canvas.drawCircle(
      const Offset(117, 214),
      4.5,
      _stroke(const Color(0xFFFFE2A5).withValues(alpha: marker), 1.5),
    );
    _shape(
      canvas,
      Path()..addOval(Rect.fromCircle(center: const Offset(118, 240), radius: 10)),
      _fill(const Color(0xFF0B2330)),
      _stroke(const Color(0xFFBDD9E2), 3),
    );
    canvas.restore();

    canvas.drawPath(
      _oval(111, 240, 28, 54),
      _stroke(const Color(0xFF7DB4C5).withValues(alpha: .9), 4),
    );
    final Paint grid = _stroke(const Color(0xFF5F93A5).withValues(alpha: .5), 3);
    canvas
      ..drawLine(const Offset(111, 188), const Offset(111, 292), grid)
      ..drawLine(const Offset(91, 206), const Offset(130, 274), grid)
      ..drawLine(const Offset(91, 274), const Offset(130, 206), grid);
    final Path shade = Path()
      ..moveTo(123, 185)
      ..cubicTo(143, 195, 151, 214, 151, 240)
      ..cubicTo(151, 267, 143, 286, 123, 296)
      ..lineTo(141, 322)
      ..lineTo(175, 328)
      ..lineTo(175, 155)
      ..lineTo(141, 156)
      ..close();
    canvas.drawPath(
      shade,
      _shader(_rear, const Rect.fromLTRB(123, 155, 175, 328))
        ..color = const Color(0xCC000000),
    );

    // Carcaça com aletas.
    _shape(
      canvas,
      _rrect(154, 143, 330, 194, 50),
      _shader(_body, const Rect.fromLTWH(154, 143, 330, 194)),
      _stroke(const Color(0xFF77AEBE), 5),
    );
    const List<double> finTop = <double>[149, 146, 144, 143, 142, 142, 143, 144, 146, 149];
    const List<double> finHeight = <double>[181, 187, 190, 192, 193, 193, 192, 190, 187, 181];
    final Paint finFill = _fill(const Color(0xFF0B4055));
    final Paint finStroke = _stroke(const Color(0xFF3B829A), 2);
    for (int i = 0; i < finTop.length; i++) {
      _shape(canvas, _rrect(188 + 26.0 * i, finTop[i], 14, finHeight[i], 5), finFill, finStroke);
    }
    final double? h = heat;
    if (h != null && h > 0) {
      canvas.drawPath(
        _rrect(154, 143, 330, 194, 50),
        _fill(_heatColor(h).withValues(alpha: .18 + .6 * h))
          ..blendMode = BlendMode.screen
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .8),
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(179, 169)
        ..cubicTo(245, 140, 378, 140, 453, 165),
      _stroke(const Color(0xFF85C8D9).withValues(alpha: .24), 11),
    );
    canvas.drawPath(
      Path()
        ..moveTo(177, 308)
        ..cubicTo(267, 338, 383, 335, 455, 304),
      _stroke(const Color(0xFF061E29).withValues(alpha: .58), 13),
    );

    // Pés e base.
    final Paint footFill = _fill(const Color(0xFF0B3749));
    final Paint footStroke = _stroke(const Color(0xFF6196A8), 4);
    _shape(canvas, _poly(const <Offset>[Offset(174, 324), Offset(252, 324), Offset(264, 369), Offset(161, 369)]), footFill, footStroke);
    _shape(canvas, _poly(const <Offset>[Offset(369, 324), Offset(450, 324), Offset(464, 369), Offset(357, 369)]), footFill, footStroke);
    _shape(canvas, _rrect(158, 361, 313, 18, 5), footFill, footStroke);

    // Caixa de ligação.
    _shape(
      canvas,
      _poly(const <Offset>[Offset(247, 95), Offset(379, 95), Offset(404, 118), Offset(386, 155), Offset(239, 155), Offset(221, 118)]),
      _shader(_box, const Rect.fromLTRB(221, 95, 404, 155)),
      _stroke(const Color(0xFF88BBCA), 5),
    );
    _shape(canvas, _rrect(237, 78, 152, 34, 9), _fill(const Color(0xFF2D6E88)), _stroke(const Color(0xFF9AC8D5), 5));
    _shape(canvas, _rrect(255, 68, 116, 15, 6), _fill(const Color(0xFF163F53)), _stroke(const Color(0xFF75A7B7), 4));
    for (final double x in const <double>[282, 346]) {
      _shape(canvas, _oval(x, 122, 10, 10), _fill(const Color(0xFF071E29)), _stroke(const Color(0xFF91BDCA), 4));
    }

    // Tampa dianteira, rolamento e parafusos.
    _shape(
      canvas,
      _oval(486, 240, 85, 100),
      _shader(_flange, const Rect.fromLTRB(401, 140, 571, 340)),
      _stroke(const Color(0xFF8BB9C8), 5),
    );
    _shape(
      canvas,
      _oval(486, 240, 63, 75),
      _shader(_endcap, const Rect.fromLTRB(423, 165, 549, 315)),
      _stroke(const Color(0xFF5B93A6), 5),
    );
    _shape(canvas, _oval(486, 240, 43, 52), _fill(const Color(0xFF082B3A)), _stroke(const Color(0xFF9BC2CE), 5));
    final Paint spoke = _stroke(const Color(0xFF5E9DB3).withValues(alpha: .78), 7);
    const List<List<double>> spokes = <List<double>>[
      <double>[486, 168, 486, 190], <double>[486, 290, 486, 312],
      <double>[432, 240, 454, 240], <double>[518, 240, 540, 240],
      <double>[450, 190, 464, 205], <double>[508, 276, 523, 292],
      <double>[450, 290, 465, 275], <double>[508, 204, 523, 189],
    ];
    for (final List<double> s in spokes) {
      canvas.drawLine(Offset(s[0], s[1]), Offset(s[2], s[3]), spoke);
    }
    const List<Offset> bolts = <Offset>[
      Offset(486, 157), Offset(486, 323), Offset(417, 240), Offset(555, 240),
      Offset(437, 179), Offset(535, 179), Offset(437, 301), Offset(535, 301),
    ];
    final Paint boltFill = _fill(const Color(0xFFD0DDE1));
    final Paint boltStroke = _stroke(const Color(0xFF617680), 2);
    for (final Offset b in bolts) {
      canvas
        ..drawCircle(b, 6, boltFill)
        ..drawCircle(b, 6, boltStroke);
    }

    // Eixo.
    _shape(
      canvas,
      _rrect(480, 221, 178, 38, 16),
      _shader(_metal, const Rect.fromLTWH(480, 221, 178, 38)),
      _stroke(const Color(0xFFE0EDF0), 3),
    );
    canvas.drawLine(
      const Offset(501, 229),
      const Offset(638, 229),
      _stroke(Colors.white.withValues(alpha: .32), 5),
    );
    _shape(canvas, _oval(658, 240, 15, 19), _fill(const Color(0xFF8599A1)), _stroke(const Color(0xFFE0EBEE), 3));
    canvas.drawPath(_oval(658, 240, 7, 10), _fill(const Color(0xFF31464E)));
    canvas.save();
    _rotateAbout(canvas, 658, 240, angle);
    canvas.drawLine(
      const Offset(658, 240),
      const Offset(658, 232),
      _stroke(const Color(0xFFDBE8EB), 3.2)..strokeCap = StrokeCap.round,
    );
    canvas
      ..drawCircle(const Offset(658, 230), 2.6, _fill(const Color(0xFFF0BB69)))
      ..drawCircle(const Offset(658, 230), 2.6, _stroke(const Color(0xFFFFE4AD), 1));
    canvas.restore();

    // Placa de identificação.
    _shape(canvas, _rrect(260, 216, 100, 61, 7), _fill(const Color(0xFFB8C4C8)), _stroke(const Color(0xFF52666E), 3));
    final Paint plateLine = _fill(const Color(0xFF75868C));
    canvas
      ..drawPath(_rrect(269, 225, 82, 6, 2), plateLine)
      ..drawPath(_rrect(269, 237, 69, 4, 2), plateLine)
      ..drawPath(_rrect(269, 247, 76, 4, 2), plateLine)
      ..drawPath(_rrect(269, 257, 57, 4, 2), plateLine);

    // Rotor visível no eixo.
    canvas.save();
    _rotateAbout(canvas, 622, 240, angle);
    _shape(canvas, _oval(622, 240, 15, 15), _fill(const Color(0xFF0A2631)), _stroke(const Color(0xFFB2D0D8), 4));
    final Paint rotorLine = _stroke(const Color(0xFFD5E6EA), 6)..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(622, 227), const Offset(622, 253), rotorLine)
      ..drawLine(const Offset(609, 240), const Offset(635, 240), rotorLine);
    canvas.restore();

    // Alarmes disparados, piscando.
    if (alarmVibration || alarmTemperature) {
      final double o = blinkOpacity();
      if (alarmVibration) {
        final Paint wave = _stroke(const Color(0xFFFF6B6B).withValues(alpha: o), 9)
          ..strokeCap = StrokeCap.round;
        canvas
          ..drawPath(Path()..moveTo(140, 334)..cubicTo(128, 347, 128, 368, 140, 381), wave)
          ..drawPath(Path()..moveTo(118, 322)..cubicTo(98, 344, 98, 372, 118, 394), wave)
          ..drawPath(Path()..moveTo(490, 334)..cubicTo(502, 347, 502, 368, 490, 381), wave)
          ..drawPath(Path()..moveTo(512, 322)..cubicTo(532, 344, 532, 372, 512, 394), wave);
      }
      if (alarmTemperature) {
        canvas.save();
        canvas.translate(222, 208);
        canvas
          ..drawCircle(Offset.zero, 38, _fill(const Color(0xFFE5484D).withValues(alpha: o)))
          ..drawCircle(Offset.zero, 38, _stroke(const Color(0xFFFFD6D6).withValues(alpha: o), 5));
        final Paint glyph = _fill(Colors.white.withValues(alpha: o));
        canvas
          ..drawPath(_rrect(-7, -26, 14, 36, 7), glyph)
          ..drawCircle(const Offset(0, 14), 13, glyph);
        canvas.restore();
      }
    }

    if (dimmed) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MotorPainter old) {
    return old.motion != motion ||
        old.heat != heat ||
        old.alarmTemperature != alarmTemperature ||
        old.alarmVibration != alarmVibration ||
        old.dimmed != dimmed ||
        old.motionBlur != motionBlur;
  }
}
