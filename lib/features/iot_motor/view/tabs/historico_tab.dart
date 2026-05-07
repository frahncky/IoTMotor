import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/motor_command_type.dart';
import '../../models/telemetry_sample.dart';
import '../../services/telemetry_history_export.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';

class HistoricoTab extends StatelessWidget {
  const HistoricoTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  Widget build(BuildContext context) {
    final List<TelemetrySample> timeline = controller.history.reversed.toList(
      growable: false,
    );

    return SingleChildScrollView(
      key: const ValueKey<String>('tab_historico'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DelayedReveal(
                delay: const Duration(milliseconds: 200),
                child: _buildHeaderPanel(context, timeline),
              ),
              const SizedBox(height: 12),
              DelayedReveal(
                delay: const Duration(milliseconds: 250),
                child:
                    timeline.isEmpty
                        ? _buildEmptyTimeline(context)
                        : _buildTimelinePanel(context, timeline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderPanel(
    BuildContext context,
    List<TelemetrySample> timeline,
  ) {
    final int total = timeline.length;
    final String lastEntry =
        total == 0 ? '--' : _formatDateTime(timeline.first.timestamp);

    return GlassPanel(
      tint: AppTheme.brandMint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Hist\u00f3rico',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Linha do tempo dos eventos do motor.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed:
                        total == 0 ? null : () => _exportHistory(context),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Exportar CSV'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        total == 0 ? null : () => _confirmClearHistory(context),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: const Text('Limpar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              Chip(
                avatar: const Icon(Icons.timeline_rounded, size: 16),
                label: Text(total == 1 ? '1 evento' : '$total eventos'),
              ),
              Chip(
                avatar: const Icon(Icons.schedule_rounded, size: 16),
                label: Text('Ultimo registro: $lastEntry'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelinePanel(
    BuildContext context,
    List<TelemetrySample> timeline,
  ) {
    final List<Widget> items = <Widget>[];
    DateTime? currentSection;

    for (int index = 0; index < timeline.length; index++) {
      final TelemetrySample sample = timeline[index];
      final DateTime sectionDate = DateTime(
        sample.timestamp.year,
        sample.timestamp.month,
        sample.timestamp.day,
      );

      if (currentSection == null || !_isSameDay(currentSection, sectionDate)) {
        if (items.isNotEmpty) {
          items.add(const SizedBox(height: 10));
        }
        currentSection = sectionDate;
        items.add(_buildDayHeader(context, sectionDate));
        items.add(const SizedBox(height: 8));
      }

      items.add(
        _buildTimelineItem(
          context,
          sample,
          isLatest: index == 0,
          showConnector: index < timeline.length - 1,
        ),
      );

      if (index < timeline.length - 1) {
        items.add(const SizedBox(height: 8));
      }
    }

    return GlassPanel(
      tint: AppTheme.brandBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Linha do tempo', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          ...items,
        ],
      ),
    );
  }

  Widget _buildEmptyTimeline(BuildContext context) {
    return GlassPanel(
      tint: AppTheme.brandBlue,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppTheme.surfaceSoft.withValues(alpha: 0.9),
          border: Border.all(
            color: AppTheme.inputBorder.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.history_toggle_off_rounded, color: AppTheme.inkSoft),
                const SizedBox(width: 8),
                Text(
                  'Ainda sem eventos no hist\u00f3rico.',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Conecte-se ao broker para come\u00e7ar.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayHeader(BuildContext context, DateTime date) {
    return Row(
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: AppTheme.brandMint,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _dayLabel(date),
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: AppTheme.brandMint),
        ),
      ],
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    TelemetrySample sample, {
    required bool isLatest,
    required bool showConnector,
  }) {
    final _HistoryEventStyle style = _eventStyle(sample);
    final String modeLabel = _resolveModeLabel(sample.mode);
    final List<Widget> metricChips = _metricChips(sample);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 20,
          child: Column(
            children: <Widget>[
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: style.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.surfaceSoft.withValues(alpha: 0.9),
                    width: 1.6,
                  ),
                ),
              ),
              if (showConnector)
                Container(
                  width: 2,
                  height: 92,
                  margin: const EdgeInsets.only(top: 2),
                  color: style.color.withValues(alpha: 0.35),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppTheme.surfaceSoft.withValues(alpha: 0.94),
              border: Border.all(color: style.color.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(style.icon, size: 18, color: style.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _eventTitle(sample, modeLabel),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    if (isLatest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: AppTheme.brandMint.withValues(alpha: 0.18),
                        ),
                        child: Text(
                          'Agora',
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium?.copyWith(
                            color: AppTheme.brandMint,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _formatDateTime(sample.timestamp),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                if (modeLabel != '--') ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'Modo: $modeLabel',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (metricChips.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: metricChips),
                ],
              ],
            ),
          ),
        ),
      ],
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
      return 'Atualização de modo ($modeLabel)';
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

  List<Widget> _metricChips(TelemetrySample sample) {
    final List<Widget> chips = <Widget>[];

    if (sample.voltage != null) {
      chips.add(
        _MetricChip(label: 'Tens\u00e3o', color: AppTheme.voltageAccent),
      );
    }

    if (sample.current != null) {
      chips.add(_MetricChip(label: 'Corrente', color: AppTheme.currentAccent));
    }

    if (sample.vibration != null) {
      chips.add(
        _MetricChip(
          label: 'Vibra\u00e7\u00e3o',
          color: AppTheme.vibrationAccent,
        ),
      );
    }

    if (sample.temperature != null) {
      chips.add(
        _MetricChip(label: 'Temperatura', color: AppTheme.temperatureAccent),
      );
    }

    return chips;
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

  String _formatDateTime(DateTime value) {
    final String day = _twoDigits(value.day);
    final String month = _twoDigits(value.month);
    final String year = value.year.toString();
    final String hour = _twoDigits(value.hour);
    final String minute = _twoDigits(value.minute);
    final String second = _twoDigits(value.second);
    return '$day/$month/$year $hour:$minute:$second';
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
        controller.historyEntries,
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
        SnackBar(content: Text('Falha ao exportar historico: $error')),
      );
    }
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppTheme.ink,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _HistoryEventStyle {
  const _HistoryEventStyle({required this.color, required this.icon});

  final Color color;
  final IconData icon;
}
