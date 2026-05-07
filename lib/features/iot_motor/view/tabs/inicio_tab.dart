import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/motor_command_type.dart';
import '../../models/telemetry_sample.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';
import '../widgets/telemetry_chart.dart';
import 'grandezas_tab.dart';

enum _TelemetryGroup { grandezas, eletrica, mecanica }

final List<_TelemetryPlot> _telemetryPlots = <_TelemetryPlot>[
  _TelemetryPlot(
    id: 'voltage',
    group: _TelemetryGroup.eletrica,
    label: 'Tens\u00e3o',
    title: 'Tens\u00e3o',
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
    title: 'Pot\u00eancia ativa',
    unit: 'W',
    color: AppTheme.brandOrange,
    decimalDigits: 1,
    readValue: (TelemetrySample sample) => sample.power,
  ),
  _TelemetryPlot(
    id: 'apparent_power',
    group: _TelemetryGroup.eletrica,
    label: 'Aparente',
    title: 'Pot\u00eancia aparente',
    unit: 'VA',
    color: AppTheme.brandMint,
    decimalDigits: 1,
    readValue: _readApparentPower,
  ),
  _TelemetryPlot(
    id: 'reactive_power',
    group: _TelemetryGroup.eletrica,
    label: 'Reativa',
    title: 'Pot\u00eancia reativa',
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
    title: 'Fator de pot\u00eancia',
    unit: '',
    color: AppTheme.online,
    decimalDigits: 2,
    readValue: (TelemetrySample sample) => sample.powerFactor,
  ),
  _TelemetryPlot(
    id: 'frequency',
    group: _TelemetryGroup.eletrica,
    label: 'Frequ\u00eancia',
    title: 'Frequ\u00eancia',
    unit: 'Hz',
    color: AppTheme.brandBlue,
    decimalDigits: 2,
    readValue: (TelemetrySample sample) => sample.frequency,
  ),
  _TelemetryPlot(
    id: 'vibration',
    group: _TelemetryGroup.mecanica,
    label: 'Vibra\u00e7\u00e3o',
    title: 'Vibra\u00e7\u00e3o',
    unit: 'g',
    color: AppTheme.vibrationAccent,
    decimalDigits: 3,
    readValue: (TelemetrySample sample) => sample.vibration,
  ),
  _TelemetryPlot(
    id: 'temperature',
    group: _TelemetryGroup.mecanica,
    label: 'Temperatura',
    title: 'Temperatura',
    unit: '\u00b0C',
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
  _TelemetryGroup _selectedGroup = _TelemetryGroup.grandezas;
  String _selectedElectricalPlotAId = 'voltage';
  String _selectedElectricalPlotBId = 'current';
  String _selectedMechanicalPlotAId = 'vibration';
  String _selectedMechanicalPlotBId = 'temperature';

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
                      delay: const Duration(milliseconds: 200),
                      child: _buildCommandPanel(
                        context,
                        startTypes: startTypes,
                        selectedStartType: selectedStartType,
                      ),
                    ),
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

  Widget _buildCommandPanel(
    BuildContext context, {
    required List<MotorCommandType> startTypes,
    required MotorCommandType selectedStartType,
  }) {
    final bool connected = widget.controller.isConnected;
    final bool canSend = connected && !widget.controller.isBusy;
    final bool motorOn = widget.controller.isSelectedDeviceMotorOn;
    const double controlHeight = 50;
    const double selectorHeight = 74;

    return SizedBox(
      width: double.infinity,
      child: GlassPanel(
        tint: AppTheme.brandBlue,
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                SizedBox(
                  width: 220,
                  height: selectorHeight,
                  child: _buildStartTypeSelector(
                    context,
                    startTypes: startTypes,
                    selectedStartType: selectedStartType,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 126,
                  height: controlHeight,
                  child: FilledButton.icon(
                    onPressed:
                        canSend
                            ? () {
                              if (motorOn) {
                                widget.controller.sendCommand(
                                  MotorCommandType.stop,
                                );
                              } else {
                                widget.controller.sendCommand(
                                  selectedStartType,
                                );
                              }
                            }
                            : null,
                    icon: Icon(
                      motorOn
                          ? Icons.power_off_rounded
                          : Icons.power_settings_new_rounded,
                    ),
                    label: Text(motorOn ? 'Desligar' : 'Ligar'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          motorOn ? AppTheme.danger : AppTheme.online,
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: (motorOn ? AppTheme.danger : AppTheme.online)
                            .withValues(alpha: 0.92),
                      ),
                      shadowColor: (motorOn ? AppTheme.danger : AppTheme.online)
                          .withValues(alpha: 0.45),
                      elevation: 2,
                      minimumSize: Size(0, controlHeight),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  MotorCommandType _resolveSelectedStartType(
    List<MotorCommandType> startTypes,
  ) {
    if (startTypes.isEmpty) {
      return MotorCommandType.directStart;
    }

    final String? selectedId = _selectedStartTypeId;
    if (selectedId != null) {
      for (final MotorCommandType type in startTypes) {
        if (type.id == selectedId) {
          return type;
        }
      }
    }
    return startTypes.first;
  }

  void _syncSelectedTypeFromDevice(MotorCommandType? detectedType) {
    if (detectedType == null) {
      return;
    }
    if (_selectedStartTypeId == detectedType.id) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedStartTypeId = detectedType.id;
      });
    });
  }

  Widget _buildStartTypeSelector(
    BuildContext context, {
    required List<MotorCommandType> startTypes,
    required MotorCommandType selectedStartType,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          top: 8,
          child: PopupMenuButton<String>(
            onSelected: (String action) {
              setState(() {
                _selectedStartTypeId = action;
              });
            },
            itemBuilder: (BuildContext menuContext) {
              final List<PopupMenuEntry<String>> items =
                  <PopupMenuEntry<String>>[
                    ...startTypes.map(
                      (MotorCommandType type) => PopupMenuItem<String>(
                        value: type.id,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPress: () {
                            Navigator.of(menuContext).pop();
                            Future<void>.delayed(Duration.zero, () {
                              if (!mounted) {
                                return;
                              }
                              _openStartTypeActions(
                                context: this.context,
                                type: type,
                              );
                            });
                          },
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  type.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (type.id == selectedStartType.id)
                                Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: AppTheme.brandBlue,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      enabled: false,
                      value: _addStartTypeAction,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Navigator.of(menuContext).pop();
                          Future<void>.delayed(Duration.zero, () {
                            if (!mounted) {
                              return;
                            }
                            _openStartTypeEditor(context: this.context);
                          });
                        },
                        child: const Row(
                          children: <Widget>[
                            Icon(Icons.add_circle_outline_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('Adicionar partida'),
                          ],
                        ),
                      ),
                    ),
                  ];
              return items;
            },
            child: Container(
              height: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceSoft.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.brandBlue.withValues(alpha: 0.34),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.list_alt_rounded,
                    size: 18,
                    color: AppTheme.brandBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedStartType.label,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: AppTheme.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    color: AppTheme.brandBlue,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: AppTheme.surfaceSoft.withValues(alpha: 0.96),
              child: Text(
                'Partida do motor',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openStartTypeActions({
    required BuildContext context,
    required MotorCommandType type,
  }) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext actionContext) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('Editar "${type.label}"'),
                onTap: () => Navigator.of(actionContext).pop('edit'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppTheme.danger),
                title: Text(
                  'Excluir "${type.label}"',
                  style: TextStyle(color: AppTheme.danger),
                ),
                onTap: () => Navigator.of(actionContext).pop('delete'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (action == 'edit') {
      await _openStartTypeEditor(context: this.context, initial: type);
      return;
    }

    if (action != 'delete') {
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: this.context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Excluir partida'),
          content: Text('Deseja excluir "${type.label}"?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    final bool removed = widget.controller.removeStartType(type.id);
    if (!removed || !mounted || _selectedStartTypeId != type.id) {
      return;
    }

    final List<MotorCommandType> remaining = widget.controller.startTypes;
    setState(() {
      _selectedStartTypeId = remaining.isEmpty ? null : remaining.first.id;
    });
  }

  Future<void> _openStartTypeEditor({
    required BuildContext context,
    MotorCommandType? initial,
  }) async {
    String label = initial?.label ?? '';
    String mode = initial?.mode ?? '';

    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(initial == null ? 'Nova partida' : 'Editar partida'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  initialValue: label,
                  autofocus: true,
                  maxLength: 40,
                  onChanged: (String value) {
                    label = value;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Nome da partida',
                    hintText: 'Ex.: Soft Starter',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: mode,
                  onChanged: (String value) {
                    mode = value;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Modo (payload)',
                    hintText: 'Ex.: soft_starter',
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Se deixar o modo vazio, ele ser\u00e1 gerado pelo nome.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (save != true) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (initial == null) {
        widget.controller.addStartType(label: label, mode: mode);
        return;
      }

      widget.controller.updateStartType(
        id: initial.id,
        label: label,
        mode: mode,
      );
    });
  }

  Widget _buildChartsPanel(
    BuildContext context, {
    required TelemetrySample? sample,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 980;
        final double rawHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 620;
        if (_selectedGroup == _TelemetryGroup.grandezas) {
          return _buildGrandezasPanel(constraints);
        }

        final List<_TelemetryPlot> plots = _plotsForGroup(_selectedGroup);
        final String selectedPlotAId = _selectedPlotAId;
        final String selectedPlotBId = _selectedPlotBId;
        final _TelemetryPlot plotA = _plotById(selectedPlotAId, plots);
        final _TelemetryPlot plotB = _plotById(selectedPlotBId, plots);

        if (wide) {
          final double availableForCards = (rawHeight - 54).clamp(
            260.0,
            1200.0,
          );
          final double cardHeight = availableForCards.clamp(220.0, 420.0);
          final double plotHeight = (cardHeight - 86).clamp(84.0, 320.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildGroupSelector(),
              const SizedBox(height: 8),
              SizedBox(
                height: cardHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _buildChartForPlot(
                        context,
                        plotA,
                        sample,
                        plotHeight,
                        selectedPlotId: selectedPlotAId,
                        plots: plots,
                        onPlotChanged: _setSelectedPlotAId,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildChartForPlot(
                        context,
                        plotB,
                        sample,
                        plotHeight,
                        selectedPlotId: selectedPlotBId,
                        plots: plots,
                        onPlotChanged: _setSelectedPlotBId,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final double availableForCards = (rawHeight - 54).clamp(260.0, 1200.0);
        final double cardHeight = ((availableForCards - 10) / 2).clamp(
          150.0,
          360.0,
        );
        final double plotHeight = (cardHeight - 86).clamp(72.0, 250.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildGroupSelector(),
            const SizedBox(height: 8),
            SizedBox(
              height: cardHeight,
              child: _buildChartForPlot(
                context,
                plotA,
                sample,
                plotHeight,
                selectedPlotId: selectedPlotAId,
                plots: plots,
                onPlotChanged: _setSelectedPlotAId,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: cardHeight,
              child: _buildChartForPlot(
                context,
                plotB,
                sample,
                plotHeight,
                selectedPlotId: selectedPlotBId,
                plots: plots,
                onPlotChanged: _setSelectedPlotBId,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGrandezasPanel(BoxConstraints constraints) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildGroupSelector(),
        const SizedBox(height: 8),
        Expanded(
          child: GrandezasTab(
            controller: widget.controller,
            showHeader: false,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupSelector() {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SegmentedButton<_TelemetryGroup>(
          showSelectedIcon: false,
          selected: <_TelemetryGroup>{_selectedGroup},
          onSelectionChanged: (Set<_TelemetryGroup> selection) {
            setState(() {
              _selectedGroup = selection.first;
            });
          },
          segments: const <ButtonSegment<_TelemetryGroup>>[
            ButtonSegment<_TelemetryGroup>(
              value: _TelemetryGroup.grandezas,
              icon: Icon(Icons.speed_rounded, size: 16),
              label: Text('Medi\u00e7\u00f5es'),
            ),
            ButtonSegment<_TelemetryGroup>(
              value: _TelemetryGroup.eletrica,
              icon: Icon(Icons.electric_bolt_rounded, size: 16),
              label: Text('El\u00e9trica'),
            ),
            ButtonSegment<_TelemetryGroup>(
              value: _TelemetryGroup.mecanica,
              icon: Icon(Icons.sensors_rounded, size: 16),
              label: Text('Mec\u00e2nica'),
            ),
          ],
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: const WidgetStatePropertyAll<EdgeInsets>(
              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            textStyle: const WidgetStatePropertyAll<TextStyle>(
              TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  String get _selectedPlotAId {
    switch (_selectedGroup) {
      case _TelemetryGroup.grandezas:
        return _selectedElectricalPlotAId;
      case _TelemetryGroup.eletrica:
        return _selectedElectricalPlotAId;
      case _TelemetryGroup.mecanica:
        return _selectedMechanicalPlotAId;
    }
  }

  String get _selectedPlotBId {
    switch (_selectedGroup) {
      case _TelemetryGroup.grandezas:
        return _selectedElectricalPlotBId;
      case _TelemetryGroup.eletrica:
        return _selectedElectricalPlotBId;
      case _TelemetryGroup.mecanica:
        return _selectedMechanicalPlotBId;
    }
  }

  void _setSelectedPlotAId(String id) {
    setState(() {
      switch (_selectedGroup) {
        case _TelemetryGroup.grandezas:
          _selectedElectricalPlotAId = id;
          break;
        case _TelemetryGroup.eletrica:
          _selectedElectricalPlotAId = id;
          break;
        case _TelemetryGroup.mecanica:
          _selectedMechanicalPlotAId = id;
          break;
      }
    });
  }

  void _setSelectedPlotBId(String id) {
    setState(() {
      switch (_selectedGroup) {
        case _TelemetryGroup.grandezas:
          _selectedElectricalPlotBId = id;
          break;
        case _TelemetryGroup.eletrica:
          _selectedElectricalPlotBId = id;
          break;
        case _TelemetryGroup.mecanica:
          _selectedMechanicalPlotBId = id;
          break;
      }
    });
  }

  Widget _buildChartForPlot(
    BuildContext context,
    _TelemetryPlot plot,
    TelemetrySample? sample,
    double plotHeight, {
    required String selectedPlotId,
    required List<_TelemetryPlot> plots,
    required ValueChanged<String> onPlotChanged,
  }) {
    return TelemetryChart(
      title: plot.title,
      color: plot.color,
      values: _seriesForPlot(plot),
      unit: plot.unit,
      instantValue: sample == null ? null : plot.readValue(sample),
      decimalDigits: plot.decimalDigits,
      chartHeight: plotHeight,
      titleWidget: _buildPlotTitleMenu(
        context,
        plot: plot,
        selectedPlotId: selectedPlotId,
        plots: plots,
        onPlotChanged: onPlotChanged,
      ),
    );
  }

  Widget _buildPlotTitleMenu(
    BuildContext context, {
    required _TelemetryPlot plot,
    required String selectedPlotId,
    required List<_TelemetryPlot> plots,
    required ValueChanged<String> onPlotChanged,
  }) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String titleText =
        plot.unit.isEmpty ? plot.title : '${plot.title} (${plot.unit})';

    return Builder(
      builder: (BuildContext titleContext) {
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            _openPlotMenu(
              titleContext,
              selectedPlotId: selectedPlotId,
              plots: plots,
              onPlotChanged: onPlotChanged,
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down_rounded, color: plot.color, size: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPlotMenu(
    BuildContext context, {
    required String selectedPlotId,
    required List<_TelemetryPlot> plots,
    required ValueChanged<String> onPlotChanged,
  }) async {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final Offset topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final double menuWidth =
        overlay.size.width < 260 ? overlay.size.width - 16 : 240;
    final double maxLeft = overlay.size.width - menuWidth - 8;
    final double left = topLeft.dx.clamp(8.0, maxLeft).toDouble();
    final double top =
        (topLeft.dy + button.size.height + 4)
            .clamp(8.0, overlay.size.height - 8)
            .toDouble();

    final String? selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        left,
        top,
        overlay.size.width - left - menuWidth,
        0,
      ),
      items:
          plots.map((_TelemetryPlot option) {
            final bool selected = option.id == selectedPlotId;
            return PopupMenuItem<String>(
              value: option.id,
              child: Row(
                children: <Widget>[
                  Icon(Icons.show_chart_rounded, color: option.color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_rounded,
                      color: AppTheme.brandMint,
                      size: 18,
                    ),
                ],
              ),
            );
          }).toList(),
    );

    if (!mounted || selected == null) {
      return;
    }
    onPlotChanged(selected);
  }

  List<double> _seriesForPlot(_TelemetryPlot plot) {
    return widget.controller.history
        .map((TelemetrySample sample) => plot.readValue(sample))
        .whereType<double>()
        .toList();
  }

  List<_TelemetryPlot> _plotsForGroup(_TelemetryGroup group) {
    return _telemetryPlots
        .where((_TelemetryPlot plot) => plot.group == group)
        .toList();
  }

  _TelemetryPlot _plotById(String id, List<_TelemetryPlot> plots) {
    return plots.firstWhere(
      (_TelemetryPlot plot) => plot.id == id,
      orElse: () => plots.first,
    );
  }
}
