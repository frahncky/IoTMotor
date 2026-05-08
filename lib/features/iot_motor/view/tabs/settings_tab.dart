import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/providers/esp_local_comm_provider.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/telemetry_alert.dart';
import '../../services/mqtt_settings_validators.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';

class ConfiguracoesTab extends ConsumerStatefulWidget {
  const ConfiguracoesTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  ConsumerState<ConfiguracoesTab> createState() => _ConfiguracoesTabState();
}

class _ConfiguracoesTabState extends ConsumerState<ConfiguracoesTab> {
  late final TextEditingController _espIpController;
  late final TextEditingController _retentionController;
  late final FocusNode _retentionFocusNode;
  bool _isTestingLocalComm = false;

  MotorControlController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _espIpController = TextEditingController();
    _retentionController = TextEditingController(
      text: controller.historyRetentionDays.toString(),
    );
    _retentionFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant ConfiguracoesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRetentionController();
  }

  @override
  void dispose() {
    _espIpController.dispose();
    _retentionController.dispose();
    _retentionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncRetentionController();

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
                child: _buildConnectionPanel(context, ref),
              ),
              const SizedBox(height: 12),
              DelayedReveal(
                delay: const Duration(milliseconds: 250),
                child: _buildStoragePanel(context),
              ),
              const SizedBox(height: 12),
              DelayedReveal(
                delay: const Duration(milliseconds: 300),
                child: _buildAlertPanel(context),
              ),
              const SizedBox(height: 12),
              DelayedReveal(
                delay: const Duration(milliseconds: 350),
                child: _buildTelemetryFormatPanel(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionPanel(BuildContext context, WidgetRef ref) {
    return GlassPanel(
      tint: AppTheme.brandBlue,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double fieldWidth = _fieldWidthFor(constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Conexão MQTT',
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
                    label: 'Usuário (opcional)',
                    controller: controller.usernameController,
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Senha (opcional)',
                    controller: controller.passwordController,
                    obscureText: true,
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      controller: _espIpController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'IP do ESP32 (local)',
                        hintText: 'Ex: 192.168.1.100',
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed:
                        _isTestingLocalComm
                            ? null
                            : () => _testLocalCommunication(ref),
                    icon:
                        _isTestingLocalComm
                            ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.wifi_tethering),
                    label: Text(
                      _isTestingLocalComm
                          ? 'Testando...'
                          : 'Testar comunicação local',
                    ),
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
                  'Tópico de comando: ${controller.commandTopic}\n'
                  'Tópico de telemetria: ${controller.telemetryTopic}\n'
                  'Tópico de status: ${controller.statusTopic}\n'
                  'Tópico de solicitação: ${controller.telemetryRequestTopic}\n'
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

  Widget _buildStoragePanel(BuildContext context) {
    return GlassPanel(
      tint: AppTheme.brandMint,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double fieldWidth = _fieldWidthFor(constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.storage_rounded, color: AppTheme.brandMint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Armazenamento local',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      controller: _retentionController,
                      focusNode: _retentionFocusNode,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Retenção do histórico',
                        suffixText: 'dias',
                        hintText: 'Ex: 30',
                      ),
                      onFieldSubmitted: (_) => _applyRetentionDays(),
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.timeline_rounded, size: 16),
                    label: Text(controller.historyRetentionSummary),
                  ),
                  for (final int days
                      in MotorControlController.historyRetentionOptions)
                    ChoiceChip(
                      label: Text('$days dias'),
                      selected: controller.historyRetentionDays == days,
                      onSelected: (_) => _setRetentionDays(days),
                    ),
                  OutlinedButton.icon(
                    onPressed:
                        controller.historyEntryCount == 0
                            ? null
                            : controller.clearHistory,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Limpar histórico'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _testLocalCommunication(WidgetRef ref) async {
    final String ip = _espIpController.text.trim();
    if (ip.isEmpty) {
      _showSnackBar('Informe o IP do ESP32.');
      return;
    }

    setState(() {
      _isTestingLocalComm = true;
    });

    try {
      final response = await ref
          .read(espLocalCommProvider)
          .getWifiNetworks(espHost: ip);
      if (!mounted) {
        return;
      }

      if (response.statusCode == 200) {
        _showSnackBar('Comunicação local com ESP32 OK.');
      } else {
        _showSnackBar('Falha ao comunicar: HTTP ${response.statusCode}.');
      }
    } catch (error) {
      if (mounted) {
        _showSnackBar('Erro na comunicação local: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingLocalComm = false;
        });
      }
    }
  }

  void _applyRetentionDays() {
    final int? days = int.tryParse(_retentionController.text.trim());
    if (days == null || days <= 0) {
      _showSnackBar('Informe uma retenção maior que zero.');
      return;
    }
    _setRetentionDays(days);
  }

  void _setRetentionDays(int days) {
    controller.setHistoryRetentionDays(days);
    _retentionController.text = controller.historyRetentionDays.toString();
  }

  void _syncRetentionController() {
    if (_retentionFocusNode.hasFocus) {
      return;
    }
    final String value = controller.historyRetentionDays.toString();
    if (_retentionController.text != value) {
      _retentionController.text = value;
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
                    label: 'Tensão mínima',
                    controller: controller.voltageMinController,
                    keyboardType: TextInputType.number,
                    suffixText: 'V',
                    errorText: MqttSettingsValidators.validateDecimal(
                      controller.voltageMinController.text,
                      fieldLabel: 'a tensão mínima',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Tensão máxima',
                    controller: controller.voltageMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'V',
                    errorText: MqttSettingsValidators.validateDecimal(
                      controller.voltageMaxController.text,
                      fieldLabel: 'a tensão máxima',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Corrente máxima',
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
                    label: 'Vibração máxima',
                    controller: controller.vibrationMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'g',
                    errorText: MqttSettingsValidators.validateDecimal(
                      controller.vibrationMaxController.text,
                      fieldLabel: 'o limite de vibração',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Temperatura máxima',
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
