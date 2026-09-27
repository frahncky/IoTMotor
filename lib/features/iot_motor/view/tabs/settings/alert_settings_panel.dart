import 'package:flutter/material.dart';
import '../../../../../app/theme/app_theme.dart';
import '../../../controller/motor_control_controller.dart';
import '../../../models/telemetry_alert.dart';
import '../../../services/mqtt_settings_validators.dart';
import '../../widgets/glass_panel.dart';
import 'settings_common.dart';

/// Aba "Alertas": limites de alerta no app e histórico de alertas.
class AlertSettingsPanel extends StatefulWidget {
  const AlertSettingsPanel({super.key, required this.controller});

  final MotorControlController controller;

  @override
  State<AlertSettingsPanel> createState() => _AlertSettingsPanelState();
}

class _AlertSettingsPanelState extends State<AlertSettingsPanel> {
  MotorControlController get controller => widget.controller;

  @override
  Widget build(BuildContext context) => _buildAlertPanel(context);

  Widget _buildAlertPanel(BuildContext context) {
    final TelemetryAlert? latestAlert = controller.latestAlert;
    final String? thresholdError = controller.alertThresholdsError;
    final List<TelemetryAlert> recentAlerts = controller.alerts
        .take(3)
        .toList(growable: false);

    return GlassPanel(
      tint: AppTheme.danger,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double fieldWidth = fieldWidthFor(constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: buildPanelTitle(
                      context,
                      icon: Icons.notification_important_rounded,
                      color: AppTheme.danger,
                      title: 'Alertas de Telemetria',
                      subtitle:
                          'Limites operacionais usados nas leituras recebidas.',
                    ),
                  ),
                  Switch(
                    value: controller.telemetryAlertsEnabled,
                    onChanged: controller.setTelemetryAlertsEnabled,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _textField(
                    width: fieldWidth,
                    label: 'Tensão mínima',
                    controllerField: controller.voltageMinController,
                    keyboardType: TextInputType.number,
                    suffixText: 'V',
                    validator:
                        (String? value) =>
                            MqttSettingsValidators.validateDecimal(
                              value,
                              fieldLabel: 'a tensão mínima',
                              min: 0,
                              allowZero: false,
                            ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Tensão máxima',
                    controllerField: controller.voltageMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'V',
                    validator:
                        (String? value) =>
                            MqttSettingsValidators.validateDecimal(
                              value,
                              fieldLabel: 'a tensão máxima',
                              min: 0,
                              allowZero: false,
                            ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Corrente máxima',
                    controllerField: controller.currentMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'A',
                    validator:
                        (String? value) =>
                            MqttSettingsValidators.validateDecimal(
                              value,
                              fieldLabel: 'o limite de corrente',
                              min: 0,
                              allowZero: false,
                            ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Vibração máxima',
                    controllerField: controller.vibrationMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'mm/s',
                    validator:
                        (String? value) =>
                            MqttSettingsValidators.validateDecimal(
                              value,
                              fieldLabel: 'o limite de vibração',
                              min: 0,
                              allowZero: false,
                            ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Temperatura máxima',
                    controllerField: controller.temperatureMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'C',
                    validator:
                        (String? value) =>
                            MqttSettingsValidators.validateDecimal(
                              value,
                              fieldLabel: 'o limite de temperatura',
                              min: 0,
                              allowZero: false,
                            ),
                  ),
                ],
              ),
              if (thresholdError != null) ...<Widget>[
                const SizedBox(height: 10),
                buildInlineNotice(
                  context,
                  icon: Icons.warning_amber_rounded,
                  color: AppTheme.danger,
                  text: thresholdError,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Chip(
                    avatar: const Icon(Icons.notifications_active, size: 16),
                    label: Text(controller.alertStatusSummary),
                  ),
                  if (latestAlert != null)
                    Chip(
                      avatar: Icon(_alertIcon(latestAlert.severity), size: 16),
                      label: Text('Último: ${latestAlert.title}'),
                    ),
                  OutlinedButton.icon(
                    onPressed:
                        controller.alerts.isEmpty
                            ? null
                            : controller.clearAlerts,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Limpar alertas'),
                  ),
                ],
              ),
              if (recentAlerts.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Column(
                  children: <Widget>[
                    for (final TelemetryAlert alert in recentAlerts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildAlertTile(context, alert),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildAlertTile(BuildContext context, TelemetryAlert alert) {
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
          Icon(_alertIcon(alert.severity), color: color, size: 20),
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
                    Chip(label: Text(_formatDateTime(alert.createdAt))),
                    if (alert.acknowledged)
                      const Chip(label: Text('Reconhecido')),
                  ],
                ),
              ],
            ),
          ),
          if (!alert.acknowledged)
            IconButton(
              tooltip: 'Reconhecer',
              onPressed: () => controller.acknowledgeAlert(alert.id),
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

  Widget _textField({
    required double width,
    required String label,
    required TextEditingController controllerField,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? suffixText,
    String? helperText,
  }) {
    return settingsTextField(
      width: width,
      label: label,
      controllerField: controllerField,
      keyboardType: keyboardType,
      validator: validator,
      suffixText: suffixText,
      helperText: helperText,
      onChanged: () {
        setState(() {});
        controller.refreshPreview();
      },
    );
  }
}
