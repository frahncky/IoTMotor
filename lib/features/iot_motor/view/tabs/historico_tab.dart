import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/motor_command_type.dart';
import '../../models/telemetry_history_entry.dart';
import '../../models/telemetry_sample.dart';
import '../../services/telemetry_history_export.dart';
import '../widgets/board_history_panel.dart';
import '../widgets/app_section.dart';

class HistoricoTab extends StatelessWidget {
  const HistoricoTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  Widget build(BuildContext context) {
    final List<TelemetryHistoryEntry> timeline = controller
        .filteredHistoryEntries
        .reversed
        .toList(growable: false);

    return ListView(
      key: const ValueKey<String>('tab_historico'),
      padding: appPagePadding,
      children: <Widget>[
        BoardHistoryPanel(horas: controller.boardHistory),
        appSectionGap,
        _buildEventsSection(context, timeline),
      ],
    );
  }

  Widget _buildEventsSection(
    BuildContext context,
    List<TelemetryHistoryEntry> timeline,
  ) {
    final int total = timeline.length;
    final String totalLabel =
        controller.hasActiveHistoryFilters
            ? '$total de ${controller.historyEntryCount} eventos'
            : (total == 1 ? '1 evento' : '$total eventos');

    return AppSection(
      title: 'Eventos',
      subtitle: totalLabel,
      trailing: PopupMenuButton<String>(
        key: const ValueKey<String>('historico_menu'),
        tooltip: 'Mais opções',
        enabled: total > 0,
        onSelected: (String acao) {
          if (acao == 'exportar') _exportHistory(context);
          if (acao == 'limpar') _confirmClearHistory(context);
        },
        itemBuilder:
            (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'exportar',
                child: Text('Exportar CSV'),
              ),
              PopupMenuItem<String>(
                value: 'limpar',
                child: Text('Limpar histórico'),
              ),
            ],
      ),
      children: <Widget>[
        _buildFilterControls(context),
        const SizedBox(height: 8),
        if (timeline.isEmpty)
          _buildEmptyTimeline(context)
        else
          ..._buildTimeline(context, timeline),
      ],
    );
  }

  List<Widget> _buildTimeline(
    BuildContext context,
    List<TelemetryHistoryEntry> timeline,
  ) {
    final List<Widget> items = <Widget>[];
    DateTime? currentSection;
    // A lista pode ser longa: mostra os mais recentes e avisa o resto.
    const int limite = 200;
    final int mostrar = timeline.length < limite ? timeline.length : limite;

    for (int index = 0; index < mostrar; index++) {
      final TelemetryHistoryEntry entry = timeline[index];
      final TelemetrySample sample = entry.sample;
      final DateTime sectionDate = DateTime(
        sample.timestamp.year,
        sample.timestamp.month,
        sample.timestamp.day,
      );

      if (currentSection == null || !_isSameDay(currentSection, sectionDate)) {
        currentSection = sectionDate;
        items.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(
              _dayLabel(sectionDate),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppTheme.inkSoft),
            ),
          ),
        );
      }
      items.add(_buildTimelineItem(context, entry));
    }
    if (timeline.length > mostrar) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Mostrando os $mostrar mais recentes. Exporte o CSV para ver tudo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return items;
  }

  Widget _buildEmptyTimeline(BuildContext context) {
    final bool hasStoredHistory = controller.historyEntryCount > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        hasStoredHistory
            ? 'Nenhum evento para esses filtros.'
            : 'Ainda sem eventos. Eles aparecem aqui quando o app recebe dados das placas.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildTimelineItem(BuildContext context, TelemetryHistoryEntry entry) {
    final TelemetrySample sample = entry.sample;
    final _HistoryEventStyle style = _eventStyle(sample);
    final String modeLabel = _resolveModeLabel(sample.mode);
    final TextTheme texto = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(style.icon, size: 22, color: style.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _eventTitle(sample, modeLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: texto.bodyLarge?.copyWith(color: AppTheme.ink),
                ),
                Text(
                  entry.deviceId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: texto.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_formatTime(sample.timestamp), style: texto.bodySmall),
        ],
      ),
    );
  }

  String _eventTitle(TelemetrySample sample, String modeLabel) {
    if (sample.motorOn == true) {
      if (modeLabel != '--') {
        return 'Motor ligado ($modeLabel)';
      }
      return 'Motor ligado';
    }

    if (sample.motorOn == false) {
      return 'Motor desligado';
    }

    if (modeLabel != '--') {
      return 'Modo $modeLabel';
    }

    return 'Leitura registrada';
  }

  _HistoryEventStyle _eventStyle(TelemetrySample sample) {
    if (sample.motorOn == true) {
      return _HistoryEventStyle(
        color: AppTheme.online,
        icon: Icons.play_circle_fill_rounded,
      );
    }

    if (sample.motorOn == false) {
      return _HistoryEventStyle(
        color: AppTheme.offline,
        icon: Icons.pause_circle_filled_rounded,
      );
    }

    final String mode = sample.mode?.trim() ?? '';
    if (mode.isNotEmpty) {
      return _HistoryEventStyle(
        color: AppTheme.brandBlue,
        icon: Icons.sync_alt_rounded,
      );
    }

    return _HistoryEventStyle(
      color: AppTheme.inkSoft,
      icon: Icons.memory_rounded,
    );
  }

  String _resolveModeLabel(String? rawMode) {
    final String mode = rawMode?.trim() ?? '';
    if (mode.isEmpty) {
      return '--';
    }

    for (final MotorCommandType type in controller.startTypes) {
      if (type.mode == mode) {
        return type.label;
      }
    }

    return mode;
  }

  String _formatTime(DateTime value) {
    return '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  }

  String _dayLabel(DateTime date) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime yesterday = today.subtract(const Duration(days: 1));

    if (_isSameDay(date, today)) {
      return 'Hoje';
    }
    if (_isSameDay(date, yesterday)) {
      return 'Ontem';
    }

    final String day = _twoDigits(date.day);
    final String month = _twoDigits(date.month);
    final String year = date.year.toString();
    return '$day/$month/$year';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  Future<void> _confirmClearHistory(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Limpar hist\u00f3rico'),
          content: const Text('Deseja remover todos os eventos?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Limpar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    controller.clearHistory();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Hist\u00f3rico limpo.')));
  }

  Future<void> _exportHistory(BuildContext context) async {
    try {
      final String result = await exportTelemetryHistoryCsv(
        controller.filteredHistoryEntries,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao exportar histórico: $error')),
      );
    }
  }

  Widget _buildFilterControls(BuildContext context) {
    final List<_FilterOption> deviceOptions = <_FilterOption>[
      const _FilterOption(MotorControlController.historyFilterAll, 'Todas'),
      for (final String deviceId in controller.knownDeviceIds)
        _FilterOption(deviceId, deviceId),
    ];

    final Widget dispositivo = _FilterMenu(
      label: 'Placa',
      value: controller.historyDeviceFilter,
      options: deviceOptions,
      onSelected: controller.setHistoryDeviceFilter,
    );
    final Widget periodo = _FilterMenu(
      label: 'Período',
      value: controller.historyPeriodFilter,
      options: const <_FilterOption>[
        _FilterOption(MotorControlController.historyFilterAll, 'Tudo'),
        _FilterOption(MotorControlController.historyPeriodToday, 'Hoje'),
        _FilterOption(
          MotorControlController.historyPeriodLastHour,
          'Última hora',
        ),
        _FilterOption(
          MotorControlController.historyPeriodLast24Hours,
          'Últimas 24h',
        ),
      ],
      onSelected: controller.setHistoryPeriodFilter,
    );
    final Widget metrica = _FilterMenu(
      label: 'Medida',
      value: controller.historyMetricFilter,
      options: const <_FilterOption>[
        _FilterOption(MotorControlController.historyFilterAll, 'Todas'),
        _FilterOption(MotorControlController.historyMetricVoltage, 'Tensão'),
        _FilterOption(MotorControlController.historyMetricCurrent, 'Corrente'),
        _FilterOption(MotorControlController.historyMetricPower, 'Potência'),
        _FilterOption(MotorControlController.historyMetricPowerFactor, 'FP'),
        _FilterOption(
          MotorControlController.historyMetricFrequency,
          'Frequência',
        ),
        _FilterOption(MotorControlController.historyMetricEnergy, 'Energia'),
        _FilterOption(
          MotorControlController.historyMetricVibration,
          'Vibração',
        ),
        _FilterOption(
          MotorControlController.historyMetricTemperature,
          'Temperatura',
        ),
      ],
      onSelected: controller.setHistoryMetricFilter,
    );
    final Widget estado = _FilterMenu(
      label: 'Motor',
      value: controller.historyStateFilter,
      options: const <_FilterOption>[
        _FilterOption(MotorControlController.historyFilterAll, 'Todos'),
        _FilterOption(MotorControlController.historyStateOn, 'Ligado'),
        _FilterOption(MotorControlController.historyStateOff, 'Desligado'),
        _FilterOption(MotorControlController.historyStateUnknown, 'Sem estado'),
      ],
      onSelected: controller.setHistoryStateFilter,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: dispositivo),
            const SizedBox(width: 8),
            Expanded(child: periodo),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(child: metrica),
            const SizedBox(width: 8),
            Expanded(child: estado),
          ],
        ),
        if (controller.hasActiveHistoryFilters)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: controller.clearHistoryFilters,
              child: const Text('Limpar filtros'),
            ),
          ),
      ],
    );
  }
}

class _HistoryEventStyle {
  const _HistoryEventStyle({required this.color, required this.icon});

  final Color color;
  final IconData icon;
}

class _FilterOption {
  const _FilterOption(this.value, this.label);

  final String value;
  final String label;
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final String value;
  final List<_FilterOption> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final _FilterOption selected = options.firstWhere(
      (_FilterOption option) => option.value == value,
      orElse: () => options.first,
    );
    final TextTheme texto = Theme.of(context).textTheme;

    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder:
          (BuildContext context) => options
              .map(
                (_FilterOption option) => CheckedPopupMenuItem<String>(
                  value: option.value,
                  checked: option.value == selected.value,
                  child: Text(option.label),
                ),
              )
              .toList(growable: false),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.inputBorder),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(label, style: texto.labelSmall),
                  Text(
                    selected.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texto.bodyMedium?.copyWith(color: AppTheme.ink),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: AppTheme.inkSoft),
          ],
        ),
      ),
    );
  }
}
