import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/motor_command_type.dart';
import '../../models/motor_info.dart';
import 'glass_panel.dart';
import 'motor_usage_strip.dart';

/// Representação vetorial nativa do motor para a tela Início.
///
/// Não comanda a bancada. A rotação acompanha somente o estado confirmado
/// pelos contatores do ESP32-01. RPM e temperatura vêm dos dados já recebidos
/// pelo app; não há deslocamento visual por vibração.
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
  late final AnimationController _ticker;
  Duration? _lastElapsed;
  double _angle = 0;
  double _speed = 0;
  double _startupElapsed = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )
      ..addListener(_tick)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant MotorAnimationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.controller.isBenchMotorOn &&
        widget.controller.isBenchMotorOn) {
      _startupElapsed = 0;
    }
  }

  void _tick() {
    final Duration elapsed = _ticker.lastElapsedDuration ?? Duration.zero;
    final Duration? previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (previous == null) return;

    double dt = (elapsed - previous).inMicroseconds / 1000000;
    if (dt < 0) dt += 1;
    dt = dt.clamp(0.0, 0.064).toDouble();

    final bool running = widget.controller.isBenchMotorOn;
    final double startupSeconds = _startupSeconds(widget.startType);
    if (running) {
      _startupElapsed += dt;
      _speed = math.min(1.0, _speed + dt / startupSeconds).toDouble();
    } else {
      _startupElapsed = 0;
      _speed = math.max(0.0, _speed - dt / 3.6).toDouble();
    }

    double effectiveSpeed = _smoothstep(_speed);
    if (running && _looksSequential(widget.startType)) {
      final double progress = (_startupElapsed / startupSeconds).clamp(0.0, 1.0).toDouble();
      final double center = widget.startType.sequence ? 0.61 : 0.64;
      final double width = widget.startType.sequence ? 0.055 : 0.075;
      final double depth = widget.startType.sequence ? 0.16 : 0.08;
      final double z = (progress - center) / width;
      effectiveSpeed *= 1 - depth * math.exp(-(z * z));
    }

    if (effectiveSpeed > 0.0001) {
      final double rpm = widget.controller.motorInfo?.rpm ?? 1750;
      _angle = (_angle + _visualDps(rpm) * effectiveSpeed * dt) % 360;
    }

    if (mounted) setState(() {});
  }

  static double _smoothstep(double x) {
    final double v = x.clamp(0.0, 1.0).toDouble();
    return v * v * (3 - 2 * v);
  }

  static bool _looksSequential(MotorCommandType type) {
    if (type.sequence) return true;
    final List<ContactorTiming>? timings = type.timings;
    if (timings == null) return false;
    final Set<int> onTimes = timings
        .where((ContactorTiming item) => item.use)
        .map((ContactorTiming item) => item.onMs)
        .toSet();
    return onTimes.length > 1 ||
        timings.any(
          (ContactorTiming item) => item.use && item.offMs > 0,
        );
  }

  static double _startupSeconds(MotorCommandType type) {
    if (type.sequence) return 2.8;
    if (_looksSequential(type)) return 2.2;
    return 1.5;
  }

  static double _visualDps(double rpm) {
    final double nominal = rpm > 0 ? rpm : 1750;
    final double x = ((nominal - 600) / 3000).clamp(0.0, 1.0).toDouble();
    return (540 + 720 * math.pow(x, 0.72)).toDouble();
  }

  @override
  void dispose() {
    _ticker
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool running = widget.controller.isBenchMotorOn;
    final MotorInfo? info = widget.controller.motorInfo;
    final double? temperature = widget.controller.latestSample?.temperature;
    final double rpm = info?.rpm ?? 1750;
    final String status = running
        ? (_speed < 0.95 ? 'Motor partindo' : 'Motor ligado')
        : (_speed > 0.03 ? 'Motor desacelerando' : 'Motor desligado');

    return SizedBox(
      width: double.infinity,
      child: GlassPanel(
        tint: running ? AppTheme.online : AppTheme.brandBlue,
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compact = constraints.maxWidth < 600;
            final Widget drawing = SizedBox(
              width: compact ? 150 : 210,
              height: compact ? 86 : 120,
              child: CustomPaint(
                key: const ValueKey<String>('motor_animation_paint'),
                painter: _MotorPainter(
                  angleDegrees: _angle,
                  speed: _speed,
                  temperature: temperature,
                  running: running,
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
                        color: running ? AppTheme.online : AppTheme.labelSoft,
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

class _MotorPainter extends CustomPainter {
  const _MotorPainter({
    required this.angleDegrees,
    required this.speed,
    required this.temperature,
    required this.running,
  });

  final double angleDegrees;
  final double speed;
  final double? temperature;
  final bool running;

  @override
  void paint(Canvas canvas, Size size) {
    // Desenho em 304 x 172 unidades, escalado sem distorcer.
    const double largura = 304, altura = 172;
    final double scale = math.min(size.width / largura, size.height / altura).toDouble();
    final Offset origin = Offset(
      (size.width - largura * scale) / 2,
      (size.height - altura * scale) / 2,
    );
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);

    final Paint shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(154, 160), width: 236, height: 18),
      shadow,
    );

    final Color bodyBase = Color.lerp(
      const Color(0xFF17556F),
      const Color(0xFFD85B45),
      _heatLevel(temperature),
    )!;
    final Paint body = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color.lerp(bodyBase, Colors.white, 0.16)!,
          bodyBase,
          Color.lerp(bodyBase, Colors.black, 0.34)!,
        ],
      ).createShader(const Rect.fromLTWH(64, 42, 164, 108));

    final RRect bodyRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(66, 44, 160, 104),
      const Radius.circular(28),
    );
    canvas.drawRRect(bodyRect, body);

    final Paint outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = const Color(0xFF88B9C8).withValues(alpha: 0.85);
    canvas.drawRRect(bodyRect, outline);

    final Paint fin = Paint()
      ..color = const Color(0xFF0C4054).withValues(alpha: 0.80)
      ..strokeWidth = 4;
    for (double x = 84; x <= 210; x += 16) {
      canvas.drawLine(Offset(x, 55), Offset(x, 137), fin);
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(114, 20, 64, 30),
        const Radius.circular(7),
      ),
      Paint()..color = const Color(0xFF2A6B83),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(121, 12, 50, 12),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF173E50),
    );

    canvas.drawOval(
      const Rect.fromLTWH(36, 50, 60, 92),
      Paint()..color = const Color(0xFF154A60),
    );
    canvas.drawOval(
      const Rect.fromLTWH(44, 60, 44, 72),
      Paint()..color = const Color(0xFF071F2A),
    );

    final Offset fanCenter = const Offset(66, 96);
    canvas.save();
    canvas.translate(fanCenter.dx, fanCenter.dy);
    canvas.rotate(angleDegrees * math.pi / 180);
    final double blur = ((speed - 0.48) / 0.52).clamp(0.0, 1.0).toDouble();
    final Paint blade = Paint()
      ..color = const Color(0xFF4A90A8).withValues(alpha: 1 - 0.34 * blur);
    for (int i = 0; i < 5; i++) {
      canvas.save();
      canvas.rotate(i * math.pi * 2 / 5);
      final Path p = Path()
        ..moveTo(1, -3)
        ..quadraticBezierTo(9, -25, 20, -26)
        ..quadraticBezierTo(22, -10, 6, 4)
        ..close();
      canvas.drawPath(p, blade);
      canvas.restore();
    }
    canvas.drawCircle(
      Offset.zero,
      6,
      Paint()..color = const Color(0xFFB8D4DD),
    );
    canvas.restore();

    canvas.drawOval(
      const Rect.fromLTWH(212, 42, 70, 108),
      Paint()..color = const Color(0xFF246C85),
    );
    canvas.drawOval(
      const Rect.fromLTWH(226, 56, 42, 80),
      Paint()..color = const Color(0xFF0C3444),
    );

    final Paint shaft = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[
          Color(0xFF7D929B),
          Color(0xFFE8F0F2),
          Color(0xFF788D96),
        ],
      ).createShader(const Rect.fromLTWH(262, 89, 34, 14));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(262, 89, 34, 14),
        const Radius.circular(6),
      ),
      shaft,
    );

    final Offset shaftEnd = const Offset(296, 96);
    canvas.drawCircle(
      shaftEnd,
      7,
      Paint()..color = const Color(0xFF8CA0A8),
    );
    canvas.save();
    canvas.translate(shaftEnd.dx, shaftEnd.dy);
    canvas.rotate(angleDegrees * math.pi / 180);
    canvas.drawLine(
      Offset.zero,
      const Offset(0, -6),
      Paint()
        ..color = AppTheme.brandOrange
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    final Paint foot = Paint()..color = const Color(0xFF0D3C4D);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(80, 140, 50, 20),
        const Radius.circular(4),
      ),
      foot,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(164, 140, 50, 20),
        const Radius.circular(4),
      ),
      foot,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(118, 76, 56, 40),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFB8C4C8),
    );
    final Paint plateLine = Paint()
      ..color = const Color(0xFF65757B)
      ..strokeWidth = 2;
    for (double y = 84; y <= 108; y += 6) {
      canvas.drawLine(Offset(125, y), Offset(167, y), plateLine);
    }

    canvas.restore();
  }

  double _heatLevel(double? temperature) {
    if (temperature == null) return 0;
    return ((temperature - 30) / 40).clamp(0.0, 1.0).toDouble() * 0.72;
  }

  @override
  bool shouldRepaint(covariant _MotorPainter oldDelegate) {
    return oldDelegate.angleDegrees != angleDegrees ||
        oldDelegate.speed != speed ||
        oldDelegate.temperature != temperature ||
        oldDelegate.running != running;
  }
}
