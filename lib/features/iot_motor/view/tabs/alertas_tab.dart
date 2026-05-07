import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/telemetry_alert.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';

class AlertasTab extends StatelessWidget {
  const AlertasTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  Widget build(BuildContext context) {
    final List<TelemetryAlert> alerts = controller.alerts;

    return SingleChildScrollView(
      key: const ValueKey<String>('tab_alertas'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 86),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: DelayedReveal(
            delay: const Duration(milliseconds: 200),
            child: GlassPanel(
              tint: AppTheme.danger,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildHeader(context),
                  const SizedBox(height: 12),
                  _buildSummary(context),
                  const SizedBox(height: 12),
                  if (alerts.isEmpty)
                    _buildEmptyState(context)
                  else
                    Column(
                      children: <Widget>[
                        for (final TelemetryAlert alert in alerts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _AlertTile(
                              alert: alert,
                              onAcknowledge:
                                  alert.acknowledged
                                      ? null
                                      : () =>
                                          controller.acknowledgeAlert(alert.id),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.notification_important_rounded, color: AppTheme.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Alertas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed:
                  controller.pendingAlertsCount == 0
                      ? null
                      : controller.acknowledgeAllAlerts,
              icon: const Icon(Icons.done_all_rounded),
              label: const Text('Reconhecer'),
            ),
            OutlinedButton.icon(
              onPressed:
                  controller.alerts.isEmpty ? null : controller.clearAlerts,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Limpar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        Chip(
          avatar: const Icon(Icons.notifications_active_rounded, size: 16),
          label: Text(controller.alertStatusSummary),
        ),
        Chip(
          avatar: const Icon(Icons.error_outline_rounded, size: 16),
          label: Text('${controller.criticalAlertsCount} críticos'),
        ),
        Chip(
          avatar: const Icon(Icons.check_circle_outline_rounded, size: 16),
          label: Text('${controller.acknowledgedAlertsCount} reconhecidos'),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.check_circle_outline_rounded, color: AppTheme.online),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Nenhum alerta registrado.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, required this.onAcknowledge});

  final TelemetryAlert alert;
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final Color color = _alertColor(alert.severity);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.surfaceSoft.withValues(alpha: 0.94),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(_alertIcon(alert.severity), color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  alert.title,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  alert.message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    Chip(label: Text(_alertSeverityLabel(alert.severity))),
                    Chip(label: Text(alert.deviceId)),
                    Chip(label: Text(alert.metric)),
                    Chip(label: Text(_formatDateTime(alert.createdAt))),
                    if (alert.acknowledged)
                      const Chip(label: Text('Reconhecido')),
                  ],
                ),
              ],
            ),
          ),
          if (onAcknowledge != null)
            IconButton(
              tooltip: 'Reconhecer',
              onPressed: onAcknowledge,
              icon: const Icon(Icons.done_rounded),
            ),
        ],
      ),
    );
  }

  IconData _alertIcon(TelemetryAlertSeverity severity) {
    switch (severity) {
      case TelemetryAlertSeverity.info:
        return Icons.info_outline_rounded;
      case TelemetryAlertSeverity.warning:
        return Icons.warning_amber_rounded;
      case TelemetryAlertSeverity.critical:
        return Icons.error_outline_rounded;
    }
  }

  Color _alertColor(TelemetryAlertSeverity severity) {
    switch (severity) {
      case TelemetryAlertSeverity.info:
        return AppTheme.brandBlue;
      case TelemetryAlertSeverity.warning:
        return AppTheme.brandOrange;
      case TelemetryAlertSeverity.critical:
        return AppTheme.danger;
    }
  }

  String _alertSeverityLabel(TelemetryAlertSeverity severity) {
    switch (severity) {
      case TelemetryAlertSeverity.info:
        return 'Informativo';
      case TelemetryAlertSeverity.warning:
        return 'Atenção';
      case TelemetryAlertSeverity.critical:
        return 'Crítico';
    }
  }

  String _formatDateTime(DateTime value) {
    final String day = value.day.toString().padLeft(2, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }
}
