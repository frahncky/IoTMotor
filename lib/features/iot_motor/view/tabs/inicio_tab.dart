import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/motor_command_type.dart';
import '../../models/telemetry_sample.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';
import '../widgets/telemetry_chart.dart';

enum _TelemetryPalette { eletrica, mecanica }

class InicioTab extends StatefulWidget {
  const InicioTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  State<InicioTab> createState() => _InicioTabState();
}

class _InicioTabState extends State<InicioTab> {
  static const String _addStartTypeAction = '__add_start_type__';

  String? _selectedStartTypeId;
  _TelemetryPalette _selectedPalette = _TelemetryPalette.eletrica;

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
    final List<double> voltageSeries =
        widget.controller.history
            .where((TelemetrySample entry) => entry.voltage != null)
            .map((TelemetrySample entry) => entry.voltage!)
            .toList();
    final List<double> currentSeries =
        widget.controller.history
            .where((TelemetrySample entry) => entry.current != null)
            .map((TelemetrySample entry) => entry.current!)
            .toList();
    final List<double> vibrationSeries =
        widget.controller.history
            .where((TelemetrySample entry) => entry.vibration != null)
            .map((TelemetrySample entry) => entry.vibration!)
            .toList();
    final List<double> temperatureSeries =
        widget.controller.history
            .where((TelemetrySample entry) => entry.temperature != null)
            .map((TelemetrySample entry) => entry.temperature!)
            .toList();

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
                      child: _buildChartsPanel(
                        context,
                        sample: sample,
                        voltageSeries: voltageSeries,
                        currentSeries: currentSeries,
                        vibrationSeries: vibrationSeries,
                        temperatureSeries: temperatureSeries,
                      ),
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
                              child: _buildChartsPanel(
                                context,
                                sample: sample,
                                voltageSeries: voltageSeries,
                                currentSeries: currentSeries,
                                vibrationSeries: vibrationSeries,
                                temperatureSeries: temperatureSeries,
                              ),
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

  Widget _buildPaletteSelector() {
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: 320,
        child: SegmentedButton<_TelemetryPalette>(
          showSelectedIcon: false,
          selected: <_TelemetryPalette>{_selectedPalette},
          onSelectionChanged: (Set<_TelemetryPalette> selection) {
            setState(() {
              _selectedPalette = selection.first;
            });
          },
          segments: const <ButtonSegment<_TelemetryPalette>>[
            ButtonSegment<_TelemetryPalette>(
              value: _TelemetryPalette.eletrica,
              icon: Icon(Icons.electric_bolt_rounded, size: 16),
              label: Text('El\u00e9trica'),
            ),
            ButtonSegment<_TelemetryPalette>(
              value: _TelemetryPalette.mecanica,
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

  Widget _buildChartsPanel(
    BuildContext context, {
    required TelemetrySample? sample,
    required List<double> voltageSeries,
    required List<double> currentSeries,
    required List<double> vibrationSeries,
    required List<double> temperatureSeries,
  }) {
    final bool eletrica = _selectedPalette == _TelemetryPalette.eletrica;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        Widget chartA(double plotHeight) {
          return TelemetryChart(
            title: eletrica ? 'Tens\u00e3o' : 'Vibra\u00e7\u00e3o',
            color: eletrica ? AppTheme.voltageAccent : AppTheme.vibrationAccent,
            values: eletrica ? voltageSeries : vibrationSeries,
            unit: eletrica ? 'V' : 'g',
            instantValue: eletrica ? sample?.voltage : sample?.vibration,
            decimalDigits: eletrica ? 1 : 3,
            chartHeight: plotHeight,
          );
        }

        Widget chartB(double plotHeight) {
          return TelemetryChart(
            title: eletrica ? 'Corrente' : 'Temperatura',
            color:
                eletrica ? AppTheme.currentAccent : AppTheme.temperatureAccent,
            values: eletrica ? currentSeries : temperatureSeries,
            unit: eletrica ? 'A' : '\u00b0C',
            instantValue: eletrica ? sample?.current : sample?.temperature,
            decimalDigits: eletrica ? 2 : 1,
            chartHeight: plotHeight,
          );
        }

        final bool wide = constraints.maxWidth >= 980;
        final double rawHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 620;
        const double selectorReservedHeight = 52;
        final double availableForCards = (rawHeight - selectorReservedHeight)
            .clamp(260.0, 1200.0);

        if (wide) {
          final double cardHeight = availableForCards.clamp(220.0, 420.0);
          final double plotHeight = (cardHeight - 86).clamp(84.0, 320.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildPaletteSelector(),
              const SizedBox(height: 8),
              SizedBox(
                height: cardHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: chartA(plotHeight)),
                    const SizedBox(width: 10),
                    Expanded(child: chartB(plotHeight)),
                  ],
                ),
              ),
            ],
          );
        }

        final double cardHeight = ((availableForCards - 10) / 2).clamp(
          150.0,
          360.0,
        );
        final double plotHeight = (cardHeight - 86).clamp(72.0, 250.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildPaletteSelector(),
            const SizedBox(height: 8),
            SizedBox(height: cardHeight, child: chartA(plotHeight)),
            const SizedBox(height: 10),
            SizedBox(height: cardHeight, child: chartB(plotHeight)),
          ],
        );
      },
    );
  }
}
