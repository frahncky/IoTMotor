import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/telemetry_alert.dart';
import '../../services/mqtt_settings_validators.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';

class ConfiguracoesTab extends StatelessWidget {
  const ConfiguracoesTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey<String>('tab_configuracoes'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DelayedReveal(
                delay: const Duration(milliseconds: 200),
                child: _buildConnectionPanel(context),
              ),
              const SizedBox(height: 12),
              DelayedReveal(
                delay: const Duration(milliseconds: 250),
                child: _buildAlertPanel(context),
              ),
              const SizedBox(height: 12),
              DelayedReveal(
                delay: const Duration(milliseconds: 300),
                child: _buildTelemetryFormatPanel(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionPanel(BuildContext context) {
    return GlassPanel(
      tint: AppTheme.brandBlue,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double fieldWidth = _fieldWidthFor(constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Conex\u00e3o MQTT',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _textField(
                    width: fieldWidth,
                    label: 'Broker host',
                    controller: controller.brokerController,
                    errorText: MqttSettingsValidators.validateBroker(
                      controller.brokerController.text,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Porta',
                    controller: controller.portController,
                    keyboardType: TextInputType.number,
                    errorText: MqttSettingsValidators.validatePort(
                      controller.portController.text,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Client ID',
                    controller: controller.clientIdController,
                    errorText: MqttSettingsValidators.validateClientId(
                      controller.clientIdController.text,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Topic prefix',
                    controller: controller.topicPrefixController,
                    errorText: MqttSettingsValidators.validateTopicPrefix(
                      controller.topicPrefixController.text,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Usu\u00e1rio (opcional)',
                    controller: controller.usernameController,
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Senha (opcional)',
                    controller: controller.passwordController,
                    obscureText: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: AppTheme.brandBlue.withValues(alpha: 0.12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Switch(
                          value: controller.useTls,
                          onChanged: controller.setTls,
                        ),
                        Text(controller.useTls ? 'TLS ativo' : 'TLS inativo'),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed:
                        controller.isBusy
                            ? null
                            : (controller.isConnected
                                ? controller.disconnect
                                : controller.connect),
                    icon: Icon(
                      controller.isConnected
                          ? Icons.link_off_rounded
                          : Icons.cloud_done_rounded,
                    ),
                    label: Text(
                      controller.isBusy
                          ? 'Conectando...'
                          : (controller.isConnected
                              ? 'Desconectar'
                              : 'Conectar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: controller.clearHistory,
                icon: const Icon(Icons.auto_graph_rounded),
                label: const Text('Limpar hist\u00f3rico'),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: AppTheme.surfaceSoft.withValues(alpha: 0.94),
                  border: Border.all(
                    color: AppTheme.brandBlue.withValues(alpha: 0.36),
                  ),
                ),
                child: SelectableText(
                  'T\u00f3pico de comando: ${controller.commandTopic}\n'
                  'T\u00f3pico de telemetria: ${controller.telemetryTopic}\n'
                  'T\u00f3pico de status: ${controller.statusTopic}\n'
                  'T\u00f3pico de solicita\u00e7\u00e3o: ${controller.telemetryRequestTopic}\n'
                  'Dispositivos conectados: ${controller.connectedDeviceIds.isEmpty ? '--' : controller.connectedDeviceIds.join(', ')}\n'
                  'Dispositivos conhecidos: ${controller.knownDeviceIds.isEmpty ? '--' : controller.knownDeviceIds.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: AppTheme.inkSoft,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

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
          final double fieldWidth = _fieldWidthFor(constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Alertas de Telemetria',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Limites operacionais usados nas leituras recebidas.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
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
                    label: 'Tensao minima',
                    controller: controller.voltageMinController,
                    keyboardType: TextInputType.number,
                    suffixText: 'V',
                    errorText: MqttSettingsValidators.validateDecimal(
                      controller.voltageMinController.text,
                      fieldLabel: 'a tensao minima',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Tensao maxima',
                    controller: controller.voltageMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'V',
                    errorText: MqttSettingsValidators.validateDecimal(
                      controller.voltageMaxController.text,
                      fieldLabel: 'a tensao maxima',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Corrente maxima',
                    controller: controller.currentMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'A',
                    errorText: MqttSettingsValidators.validateDecimal(
                      controller.currentMaxController.text,
                      fieldLabel: 'o limite de corrente',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Vibracao maxima',
                    controller: controller.vibrationMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'g',
                    errorText: MqttSettingsValidators.validateDecimal(
                      controller.vibrationMaxController.text,
                      fieldLabel: 'o limite de vibracao',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Temperatura maxima',
                    controller: controller.temperatureMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'C',
                    errorText: MqttSettingsValidators.validateDecimal(
                      controller.temperatureMaxController.text,
                      fieldLabel: 'o limite de temperatura',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                ],
              ),
              if (thresholdError != null) ...<Widget>[
                const SizedBox(height: 10),
                _buildInlineNotice(
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
                      label: Text('Ultimo: ${latestAlert.title}'),
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

  Widget _buildInlineNotice(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
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

  Widget _buildTelemetryFormatPanel(BuildContext context) {
    return GlassPanel(
      tint: AppTheme.brandOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Formato da Telemetria',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceSoft.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.brandOrange.withValues(alpha: 0.4),
              ),
            ),
            child: SelectableText(
              '{"voltage":220.4,"current":3.9,"power":858,"pf":0.98,"frequency":60,"energy":1.234,"vibration":0.12,"temperature":37.8}\n'
              'ou\n'
              '{"voltage":220.4}\n'
              '{"current":3.9}\n'
              '{"power":858,"pf":0.98,"frequency":60,"energy":1.234}\n'
              '{"vibration":0.12}\n'
              '{"temperature":37.8}\n'
              'ou\n'
              '{"data":{"voltage":"220.4","current":"3.9","power":"858","pf":"0.98","frequency":"60","energy":"1.234","vibration":"0.12","temperature":"37.8"}}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: AppTheme.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required double width,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? errorText,
    String? suffixText,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onChanged: (_) => this.controller.refreshPreview(),
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          suffixText: suffixText,
        ),
      ),
    );
  }

  double _fieldWidthFor(double availableWidth) {
    if (availableWidth >= 840) {
      return (availableWidth - 20) / 2;
    }
    if (availableWidth >= 560) {
      return (availableWidth - 20) / 2;
    }
    return availableWidth;
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
        return 'Atencao';
      case TelemetryAlertSeverity.critical:
        return 'Critico';
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
