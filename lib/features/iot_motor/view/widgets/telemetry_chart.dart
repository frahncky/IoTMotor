import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

class TelemetryChart extends StatelessWidget {
  const TelemetryChart({
    super.key,
    required this.title,
    required this.color,
    required this.values,
    required this.unit,
    this.instantValue,
    this.decimalDigits = 2,
    this.chartHeight = 210,
    this.titleWidget,
  });

  final String title;
  final Color color;
  final List<double> values;
  final String unit;
  final double? instantValue;
  final int decimalDigits;
  final double chartHeight;
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final double? liveValue =
        instantValue ?? (values.isEmpty ? null : values.last);
    final _ChartScale scale =
        values.isEmpty ? _emptyScale(liveValue) : _computeScale(values);
    final String formattedLiveValue =
        liveValue == null ? '--' : liveValue.toStringAsFixed(decimalDigits);
    final String titleText = unit.isEmpty ? title : '$title ($unit)';
    final String instantText =
        unit.isEmpty
            ? 'Instant\u00e2neo: $formattedLiveValue'
            : 'Instant\u00e2neo: $formattedLiveValue $unit';
    final Widget chartBody = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        RepaintBoundary(
          child: LineChart(_buildChartData(context, scale: scale, liveValue: liveValue)),
        ),
        if (values.isEmpty)
          Center(child: Text('Sem dados', style: textTheme.bodyMedium)),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppTheme.surfaceSoft.withValues(alpha: 0.96),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool boundedHeight = constraints.maxHeight.isFinite;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child:
                        titleWidget ??
                        Text(
                          titleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: color.withValues(alpha: 0.1),
                          border: Border.all(
                            color: color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            instantText,
                            maxLines: 1,
                            style: textTheme.labelMedium?.copyWith(
                              color: color.withValues(alpha: 0.95),
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (boundedHeight)
                Expanded(child: chartBody)
              else
                SizedBox(height: chartHeight, child: chartBody),
            ],
          );
        },
      ),
    );
  }

  LineChartData _buildChartData(
    BuildContext context, {
    required _ChartScale scale,
    required double? liveValue,
  }) {
    final List<FlSpot> spots = <FlSpot>[
      for (int i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];

    final double xInterval = _xAxisInterval(scale.maxX);

    return LineChartData(
      minX: 0,
      maxX: scale.maxX,
      minY: scale.minY,
      maxY: scale.maxY,
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppTheme.ink.withValues(alpha: 0.9),
          tooltipRoundedRadius: 10,
          getTooltipItems: (List<LineBarSpot> touchedSpots) {
            return touchedSpots.map((LineBarSpot spot) {
              final String formatted = spot.y.toStringAsFixed(decimalDigits);
              return LineTooltipItem(
                unit.isEmpty ? formatted : '$formatted $unit',
                (Theme.of(context).textTheme.labelMedium ??
                        const TextStyle(fontSize: 11))
                    .copyWith(color: Colors.white),
              );
            }).toList();
          },
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        verticalInterval: xInterval,
        horizontalInterval: scale.interval,
        getDrawingHorizontalLine:
            (double _) =>
                FlLine(color: color.withValues(alpha: 0.14), strokeWidth: 1),
        getDrawingVerticalLine:
            (double _) =>
                FlLine(color: color.withValues(alpha: 0.08), strokeWidth: 1),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          left: BorderSide(color: color.withValues(alpha: 0.72), width: 1.4),
          bottom: BorderSide(color: color.withValues(alpha: 0.72), width: 1.4),
          right: BorderSide(color: Colors.transparent),
          top: BorderSide(color: Colors.transparent),
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          axisNameWidget: Text(
            'Amostras',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          axisNameSize: 18,
          sideTitles: SideTitles(
            showTitles: true,
            interval: xInterval,
            reservedSize: 20,
            getTitlesWidget: (double value, TitleMeta meta) {
              if (value < 0 || value > scale.maxX) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  value.toInt().toString(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          axisNameSize: 0,
          sideTitles: SideTitles(
            showTitles: true,
            interval: scale.interval,
            reservedSize: 48,
            getTitlesWidget: (double value, TitleMeta meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  _formatValue(value, scale.interval),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color.withValues(alpha: 0.86),
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      extraLinesData:
          liveValue == null
              ? ExtraLinesData()
              : ExtraLinesData(
                horizontalLines: <HorizontalLine>[
                  HorizontalLine(
                    y: liveValue,
                    color: color.withValues(alpha: 0.76),
                    strokeWidth: 1.2,
                    dashArray: <int>[6, 4],
                  ),
                ],
              ),
      lineBarsData: <LineChartBarData>[
        LineChartBarData(
          spots: spots,
          isCurved: false,
          barWidth: 2.2,
          color: color,
          isStrokeCapRound: false,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      ],
    );
  }

  double _xAxisInterval(double maxX) {
    if (maxX <= 6) {
      return 1;
    }
    if (maxX <= 20) {
      return 2;
    }
    if (maxX <= 40) {
      return 5;
    }
    if (maxX <= 80) {
      return 10;
    }
    return 20;
  }

  _ChartScale _computeScale(List<double> series) {
    double minY = series.reduce(math.min);
    double maxY = series.reduce(math.max);
    final double range = (maxY - minY).abs();
    final double padding = range < 0.5 ? 0.25 : range * 0.15;
    minY -= padding;
    maxY += padding;

    final double interval = _axisInterval(minY, maxY);
    minY = (minY / interval).floorToDouble() * interval;
    maxY = (maxY / interval).ceilToDouble() * interval;

    if ((maxY - minY).abs() < 0.0001) {
      maxY += interval;
    }

    return _ChartScale(
      minY: minY,
      maxY: maxY,
      interval: interval,
      maxX: series.isNotEmpty ? series.length.toDouble() : 1,
    );
  }

  _ChartScale _emptyScale(double? liveValue) {
    final double center = liveValue ?? 0;
    final double rawMin = center - 1;
    final double rawMax = center + 1;
    final double interval = _axisInterval(rawMin, rawMax);

    return _ChartScale(
      minY: (rawMin / interval).floorToDouble() * interval,
      maxY: (rawMax / interval).ceilToDouble() * interval,
      interval: interval,
      maxX: 120,
    );
  }

  double _axisInterval(double minY, double maxY) {
    final double range = (maxY - minY).abs();
    if (range == 0) {
      return 1;
    }
    final double roughStep = range / 5;
    final int exponent = (math.log(roughStep) / math.ln10).floor();
    final double magnitude = math.pow(10, exponent).toDouble();
    final double normalized = roughStep / magnitude;

    double step;
    if (normalized <= 1) {
      step = 1;
    } else if (normalized <= 2) {
      step = 2;
    } else if (normalized <= 5) {
      step = 5;
    } else {
      step = 10;
    }

    return step * magnitude;
  }

  String _formatValue(double value, double interval) {
    final double absInterval = interval.abs();
    if (absInterval < 0.1) {
      return value.toStringAsFixed(3);
    }
    if (absInterval < 1) {
      return value.toStringAsFixed(2);
    }
    if (absInterval < 10) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(0);
  }
}

class _ChartScale {
  const _ChartScale({
    required this.minY,
    required this.maxY,
    required this.interval,
    required this.maxX,
  });

  final double minY;
  final double maxY;
  final double interval;
  final double maxX;
}
