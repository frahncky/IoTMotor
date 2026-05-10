import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/glass_panel.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/telemetry_alert.dart';
import '../../services/mqtt_settings_validators.dart';

enum _RetentionUnit { days, months, years }

class ConfiguracoesTab extends StatefulWidget {
  final MotorControlController controller;
  const ConfiguracoesTab({Key? key, required this.controller}) : super(key: key);

  @override
  State<ConfiguracoesTab> createState() => _ConfiguracoesTabState();
}

class _ConfiguracoesTabState extends State<ConfiguracoesTab> {
  final _retentionController = TextEditingController();
  final _remoteRetentionController = TextEditingController();
  final _retentionFocusNode = FocusNode();
  final _remoteRetentionFocusNode = FocusNode();
  final _espIpController = TextEditingController();

  _RetentionUnit _retentionUnit = _RetentionUnit.days;
  _RetentionUnit _remoteRetentionUnit = _RetentionUnit.days;

  @override
  void dispose() {
    _retentionController.dispose();
    _remoteRetentionController.dispose();
    _retentionFocusNode.dispose();
    _remoteRetentionFocusNode.dispose();
    _espIpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStoragePanel(context),
          const SizedBox(height: 24),
          _buildAlertPanel(context),
          // ...outros painéis...
        ],
      ),
    );
  }

  // ...restante do código...

  // Corrigir todos os acessos a 'controller' para 'widget.controller' nos métodos privados e widgets
  // Exemplo para métodos e widgets que usam 'controller':

  // Exemplo de uso:
  // widget.controller.historyRetentionSummary
  // widget.controller.setHistoryRetentionDays(...)
  // ...

  // Substitua todos os 'controller.' por 'widget.controller.' nos métodos privados e widgets abaixo

  Widget _buildStoragePanel(BuildContext context) {
    final controller = widget.controller;
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
                      'Armazenamento',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Local do app',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
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
                      decoration: InputDecoration(
                        labelText: 'Retenção local',
                        suffixText: _retentionUnitLabel(_retentionUnit),
                        hintText: 'Ex: 30',
                      ),
                      onFieldSubmitted: (_) => _applyRetentionDays(),
                    ),
                  ),
                  _buildRetentionUnitSelector(
                    selected: _retentionUnit,
                    onChanged: _setRetentionUnit,
                  ),
                  Chip(
                    avatar: const Icon(Icons.timeline_rounded, size: 16),
                    label: Text(controller.historyRetentionSummary),
                  ),
                  OutlinedButton.icon(
                    onPressed: _applyRetentionDays,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Aplicar local'),
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
              const SizedBox(height: 16),
              Text(
                'Remoto no ESP32',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      controller: _remoteRetentionController,
                      focusNode: _remoteRetentionFocusNode,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Retenção remota (ESP32 SD)',
                        suffixText: _retentionUnitLabel(_remoteRetentionUnit),
                        hintText: 'Ex: 30',
                      ),
                      onFieldSubmitted: (_) => _applyRemoteRetentionDays(),
                    ),
                  ),
                  _buildRetentionUnitSelector(
                    selected: _remoteRetentionUnit,
                    onChanged: _setRemoteRetentionUnit,
                  ),
                  Chip(
                    avatar: const Icon(Icons.sd_storage_rounded, size: 16),
                    label: Text(controller.remoteHistoryRetentionSummary),
                  ),
                  FilledButton.icon(
                    onPressed: _applyAndSendRemoteRetention,
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: const Text('Aplicar no ESP32'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRetentionUnitSelector({
    required _RetentionUnit selected,
    required ValueChanged<_RetentionUnit> onChanged,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_RetentionUnit>(
        showSelectedIcon: false,
        selected: <_RetentionUnit>{selected},
        onSelectionChanged: (Set<_RetentionUnit> selection) {
          onChanged(selection.first);
        },
        segments: const <ButtonSegment<_RetentionUnit>>[
          ButtonSegment<_RetentionUnit>(
            value: _RetentionUnit.days,
            label: Text('Dias'),
          ),
          ButtonSegment<_RetentionUnit>(
            value: _RetentionUnit.months,
            label: Text('Meses'),
          ),
          ButtonSegment<_RetentionUnit>(
            value: _RetentionUnit.years,
            label: Text('Anos'),
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
    );
  }


  bool _applyRetentionDays() {
    final int? days = int.tryParse(_retentionController.text.trim());
    if (days == null || days <= 0) {
      _showSnackBar('Informe uma retenção local maior que zero.');
      return false;
    }
    _setRetentionAmount(days);
    return true;
  }

  bool _applyRemoteRetentionDays() {
    final int? days = int.tryParse(_remoteRetentionController.text.trim());
    if (days == null || days <= 0) {
      _showSnackBar('Informe uma retenção remota maior que zero.');
      return false;
    }
    _setRemoteRetentionAmount(days);
    return true;
  }

  Future<void> _applyAndSendRemoteRetention() async {
    if (!_applyRemoteRetentionDays()) {
      return;
    }
    await widget.controller.applyRemoteHistoryRetention();
  }

  void _setRetentionAmount(int amount) {
    widget.controller.setHistoryRetentionDays(
      _retentionDaysFromAmount(amount, _retentionUnit),
    );
    _retentionController.text =
        _displayAmountForDays(
          widget.controller.historyRetentionDays,
          _retentionUnit,
        ).toString();
  }

  void _setRemoteRetentionAmount(int amount) {
    widget.controller.setRemoteHistoryRetentionDays(
      _retentionDaysFromAmount(amount, _remoteRetentionUnit),
    );
    _remoteRetentionController.text =
        _displayAmountForDays(
          widget.controller.remoteHistoryRetentionDays,
          _remoteRetentionUnit,
        ).toString();
  }

  void _setRetentionUnit(_RetentionUnit unit) {
    if (_retentionUnit == unit) {
      return;
    }
    setState(() {
      _retentionUnit = unit;
      _retentionController.text =
          _displayAmountForDays(
            widget.controller.historyRetentionDays,
            unit,
          ).toString();
    });
  }

  void _setRemoteRetentionUnit(_RetentionUnit unit) {
    if (_remoteRetentionUnit == unit) {
      return;
    }
    setState(() {
      _remoteRetentionUnit = unit;
      _remoteRetentionController.text =
          _displayAmountForDays(
            widget.controller.remoteHistoryRetentionDays,
            unit,
          ).toString();
    });
  }

  int _retentionDaysFromAmount(int amount, _RetentionUnit unit) {
    switch (unit) {
      case _RetentionUnit.days:
        return amount;
      case _RetentionUnit.months:
        return amount * 30;
      case _RetentionUnit.years:
        return amount * 365;
    }
  }

  int _displayAmountForDays(int days, _RetentionUnit unit) {
    switch (unit) {
      case _RetentionUnit.days:
        return days;
      case _RetentionUnit.months:
        return (days / 30).ceil().clamp(1, 3650);
      case _RetentionUnit.years:
        return (days / 365).ceil().clamp(1, 3650);
    }
  }

  String _retentionUnitLabel(_RetentionUnit unit) {
    switch (unit) {
      case _RetentionUnit.days:
        return 'dias';
      case _RetentionUnit.months:
        return 'meses';
      case _RetentionUnit.years:
        return 'anos';
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
    final TelemetryAlert? latestAlert = widget.controller.latestAlert;
    final String? thresholdError = widget.controller.alertThresholdsError;
    final List<TelemetryAlert> recentAlerts = widget.controller.alerts
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
                    value: widget.controller.telemetryAlertsEnabled,
                    onChanged: widget.controller.setTelemetryAlertsEnabled,
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
                    controller: widget.controller.voltageMinController,
                    keyboardType: TextInputType.number,
                    suffixText: 'V',
                    errorText: MqttSettingsValidators.validateDecimal(
                      widget.controller.voltageMinController.text,
                      fieldLabel: 'a tensão mínima',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Tensão máxima',
                    controller: widget.controller.voltageMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'V',
                    errorText: MqttSettingsValidators.validateDecimal(
                      widget.controller.voltageMaxController.text,
                      fieldLabel: 'a tensão máxima',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Corrente máxima',
                    controller: widget.controller.currentMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'A',
                    errorText: MqttSettingsValidators.validateDecimal(
                      widget.controller.currentMaxController.text,
                      fieldLabel: 'o limite de corrente',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Vibração máxima',
                    controller: widget.controller.vibrationMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'g',
                    errorText: MqttSettingsValidators.validateDecimal(
                      widget.controller.vibrationMaxController.text,
                      fieldLabel: 'o limite de vibração',
                      min: 0,
                      allowZero: false,
                    ),
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Temperatura máxima',
                    controller: widget.controller.temperatureMaxController,
                    keyboardType: TextInputType.number,
                    suffixText: 'C',
                    errorText: MqttSettingsValidators.validateDecimal(
                      widget.controller.temperatureMaxController.text,
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
                    label: Text(widget.controller.alertStatusSummary),
                  ),
                  if (latestAlert != null)
                    Chip(
                      avatar: Icon(_alertIcon(latestAlert.severity), size: 16),
                      label: Text('Último: ${latestAlert.title}'),
                    ),
                  OutlinedButton.icon(
                    onPressed:
                        widget.controller.alerts.isEmpty
                          ? null
                          : widget.controller.clearAlerts,
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
              onPressed: () => widget.controller.acknowledgeAlert(alert.id),
              icon: const Icon(Icons.done_rounded),
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
        onChanged: (_) => widget.controller.refreshPreview(),
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
