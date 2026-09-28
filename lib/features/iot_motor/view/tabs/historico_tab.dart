import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/motor_command_type.dart';
import '../../models/telemetry_history_entry.dart';
import '../../models/device_names.dart';
import '../../services/telemetry_history_export.dart';
import '../widgets/board_history_panel.dart';
import '../widgets/app_section.dart';

class HistoricoTab extends StatelessWidget {
  const HistoricoTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  Widget build(BuildContext context) {
    // Mais recentes primeiro.
    final List<HistoryEvent> eventos = controller.historyEvents.reversed.toList(
      growable: false,
    );

    return ListView(
      key: const ValueKey<String>('tab_historico'),
      padding: appPagePadding,
      children: <Widget>[
        BoardHistoryPanel(horas: controller.boardHistory),
        appSectionGap,
        _buildEventsSection(context, eventos),
      ],
    );
  }

  Widget _buildEventsSection(BuildContext context, List<HistoryEvent> eventos) {
    final int total = eventos.length;
    final bool temLeituras = controller.filteredHistoryEntries.isNotEmpty;

    return AppSection(
      title: 'Eventos do motor',
      subtitle:
          total == 0 ? null : (total == 1 ? '1 evento' : '$total eventos'),
      trailing: PopupMenuButton<String>(
        key: const ValueKey<String>('historico_menu'),
        tooltip: 'Mais opções',
        enabled: temLeituras,
        onSelected: (String acao) {
          if (acao == 'exportar') _exportHistory(context);
          if (acao == 'limpar') _confirmClearHistory(context);
        },
        itemBuilder:
            (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'exportar',
                child: Text('Exportar leituras (CSV)'),
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
        if (eventos.isEmpty)
          _buildEmpty(context)
        else
          ..._buildTimeline(context, eventos),
      ],
    );
  }

  List<Widget> _buildTimeline(
    BuildContext context,
    List<HistoryEvent> eventos,
  ) {
    final List<Widget> items = <Widget>[];
    DateTime? currentSection;
    // A lista pode ser longa: mostra os mais recentes e avisa o resto.
    const int limite = 200;
    final int mostrar = eventos.length < limite ? eventos.length : limite;

    for (int index = 0; index < mostrar; index++) {
      final HistoryEvent evento = eventos[index];
      final DateTime sectionDate = DateTime(
        evento.time.year,
        evento.time.month,
        evento.time.day,
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
      items.add(_buildEventItem(context, evento));
    }
    if (eventos.length > mostrar) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Mostrando os $mostrar mais recentes.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return items;
  }

  Widget _buildEmpty(BuildContext context) {
    final bool hasStoredHistory = controller.historyEntryCount > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        hasStoredHistory
            ? 'O motor não ligou nem desligou neste período.'
            : 'Ainda sem eventos. Eles aparecem aqui quando o motor liga ou desliga.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildEventItem(BuildContext context, HistoryEvent evento) {
    final TextTheme texto = Theme.of(context).textTheme;
    final String modo = _resolveModeLabel(evento.mode);
    final (
      String titulo,
      String? detalhe,
      IconData icone,
      Color cor,
    ) = switch (evento.kind) {
      HistoryEventKind.ligou => (
        'Motor ligado',
        modo == '--' ? null : 'Partida: $modo',
        Icons.play_circle_fill_rounded,
        AppTheme.online,
      ),
      HistoryEventKind.desligou => (
        'Motor desligado',
        evento.ligadoPor == null || evento.ligadoPor!.inSeconds < 1
            ? null
            : 'Ficou ligado ${_formatDuration(evento.ligadoPor!)}',
        Icons.stop_circle_rounded,
        AppTheme.offline,
      ),
      HistoryEventKind.modo => (
        'Modo alterado',
        modo == '--' ? null : modo,
        Icons.sync_alt_rounded,
        AppTheme.brandBlue,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(icone, size: 22, color: cor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  titulo,
                  style: texto.bodyLarge?.copyWith(color: AppTheme.ink),
                ),
                if (detalhe != null)
                  Text(
                    detalhe,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texto.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_formatTime(evento.time), style: texto.bodySmall),
        ],
      ),
    );
  }

  /// "45 s", "12 min", "2 h 05 min".
  String _formatDuration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} s';
    if (d.inHours < 1) return '${d.inMinutes} min';
    return '${d.inHours} h ${_twoDigits(d.inMinutes % 60)} min';
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
        _FilterOption(deviceId, nomeDaPlaca(deviceId)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _FilterMenu(
                label: 'Placa',
                value: controller.historyDeviceFilter,
                options: deviceOptions,
                onSelected: controller.setHistoryDeviceFilter,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FilterMenu(
                label: 'Período',
                value: controller.historyPeriodFilter,
                options: const <_FilterOption>[
                  _FilterOption(
                    MotorControlController.historyFilterAll,
                    'Tudo',
                  ),
                  _FilterOption(
                    MotorControlController.historyPeriodToday,
                    'Hoje',
                  ),
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
              ),
            ),
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
