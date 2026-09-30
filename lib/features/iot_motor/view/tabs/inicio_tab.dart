import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/motor_command_type.dart';
import '../../models/telemetry_sample.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';
import '../widgets/motor_animation_card.dart';
import '../widgets/telemetry_chart.dart';
import 'grandezas_tab.dart';

part 'inicio_partida.dart';
part 'inicio_graficos.dart';

enum _TelemetryGroup { grandezas, eletrica, mecanica }

final List<_TelemetryPlot> _telemetryPlots = <_TelemetryPlot>[
  _TelemetryPlot(
    id: 'voltage',
    group: _TelemetryGroup.eletrica,
    label: 'Tensão',
    title: 'Tensão',
    unit: 'V',
    color: AppTheme.voltageAccent,
    decimalDigits: 1,
    readValue: (TelemetrySample sample) => sample.voltage,
  ),
  _TelemetryPlot(
    id: 'current',
    group: _TelemetryGroup.eletrica,
    label: 'Corrente',
    title: 'Corrente',
    unit: 'A',
    color: AppTheme.currentAccent,
    decimalDigits: 2,
    readValue: (TelemetrySample sample) => sample.current,
  ),
  _TelemetryPlot(
    id: 'power',
    group: _TelemetryGroup.eletrica,
    label: 'Ativa',
    title: 'Ativa',
    unit: 'W',
    color: AppTheme.brandOrange,
    decimalDigits: 1,
    readValue: (TelemetrySample sample) => sample.power,
  ),
  _TelemetryPlot(
    id: 'apparent_power',
    group: _TelemetryGroup.eletrica,
    label: 'Aparente',
    title: 'Aparente',
    unit: 'VA',
    color: AppTheme.brandMint,
    decimalDigits: 1,
    readValue: _readApparentPower,
  ),
  _TelemetryPlot(
    id: 'reactive_power',
    group: _TelemetryGroup.eletrica,
    label: 'Reativa',
    title: 'Reativa',
    unit: 'VAr',
    color: AppTheme.brandBlue,
    decimalDigits: 1,
    readValue: _readReactivePower,
  ),
  _TelemetryPlot(
    id: 'energy',
    group: _TelemetryGroup.eletrica,
    label: 'Energia',
    title: 'Energia',
    unit: 'kWh',
    color: AppTheme.brandMint,
    decimalDigits: 3,
    readValue: (TelemetrySample sample) => sample.energy,
  ),
  _TelemetryPlot(
    id: 'power_factor',
    group: _TelemetryGroup.eletrica,
    label: 'FP',
    title: 'FP',
    unit: '',
    color: AppTheme.online,
    decimalDigits: 2,
    readValue: (TelemetrySample sample) => sample.powerFactor,
  ),
  _TelemetryPlot(
    id: 'frequency',
    group: _TelemetryGroup.eletrica,
    label: 'Frequência',
    title: 'Frequência',
    unit: 'Hz',
    color: AppTheme.brandBlue,
    decimalDigits: 2,
    readValue: (TelemetrySample sample) => sample.frequency,
  ),
  _TelemetryPlot(
    id: 'vibration',
    group: _TelemetryGroup.mecanica,
    label: 'Vibração',
    title: 'Vibração',
    unit: 'mm/s',
    color: AppTheme.vibrationAccent,
    decimalDigits: 2,
    readValue: (TelemetrySample sample) => sample.vibration,
  ),
  _TelemetryPlot(
    id: 'temperature',
    group: _TelemetryGroup.mecanica,
    label: 'Temperatura',
    title: 'Temperatura',
    unit: '°C',
    color: AppTheme.temperatureAccent,
    decimalDigits: 1,
    readValue: (TelemetrySample sample) => sample.temperature,
  ),
];

class _TelemetryPlot {
  const _TelemetryPlot({
    required this.id,
    required this.group,
    required this.label,
    required this.title,
    required this.unit,
    required this.color,
    required this.decimalDigits,
    required this.readValue,
  });

  final String id;
  final _TelemetryGroup group;
  final String label;
  final String title;
  final String unit;
  final Color color;
  final int decimalDigits;
  final double? Function(TelemetrySample sample) readValue;
}

double? _readApparentPower(TelemetrySample sample) {
  final double? voltage = sample.voltage;
  final double? current = sample.current;
  if (!_isFinite(voltage) || !_isFinite(current)) {
    return null;
  }
  return voltage! * current!;
}

double? _readReactivePower(TelemetrySample sample) {
  final double? apparent = _readApparentPower(sample);
  if (!_isFinite(apparent)) {
    return null;
  }

  final double? active = sample.power;
  if (_isFinite(active)) {
    final double squared = apparent! * apparent - active! * active;
    return squared <= 0 ? 0 : math.sqrt(squared);
  }

  final double? powerFactor = sample.powerFactor;
  if (!_isFinite(powerFactor)) {
    return null;
  }
  final double squaredRatio = 1 - powerFactor! * powerFactor;
  return apparent! * (squaredRatio <= 0 ? 0 : math.sqrt(squaredRatio));
}

bool _isFinite(double? value) {
  return value != null && value.isFinite;
}

class InicioTab extends StatefulWidget {
  const InicioTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  State<InicioTab> createState() => _InicioTabState();
}

class _InicioTabState extends State<InicioTab> {
  static const String _addStartTypeAction = '__add_start_type__';

  String? _selectedStartTypeId;

  _TelemetryGroup get _selectedGroup =>
      _groupFromDashboardTab(widget.controller.dashboardTab);

  @override
  Widget build(BuildContext context) {
    final List<MotorCommandType> startTypes = widget.controller.startTypes;
    final MotorCommandType? detectedConnectionType =
        widget.controller.selectedDeviceConnectionType;
    _syncSelectedTypeFromDevice(detectedConnectionType);
    final MotorCommandType selectedStartType = _resolveSelectedStartType(
      startTypes,
    );

    final TelemetrySample? sample = widget.controller.latestSample;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints viewport) {
        final bool useScrollableLayout = viewport.maxHeight < 560;

        if (useScrollableLayout) {
          return SingleChildScrollView(
            key: const ValueKey<String>('tab_inicio'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DelayedReveal(
                      delay: const Duration(milliseconds: 160),
                      child: MotorAnimationCard(
                        controller: widget.controller,
                        startType: selectedStartType,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DelayedReveal(
                      delay: const Duration(milliseconds: 200),
                      child: _buildCommandPanel(
                        context,
                        startTypes: startTypes,
                        selectedStartType: selectedStartType,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DelayedReveal(
                      delay: const Duration(milliseconds: 240),
                      child: _buildChartsPanel(context, sample: sample),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Padding(
          key: const ValueKey<String>('tab_inicio'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1320),
                    child: SizedBox(
                      height: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          DelayedReveal(
                            delay: const Duration(milliseconds: 160),
                            child: MotorAnimationCard(
                              controller: widget.controller,
                              startType: selectedStartType,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DelayedReveal(
                            delay: const Duration(milliseconds: 200),
                            child: _buildCommandPanel(
                              context,
                              startTypes: startTypes,
                              selectedStartType: selectedStartType,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: DelayedReveal(
                              delay: const Duration(milliseconds: 240),
                              child: _buildChartsPanel(context, sample: sample),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // setState e protegido: as partes (extensoes) atualizam a tela por aqui.
  void _atualizar(VoidCallback mudanca) => setState(mudanca);
}
