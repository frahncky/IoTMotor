import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/telemetry_sample.dart';

class GrandezasTab extends StatelessWidget {
  const GrandezasTab({
    super.key,
    required this.controller,
    this.showHeader = true,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 86),
  });

  final MotorControlController controller;
  final bool showHeader;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final TelemetrySample? sample = controller.latestSample;
    final List<_MagnitudeInfo> magnitudes = _buildMagnitudes(sample);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints viewport) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (showHeader) ...<Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.speed_rounded,
                          color: AppTheme.brandMint,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Medi\u00e7\u00f5es',
                            style: Theme.of(context).textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _latestLabel(sample),
                          style: Theme.of(context).textTheme.labelMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints grid) {
                        final double maxWidth =
                            grid.maxWidth.isFinite
                                ? grid.maxWidth
                                : MediaQuery.sizeOf(context).width;
                        final double maxHeight = grid.maxHeight.isFinite ? grid.maxHeight : MediaQuery.sizeOf(context).height;
                        final int columns = _columnsForWidth(maxWidth);
                        const double spacing = 8;
                        final int rows = (magnitudes.length / columns).ceil();
                        // Calcula altura mínima necessária para todos os cards sem rolagem (mais compacto)
                        final double cardHeight = ((maxHeight - (rows - 1) * spacing) / rows).clamp(90, 200);
                        final double cardWidth = (maxWidth - spacing * (columns - 1)) / columns;
                        final double aspectRatio = cardWidth / cardHeight;

                        // Se todos os cards cabem, não rola
                        final bool needsScroll = (rows * 300 + (rows - 1) * spacing) > maxHeight;

                        return GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                            childAspectRatio: aspectRatio,
                          ),
                          itemCount: magnitudes.length,
                          physics: needsScroll ? null : const NeverScrollableScrollPhysics(),
                          shrinkWrap: !needsScroll,
                          itemBuilder: (context, index) {
                            return _MagnitudeCard(magnitude: magnitudes[index]);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  int _columnsForWidth(double width) {
    if (width >= 1080) {
      return 6;
    }
    if (width >= 8060) {
      return 5;
    }
    if (width >= 520) {
      return 3;
    }
    return 2;
  }

  List<_MagnitudeInfo> _buildMagnitudes(TelemetrySample? sample) {
    final double? apparent = _apparentPower(sample);
    final double? reactive = _reactivePower(sample, apparent);

    return <_MagnitudeInfo>[
      _MagnitudeInfo(
        label: 'Aparente',
        value: apparent,
        unit: 'VA',
        decimalDigits: 1,
        icon: Icons.data_usage_rounded,
        color: AppTheme.brandMint,
      ),
      _MagnitudeInfo(
        label: 'Ativa',
        value: sample?.power,
        unit: 'W',
        decimalDigits: 1,
        icon: Icons.flash_on_rounded,
        color: AppTheme.brandOrange,
      ),
      _MagnitudeInfo(
        label: 'Reativa',
        value: reactive,
        unit: 'VAr',
        decimalDigits: 1,
        icon: Icons.waves_rounded,
        color: AppTheme.brandBlue,
      ),
      _MagnitudeInfo(
        label: 'FP',
        value: sample?.powerFactor,
        unit: '',
        decimalDigits: 2,
        icon: Icons.speed_rounded,
        color: AppTheme.online,
        compactValue: true,
      ),
      _MagnitudeInfo(
        label: 'Tens\u00e3o',
        value: sample?.voltage,
        unit: 'V',
        decimalDigits: 1,
        icon: Icons.electrical_services_rounded,
        color: AppTheme.voltageAccent,
      ),
      _MagnitudeInfo(
        label: 'Corrente',
        value: sample?.current,
        unit: 'A',
        decimalDigits: 2,
        icon: Icons.bolt_rounded,
        color: AppTheme.currentAccent,
      ),
      _MagnitudeInfo(
        label: 'Energia',
        value: sample?.energy,
        unit: 'kWh',
        decimalDigits: 3,
        icon: Icons.battery_charging_full_rounded,
        color: AppTheme.brandMint,
      ),
      _MagnitudeInfo(
        label: 'Frequ\u00eancia',
        value: sample?.frequency,
        unit: 'Hz',
        decimalDigits: 2,
        icon: Icons.ssid_chart_rounded,
        color: AppTheme.brandBlue,
      ),
      _MagnitudeInfo(
        label: 'Vibra\u00e7\u00e3o',
        value: sample?.vibration,
        unit: 'g',
        decimalDigits: 3,
        icon: Icons.sensors_rounded,
        color: AppTheme.vibrationAccent,
      ),
      _MagnitudeInfo(
        label: 'Temperatura',
        value: sample?.temperature,
        unit: '\u00b0C',
        decimalDigits: 1,
        icon: Icons.device_thermostat_rounded,
        color: AppTheme.temperatureAccent,
      ),
    ];
  }

  double? _apparentPower(TelemetrySample? sample) {
    final double? voltage = sample?.voltage;
    final double? current = sample?.current;
    if (!_isFinite(voltage) || !_isFinite(current)) {
      return null;
    }
    return voltage! * current!;
  }

  double? _reactivePower(TelemetrySample? sample, double? apparent) {
    if (!_isFinite(apparent)) {
      return null;
    }

    final double? active = sample?.power;
    if (_isFinite(active)) {
      final double squared = apparent! * apparent - active! * active;
      return math.sqrt(math.max(0, squared));
    }

    final double? powerFactor = sample?.powerFactor;
    if (!_isFinite(powerFactor)) {
      return null;
    }
    return apparent! * math.sqrt(math.max(0, 1 - powerFactor! * powerFactor));
  }

  bool _isFinite(double? value) {
    return value != null && value.isFinite;
  }

  String _latestLabel(TelemetrySample? sample) {
    final DateTime? timestamp = sample?.timestamp;
    if (timestamp == null) {
      return 'Sem leitura';
    }
    final String hour = timestamp.hour.toString().padLeft(2, '0');
    final String minute = timestamp.minute.toString().padLeft(2, '0');
    final String second = timestamp.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _MagnitudeInfo {
  const _MagnitudeInfo({
    required this.label,
    required this.value,
    required this.unit,
    required this.decimalDigits,
    required this.icon,
    required this.color,
    this.compactValue = false,
  });

  final String label;
  final double? value;
  final String unit;
  final int decimalDigits;
  final IconData icon;
  final Color color;
  final bool compactValue;
}

class _MagnitudeCard extends StatelessWidget {
  const _MagnitudeCard({required this.magnitude});

  final _MagnitudeInfo magnitude;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String value = _formatValue(magnitude.value, magnitude.decimalDigits);

    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: magnitude.color.withValues(alpha: 0.58)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: magnitude.color.withValues(alpha: 0.11),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(magnitude.icon, color: magnitude.color, size: 20),
          const SizedBox(height: 3),
          Text(
            magnitude.label,
            style: textTheme.labelMedium?.copyWith(
              color: AppTheme.inkSoft,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  value,
                  style: textTheme.titleMedium?.copyWith(
                    color: magnitude.color,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w900,
                    fontSize: magnitude.compactValue ? 14 : 16,
                  ),
                ),
                if (magnitude.unit.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      magnitude.unit,
                      style: textTheme.labelMedium?.copyWith(
                        color: AppTheme.inkSoft,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatValue(double? value, int decimalDigits) {
    if (value == null || !value.isFinite) {
      return '--';
    }
    return value.toStringAsFixed(decimalDigits);
  }
}
