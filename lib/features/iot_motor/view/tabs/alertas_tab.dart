import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/telemetry_alert.dart';
import '../widgets/board_alarms_panel.dart';
import '../widgets/app_section.dart';

class AlertasTab extends StatelessWidget {
  const AlertasTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  Widget build(BuildContext context) {
    final List<TelemetryAlert> alerts = controller.alerts;

    return ListView(
      key: const ValueKey<String>('tab_alertas'),
      padding: appPagePadding,
      children: <Widget>[
        BoardAlarmsPanel(controller: controller),
        appSectionGap,
        AppSection(
          title: 'Avisos recebidos',
          subtitle:
              controller.pendingAlertsCount == 0
                  ? null
                  : '${controller.pendingAlertsCount} sem reconhecer',
          trailing: PopupMenuButton<String>(
            key: const ValueKey<String>('alertas_menu'),
            tooltip: 'Mais opções',
            enabled: alerts.isNotEmpty,
            onSelected: (String acao) {
              if (acao == 'reconhecer') controller.acknowledgeAllAlerts();
              if (acao == 'limpar') controller.clearAlerts();
            },
            itemBuilder:
                (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'reconhecer',
                    enabled: controller.pendingAlertsCount > 0,
                    child: const Text('Reconhecer todos'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'limpar',
                    child: Text('Limpar avisos'),
                  ),
                ],
          ),
          children: <Widget>[
            if (alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nenhum alerta registrado.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              for (final TelemetryAlert alert in alerts)
                _AlertTile(
                  alert: alert,
                  onAcknowledge:
                      alert.acknowledged
                          ? null
                          : () => controller.acknowledgeAlert(alert.id),
                ),
          ],
        ),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, required this.onAcknowledge});

  final TelemetryAlert alert;
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final Color color =
        alert.acknowledged ? AppTheme.inkSoft : _alertColor(alert.severity);
    final TextTheme texto = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_alertIcon(alert.severity), color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  alert.title,
                  style: texto.bodyLarge?.copyWith(color: AppTheme.ink),
                ),
                const SizedBox(height: 2),
                Text(alert.message, style: texto.bodySmall),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    _formatDateTime(alert.createdAt),
                    alert.deviceId,
                    if (alert.acknowledged) 'reconhecido',
                  ].join(' · '),
                  style: texto.bodySmall?.copyWith(color: AppTheme.labelSoft),
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

  String _formatDateTime(DateTime value) {
    final String day = value.day.toString().padLeft(2, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }
}
