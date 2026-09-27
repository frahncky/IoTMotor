import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../models/motor_info.dart';
import 'glass_panel.dart';

/// Grandeza do histórico da placa: média e máximo de cada hora.
class _Grandeza {
  const _Grandeza(this.nome, this.unidade, this.casas, this.media, this.maximo, {this.barras = false});

  final String nome;
  final String unidade;
  final int casas;
  final double? Function(BoardHistoryHour) media;
  final double? Function(BoardHistoryHour)? maximo;
  final bool barras;
}

final List<_Grandeza> _grandezas = <_Grandeza>[
  _Grandeza('Corrente', 'A', 2, (BoardHistoryHour h) => h.currentAvg, (BoardHistoryHour h) => h.currentMax),
  _Grandeza('Temperatura', '°C', 1, (BoardHistoryHour h) => h.temperatureAvg, (BoardHistoryHour h) => h.temperatureMax),
  _Grandeza('Vibração', 'mm/s', 2, (BoardHistoryHour h) => h.vibrationAvg, (BoardHistoryHour h) => h.vibrationMax),
  _Grandeza('Tensão', 'V', 1, (BoardHistoryHour h) => h.voltageAvg, null),
  _Grandeza('Tempo ligado', 'min/h', 0, (BoardHistoryHour h) => h.minutesOn.toDouble(), null, barras: true),
];

/// Histórico por hora dos últimos 7 dias guardado na placa de sensores: o
/// registro continua com o app fechado.
class BoardHistoryPanel extends StatefulWidget {
  const BoardHistoryPanel({super.key, required this.horas});

  final List<BoardHistoryHour> horas;

  @override
  State<BoardHistoryPanel> createState() => _BoardHistoryPanelState();
}

class _BoardHistoryPanelState extends State<BoardHistoryPanel> {
  int _escolhida = 0;

  Color _cor(int i) => <Color>[
        AppTheme.currentAccent,
        AppTheme.temperatureAccent,
        AppTheme.vibrationAccent,
        AppTheme.voltageAccent,
        AppTheme.online,
      ][i];

  @override
  Widget build(BuildContext context) {
    final _Grandeza g = _grandezas[_escolhida];
    final int minutos = widget.horas.fold(0, (int s, BoardHistoryHour h) => s + h.minutesOn);
    final TextTheme texto = Theme.of(context).textTheme;
    return GlassPanel(
      tint: AppTheme.brandBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Histórico da placa · últimos 7 dias', style: texto.titleMedium),
          const SizedBox(height: 4),
          Text(
            widget.horas.isEmpty
                ? 'A placa de sensores ainda não publicou histórico (precisa do firmware novo e da hora da internet).'
                : 'Médias e máximos de cada hora, guardados na placa. Motor ligado '
                    '${minutos ~/ 60} h ${(minutos % 60).toString().padLeft(2, '0')} min em 7 dias.',
            style: texto.bodySmall?.copyWith(color: AppTheme.bodySoft),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              for (int i = 0; i < _grandezas.length; i++)
                ChoiceChip(
                  label: Text(_grandezas[i].nome),
                  selected: i == _escolhida,
                  onSelected: (_) => setState(() => _escolhida = i),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            width: double.infinity,
            child: CustomPaint(
              painter: _HistoricoPainter(
                horas: widget.horas,
                grandeza: g,
                cor: _cor(_escolhida),
                corTexto: AppTheme.labelSoft,
                agora: DateTime.now(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            g.barras
                ? 'Barras: minutos ligado em cada hora.'
                : g.maximo == null
                    ? 'Média de cada hora.'
                    : 'Linha forte: média da hora · linha clara: máximo da hora.',
            style: texto.bodySmall?.copyWith(color: AppTheme.labelSoft),
          ),
        ],
      ),
    );
  }
}

class _HistoricoPainter extends CustomPainter {
  _HistoricoPainter({
    required this.horas,
    required this.grandeza,
    required this.cor,
    required this.corTexto,
    required this.agora,
  });

  final List<BoardHistoryHour> horas;
  final _Grandeza grandeza;
  final Color cor;
  final Color corTexto;
  final DateTime agora;

  static const int _horaMs = 3600000;

  void _texto(Canvas canvas, String s, Offset onde) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: corTexto, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, onde);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const double e = 40, d = 6, t = 6, b = 18;
    final int fim = agora.millisecondsSinceEpoch;
    final int inicio = fim - 7 * 24 * _horaMs;
    double x(int ms) => e + (ms - inicio) / (fim - inicio) * (size.width - e - d);

    final List<(int, double, double?)> pontos = <(int, double, double?)>[
      for (final BoardHistoryHour h in horas)
        if (grandeza.media(h) != null)
          (h.time.millisecondsSinceEpoch, grandeza.media(h)!, grandeza.maximo?.call(h)),
    ];
    final List<double> valores = <double>[
      for (final (int, double, double?) p in pontos) ...<double>[p.$2, if (p.$3 != null) p.$3!],
    ];
    final bool baseZero = grandeza.barras || grandeza.nome == 'Corrente' || grandeza.nome == 'Vibração';
    double minimo = valores.isEmpty ? 0 : valores.reduce(math.min);
    double maximo = valores.isEmpty ? 1 : valores.reduce(math.max);
    if (baseZero) minimo = 0;
    if (grandeza.barras) maximo = 60;
    if (maximo - minimo < 1e-9) {
      maximo += 1;
      if (!baseZero) minimo -= 1;
    }
    if (!grandeza.barras) {
      final double folga = (maximo - minimo) * 0.08;
      maximo += folga;
      if (!baseZero) minimo -= folga;
    }
    double y(double v) => t + (1 - (v - minimo) / (maximo - minimo)) * (size.height - t - b);

    // Grade: meia-noite de cada dia.
    final Paint grade = Paint()
      ..color = corTexto.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    DateTime dia = DateTime(agora.year, agora.month, agora.day).subtract(const Duration(days: 6));
    while (dia.isBefore(agora)) {
      final double px = x(dia.millisecondsSinceEpoch);
      if (px >= e) {
        canvas.drawLine(Offset(px, t), Offset(px, size.height - b), grade);
        _texto(canvas, '${dia.day.toString().padLeft(2, '0')}/${dia.month.toString().padLeft(2, '0')}',
            Offset(px + 2, size.height - b + 3));
      }
      dia = DateTime(dia.year, dia.month, dia.day + 1);
    }
    String numero(double v) => v.toStringAsFixed(grandeza.barras ? 0 : grandeza.casas).replaceAll('.', ',');
    _texto(canvas, numero(maximo), Offset(0, y(maximo) - 6));
    _texto(canvas, numero(minimo), Offset(0, y(minimo) - 12));
    _texto(canvas, grandeza.unidade, Offset(0, size.height - b + 3));

    if (pontos.isEmpty) {
      _texto(canvas, 'Sem registros nestes 7 dias', Offset(size.width / 2 - 70, size.height / 2 - 6));
      return;
    }
    if (grandeza.barras) {
      final Paint barra = Paint()..color = cor;
      final double largura = math.max(1, x(_horaMs) - x(0) - 0.5);
      for (final (int, double, double?) p in pontos) {
        if (p.$2 <= 0) continue;
        canvas.drawRect(Rect.fromLTRB(x(p.$1), y(p.$2), x(p.$1) + largura, y(0)), barra);
      }
      return;
    }
    // Linhas quebradas onde falta hora.
    Path trilha(double? Function((int, double, double?)) valor) {
      final Path path = Path();
      int? anterior;
      for (final (int, double, double?) p in pontos) {
        final double? v = valor(p);
        if (v == null) {
          anterior = null;
          continue;
        }
        final Offset o = Offset(x(p.$1 + _horaMs ~/ 2), y(v));
        if (anterior != null && p.$1 - anterior <= _horaMs) {
          path.lineTo(o.dx, o.dy);
        } else {
          path.moveTo(o.dx, o.dy);
          path.addOval(Rect.fromCircle(center: o, radius: 1.2));
          path.moveTo(o.dx, o.dy);
        }
        anterior = p.$1;
      }
      return path;
    }

    if (grandeza.maximo != null) {
      canvas.drawPath(
        trilha(((int, double, double?) p) => p.$3),
        Paint()
          ..color = cor.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    canvas.drawPath(
      trilha(((int, double, double?) p) => p.$2),
      Paint()
        ..color = cor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HistoricoPainter old) =>
      old.horas != horas || old.grandeza != grandeza || old.cor != cor;
}
