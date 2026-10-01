import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../models/motor_info.dart';
import 'app_section.dart';

/// Grandeza do histórico da placa: média e máximo de cada hora.
class _Grandeza {
  const _Grandeza(
    this.nome,
    this.unidade,
    this.casas,
    this.media,
    this.maximo, {
    this.barras = false,
  });

  final String nome;
  final String unidade;
  final int casas;
  final double? Function(BoardHistoryHour) media;
  final double? Function(BoardHistoryHour)? maximo;
  final bool barras;
}

final List<_Grandeza> _grandezas = <_Grandeza>[
  _Grandeza(
    'Corrente',
    'A',
    2,
    (BoardHistoryHour h) => h.currentAvg,
    (BoardHistoryHour h) => h.currentMax,
  ),
  _Grandeza(
    'Temperatura',
    '°C',
    1,
    (BoardHistoryHour h) => h.temperatureAvg,
    (BoardHistoryHour h) => h.temperatureMax,
  ),
  _Grandeza(
    'Vibração',
    'mm/s',
    2,
    (BoardHistoryHour h) => h.vibrationAvg,
    (BoardHistoryHour h) => h.vibrationMax,
  ),
  _Grandeza('Tensão', 'V', 1, (BoardHistoryHour h) => h.voltageAvg, null),
  _Grandeza(
    'Tempo ligado',
    'min/h',
    0,
    (BoardHistoryHour h) => h.minutesOn.toDouble(),
    null,
    barras: true,
  ),
];

/// O que um item da legenda representa no gráfico.
enum TipoLegenda { media, maximo, ponto, barra, nota }

typedef ItemLegenda = ({TipoLegenda tipo, String texto});

/// Legenda só com o que aparece no gráfico da grandeza [grandeza] (índice na
/// ordem dos botões: corrente, temperatura, vibração, tensão, tempo ligado).
List<ItemLegenda> legendaDoHistorico(
  List<BoardHistoryHour> horas,
  int grandeza,
) {
  const int horaMs = 3600000;
  final _Grandeza g = _grandezas[grandeza];
  final List<BoardHistoryHour> pontos = <BoardHistoryHour>[
    for (final BoardHistoryHour h in horas)
      if (g.media(h) != null) h,
  ];
  int ms(int i) => pontos[i].time.millisecondsSinceEpoch;
  bool seguida(int i) => i > 0 && ms(i) - ms(i - 1) <= horaMs;
  final List<ItemLegenda> itens = <ItemLegenda>[];
  if (g.barras) {
    if (pontos.any((BoardHistoryHour h) => g.media(h)! > 0)) {
      itens.add((
        tipo: TipoLegenda.barra,
        texto: 'minutos ligado em cada hora',
      ));
    }
    return itens;
  }
  if (pontos.isEmpty) return itens;
  final bool soLigado = g.nome == 'Corrente' || g.nome == 'Vibração';
  final Iterable<int> indices = Iterable<int>.generate(pontos.length);
  if (indices.any(seguida)) {
    itens.add((
      tipo: TipoLegenda.media,
      texto: 'média de cada hora${soLigado ? ', com o motor girando' : ''}',
    ));
  }
  if (g.maximo != null &&
      indices.any(
        (int i) =>
            seguida(i) &&
            g.maximo!(pontos[i]) != null &&
            g.maximo!(pontos[i - 1]) != null,
      )) {
    itens.add((tipo: TipoLegenda.maximo, texto: 'máximo da hora'));
  }
  if (indices.any(
    (int i) => !seguida(i) && !(i + 1 < pontos.length && seguida(i + 1)),
  )) {
    itens.add((
      tipo: TipoLegenda.ponto,
      texto: 'hora isolada (sem hora vizinha com registro)',
    ));
  }
  if (g.nome == 'Corrente' &&
      pontos.any((BoardHistoryHour h) => g.media(h) == 0)) {
    itens.add((
      tipo: TipoLegenda.nota,
      texto:
          'Zero: motor marcado como ligado sem corrente (quadro antes da v28).',
    ));
  }
  if (indices.any((int i) => i > 0 && !seguida(i))) {
    itens.add((
      tipo: TipoLegenda.nota,
      texto:
          soLigado
              ? 'Espaço vazio: motor parado ou placa sem dados.'
              : 'Espaço vazio: placa sem leitura.',
    ));
  }
  return itens;
}

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

  Color _cor(int i) =>
      <Color>[
        AppTheme.currentAccent,
        AppTheme.temperatureAccent,
        AppTheme.vibrationAccent,
        AppTheme.voltageAccent,
        AppTheme.online,
      ][i];

  @override
  Widget build(BuildContext context) {
    final _Grandeza g = _grandezas[_escolhida];
    final int minutos = widget.horas.fold(
      0,
      (int s, BoardHistoryHour h) => s + h.minutesOn,
    );
    final TextTheme texto = Theme.of(context).textTheme;
    return AppSection(
      title: 'Últimos 7 dias',
      subtitle:
          widget.horas.isEmpty
              ? 'A placa de sensores ainda não enviou o histórico.'
              : 'Motor ligado ${minutos ~/ 60} h ${(minutos % 60).toString().padLeft(2, '0')} min',
      children: <Widget>[
        if (widget.horas.isNotEmpty) ...<Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < _grandezas.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(_grandezas[i].nome),
                    selected: i == _escolhida,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _escolhida = i),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
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
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: <Widget>[
              for (final ItemLegenda item in legendaDoHistorico(
                widget.horas,
                _escolhida,
              ))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (item.tipo != TipoLegenda.nota) ...<Widget>[
                      CustomPaint(
                        size: const Size(18, 10),
                        painter: _AmostraLegenda(item.tipo, _cor(_escolhida)),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        item.texto,
                        style: texto.bodySmall?.copyWith(
                          color: AppTheme.labelSoft,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Amostra de um item da legenda, desenhada como no gráfico.
class _AmostraLegenda extends CustomPainter {
  _AmostraLegenda(this.tipo, this.cor);

  final TipoLegenda tipo;
  final Color cor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset meio = size.center(Offset.zero);
    final Paint tinta = Paint()..color = cor;
    switch (tipo) {
      case TipoLegenda.media:
      case TipoLegenda.maximo:
        tinta
          ..style = PaintingStyle.stroke
          ..strokeWidth = tipo == TipoLegenda.media ? 2 : 1.2;
        if (tipo == TipoLegenda.maximo) {
          tinta.color = cor.withValues(alpha: 0.55);
        }
        canvas.drawLine(
          Offset(1, meio.dy),
          Offset(size.width - 1, meio.dy),
          tinta,
        );
      case TipoLegenda.ponto:
        tinta
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(meio, 1.2, tinta);
      case TipoLegenda.barra:
        canvas.drawRect(
          Rect.fromCenter(center: meio, width: 6, height: size.height - 1),
          tinta,
        );
      case TipoLegenda.nota:
        break;
    }
  }

  @override
  bool shouldRepaint(_AmostraLegenda old) => old.tipo != tipo || old.cor != cor;
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
    double x(int ms) =>
        e + (ms - inicio) / (fim - inicio) * (size.width - e - d);

    final List<(int, double, double?)> pontos = <(int, double, double?)>[
      for (final BoardHistoryHour h in horas)
        if (grandeza.media(h) != null)
          (
            h.time.millisecondsSinceEpoch,
            grandeza.media(h)!,
            grandeza.maximo?.call(h),
          ),
    ];
    final List<double> valores = <double>[
      for (final (int, double, double?) p in pontos) ...<double>[
        p.$2,
        if (p.$3 != null) p.$3!,
      ],
    ];
    final bool baseZero =
        grandeza.barras ||
        grandeza.nome == 'Corrente' ||
        grandeza.nome == 'Vibração';
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
    double y(double v) =>
        t + (1 - (v - minimo) / (maximo - minimo)) * (size.height - t - b);

    // Grade: meia-noite de cada dia.
    final Paint grade =
        Paint()
          ..color = corTexto.withValues(alpha: 0.25)
          ..strokeWidth = 1;
    DateTime dia = DateTime(
      agora.year,
      agora.month,
      agora.day,
    ).subtract(const Duration(days: 6));
    while (dia.isBefore(agora)) {
      final double px = x(dia.millisecondsSinceEpoch);
      if (px >= e) {
        canvas.drawLine(Offset(px, t), Offset(px, size.height - b), grade);
        _texto(
          canvas,
          '${dia.day.toString().padLeft(2, '0')}/${dia.month.toString().padLeft(2, '0')}',
          Offset(px + 2, size.height - b + 3),
        );
      }
      dia = DateTime(dia.year, dia.month, dia.day + 1);
    }
    String numero(double v) => v
        .toStringAsFixed(grandeza.barras ? 0 : grandeza.casas)
        .replaceAll('.', ',');
    _texto(canvas, numero(maximo), Offset(0, y(maximo) - 6));
    _texto(canvas, numero(minimo), Offset(0, y(minimo) - 12));
    _texto(canvas, grandeza.unidade, Offset(0, size.height - b + 3));

    if (pontos.isEmpty) {
      _texto(
        canvas,
        'Sem registros nestes 7 dias',
        Offset(size.width / 2 - 70, size.height / 2 - 6),
      );
      return;
    }
    if (grandeza.barras) {
      final Paint barra = Paint()..color = cor;
      final double largura = math.max(1, x(_horaMs) - x(0) - 0.5);
      for (final (int, double, double?) p in pontos) {
        if (p.$2 <= 0) continue;
        canvas.drawRect(
          Rect.fromLTRB(x(p.$1), y(p.$2), x(p.$1) + largura, y(0)),
          barra,
        );
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
