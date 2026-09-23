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
import '../widgets/telemetry_chart.dart';
import 'grandezas_tab.dart';

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
    label: 'Freq.',
    title: 'Freq.',
    unit: 'Hz',
    color: AppTheme.brandBlue,
    decimalDigits: 2,
    readValue: (TelemetrySample sample) => sample.frequency,
  ),
  _TelemetryPlot(
    id: 'vibration',
    group: _TelemetryGroup.mecanica,
    label: 'Vibra.',
    title: 'Vibra.',
    unit: 'g',
    color: AppTheme.vibrationAccent,
    decimalDigits: 3,
    readValue: (TelemetrySample sample) => sample.vibration,
  ),
  _TelemetryPlot(
    id: 'temperature',
    group: _TelemetryGroup.mecanica,
    label: 'Temp.',
    title: 'Temp.',
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
    final bool motorOn = widget.controller.isBenchMotorOn;
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      type.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    // Contatores que esta partida aciona.
                                    Text(
                                      type.profileSummary,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
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

  /// Editor de partidas: cada contator com o instante em que liga e em que
  /// desliga. A partida é gravada no ESP32, então vale também no painel.
  Future<void> _openStartTypeEditor({
    required BuildContext context,
    MotorCommandType? initial,
  }) async {
    String label = initial?.label ?? '';
    final List<ContactorTiming> tempos = List<ContactorTiming>.generate(4, (int i) {
      final List<ContactorTiming>? atuais = initial?.timings;
      if (atuais != null && i < atuais.length) return atuais[i];
      return ContactorTiming(use: i == 0, onMs: 500, offMs: 0);
    });

    String? problema() {
      if (label.trim().isEmpty) return 'Informe o nome da partida.';
      if (!tempos.any((ContactorTiming t) => t.use)) return 'Marque pelo menos um contator.';
      for (int i = 0; i < tempos.length; i++) {
        final ContactorTiming t = tempos[i];
        if (!t.use) continue;
        if (t.offMs != 0 && t.offMs <= t.onMs) {
          return 'CNT ${i + 1}: desligar depois de ligar (ou 0 para ficar ligado).';
        }
      }
      return null;
    }

    Widget campoDeTempo(String rotulo, int valorMs, ValueChanged<int> aoMudar) {
      return SizedBox(
        width: 104,
        child: TextFormField(
          initialValue: (valorMs / 1000).toString(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: rotulo, suffixText: 's'),
          onChanged: (String texto) {
            final double? s = double.tryParse(texto.replaceAll(',', '.'));
            if (s != null && s >= 0 && s <= 300) aoMudar((s * 1000).round());
          },
        ),
      );
    }

    final bool? salvar = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter atualizar) {
            final String? erro = problema();
            return AlertDialog(
              title: Text(initial == null ? 'Nova partida' : 'Editar partida'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextFormField(
                        initialValue: label,
                        autofocus: initial == null,
                        // A placa guarda 24 bytes, e cada acento ocupa dois.
                        maxLength: 24,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        validator: (String? valor) {
                          final String nome = (valor ?? '').trim();
                          if (nome.isEmpty) return 'Informe o nome da partida.';
                          final int bytes = utf8.encode(nome).length;
                          return bytes > 24
                              ? 'Nome comprido para a placa ($bytes de 24; '
                                  'cada acento conta dois).'
                              : null;
                        },
                        onChanged: (String value) => atualizar(() => label = value),
                        decoration: const InputDecoration(
                          labelText: 'Nome da partida',
                          hintText: 'Ex.: Estrela-triângulo 8 s',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tempos contados do início da partida. Desligar em 0 = '
                        'o contator fica ligado até você parar.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      for (int i = 0; i < 4; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: <Widget>[
                              SizedBox(
                                width: 112,
                                child: CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  title: Text('CNT ${i + 1}'),
                                  value: tempos[i].use,
                                  onChanged: (bool? marcado) => atualizar(() {
                                    tempos[i] = ContactorTiming(
                                      use: marcado ?? false,
                                      onMs: tempos[i].onMs,
                                      offMs: tempos[i].offMs,
                                    );
                                  }),
                                ),
                              ),
                              const SizedBox(width: 6),
                              campoDeTempo('Liga', tempos[i].onMs, (int ms) => atualizar(() {
                                tempos[i] = ContactorTiming(
                                  use: tempos[i].use,
                                  onMs: ms,
                                  offMs: tempos[i].offMs,
                                );
                              })),
                              const SizedBox(width: 10),
                              campoDeTempo('Desliga', tempos[i].offMs, (int ms) => atualizar(() {
                                tempos[i] = ContactorTiming(
                                  use: tempos[i].use,
                                  onMs: tempos[i].onMs,
                                  offMs: ms,
                                );
                              })),
                            ],
                          ),
                        ),
                      if (erro != null)
                        Text(
                          erro,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: erro == null ? () => Navigator.of(dialogContext).pop(true) : null,
                  child: const Text('Salvar na placa'),
                ),
              ],
            );
          },
        );
      },
    );

    if (salvar != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.saveStartTypeOnBoard(
        id: initial?.id ?? '',
        label: label,
        timings: tempos,
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
    final Widget panel = GrandezasTab(
      controller: widget.controller,
      showHeader: false,
      padding: EdgeInsets.zero,
    );

    if (!constraints.maxHeight.isFinite) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildGroupSelector(),
          const SizedBox(height: 8),
          SizedBox(height: 360, child: panel),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildGroupSelector(),
        const SizedBox(height: 8),
        Expanded(child: panel),
      ],
    );
  }

  Widget _buildGroupSelector() {
    return Align(
      alignment: Alignment.center,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<_TelemetryGroup>(
          showSelectedIcon: false,
          selected: <_TelemetryGroup>{_selectedGroup},
          onSelectionChanged: (Set<_TelemetryGroup> selection) {
            widget.controller.setDashboardTab(
              _dashboardTabForGroup(selection.first),
            );
          },
          segments: const <ButtonSegment<_TelemetryGroup>>[
            ButtonSegment<_TelemetryGroup>(
              value: _TelemetryGroup.grandezas,
              icon: Icon(Icons.speed_rounded, size: 16),
              label: Text('Medições'),
            ),
            ButtonSegment<_TelemetryGroup>(
              value: _TelemetryGroup.eletrica,
              icon: Icon(Icons.electric_bolt_rounded, size: 16),
              label: Text('Elétrica'),
            ),
            ButtonSegment<_TelemetryGroup>(
              value: _TelemetryGroup.mecanica,
              icon: Icon(Icons.sensors_rounded, size: 16),
              label: Text('Mecânica'),
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
        return widget.controller.electricalPlotAId;
      case _TelemetryGroup.eletrica:
        return widget.controller.electricalPlotAId;
      case _TelemetryGroup.mecanica:
        return widget.controller.mechanicalPlotAId;
    }
  }

  String get _selectedPlotBId {
    switch (_selectedGroup) {
      case _TelemetryGroup.grandezas:
        return widget.controller.electricalPlotBId;
      case _TelemetryGroup.eletrica:
        return widget.controller.electricalPlotBId;
      case _TelemetryGroup.mecanica:
        return widget.controller.mechanicalPlotBId;
    }
  }

  void _setSelectedPlotAId(String id) {
    switch (_selectedGroup) {
      case _TelemetryGroup.grandezas:
        widget.controller.setElectricalPlotAId(id);
        break;
      case _TelemetryGroup.eletrica:
        widget.controller.setElectricalPlotAId(id);
        break;
      case _TelemetryGroup.mecanica:
        widget.controller.setMechanicalPlotAId(id);
        break;
    }
  }

  void _setSelectedPlotBId(String id) {
    switch (_selectedGroup) {
      case _TelemetryGroup.grandezas:
        widget.controller.setElectricalPlotBId(id);
        break;
      case _TelemetryGroup.eletrica:
        widget.controller.setElectricalPlotBId(id);
        break;
      case _TelemetryGroup.mecanica:
        widget.controller.setMechanicalPlotBId(id);
        break;
    }
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
    final bool connected = widget.controller.isConnected;
    final bool recebeuDadoAtual = widget.controller.recebeuDadoAtual;
    final List<double> values = _seriesForPlot(plot);
    // Só mostra valores se já recebeu dado novo na sessão atual
    final List<double> sessionValues = (connected && recebeuDadoAtual) ? values : <double>[];
    return TelemetryChart(
      title: plot.title,
      color: plot.color,
      values: sessionValues,
      unit: plot.unit,
      instantValue: (connected && recebeuDadoAtual && sample != null) ? plot.readValue(sample) : null,
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

  _TelemetryGroup _groupFromDashboardTab(String value) {
    switch (value) {
      case MotorControlController.dashboardTabElectrical:
        return _TelemetryGroup.eletrica;
      case MotorControlController.dashboardTabMechanical:
        return _TelemetryGroup.mecanica;
      case MotorControlController.dashboardTabMeasurements:
      default:
        return _TelemetryGroup.grandezas;
    }
  }

  String _dashboardTabForGroup(_TelemetryGroup group) {
    switch (group) {
      case _TelemetryGroup.grandezas:
        return MotorControlController.dashboardTabMeasurements;
      case _TelemetryGroup.eletrica:
        return MotorControlController.dashboardTabElectrical;
      case _TelemetryGroup.mecanica:
        return MotorControlController.dashboardTabMechanical;
    }
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
