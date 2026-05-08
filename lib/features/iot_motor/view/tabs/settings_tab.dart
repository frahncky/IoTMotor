import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/providers/esp_local_comm_provider.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/telemetry_alert.dart';
import '../../services/mqtt_settings_validators.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';

enum _SettingsSection { conexao, armazenamento, alertas }

enum _RetentionUnit { days, months, years }

class ConfiguracoesTab extends ConsumerStatefulWidget {
  const ConfiguracoesTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  ConsumerState<ConfiguracoesTab> createState() => _ConfiguracoesTabState();
}

class _ConfiguracoesTabState extends ConsumerState<ConfiguracoesTab> {
  late final TextEditingController _espIpController;
  late final TextEditingController _retentionController;
  late final TextEditingController _remoteRetentionController;
  late final FocusNode _retentionFocusNode;
  late final FocusNode _remoteRetentionFocusNode;
  _SettingsSection _selectedSection = _SettingsSection.conexao;
  _RetentionUnit _retentionUnit = _RetentionUnit.days;
  _RetentionUnit _remoteRetentionUnit = _RetentionUnit.days;
  bool _isTestingLocalComm = false;

  MotorControlController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _espIpController = TextEditingController();
    _retentionController = TextEditingController(
      text: controller.historyRetentionDays.toString(),
    );
    _remoteRetentionController = TextEditingController(
      text: controller.remoteHistoryRetentionDays.toString(),
    );
    _retentionFocusNode = FocusNode();
    _remoteRetentionFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant ConfiguracoesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRetentionControllers();
  }

  @override
  void dispose() {
    _espIpController.dispose();
    _retentionController.dispose();
    _remoteRetentionController.dispose();
    _retentionFocusNode.dispose();
    _remoteRetentionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncRetentionControllers();

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
                child: _buildSectionSelector(),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: ValueKey<_SettingsSection>(_selectedSection),
                child: _buildSelectedSettingsPanel(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionSelector() {
    return Align(
      alignment: Alignment.center,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<_SettingsSection>(
          showSelectedIcon: false,
          selected: <_SettingsSection>{_selectedSection},
          onSelectionChanged: (Set<_SettingsSection> selection) {
            final _SettingsSection nextSection = selection.first;
            if (nextSection == _selectedSection) {
              return;
            }
            setState(() {
              _selectedSection = nextSection;
            });
          },
          segments: const <ButtonSegment<_SettingsSection>>[
            ButtonSegment<_SettingsSection>(
              value: _SettingsSection.conexao,
              icon: Icon(Icons.cloud_done_rounded, size: 16),
              label: Text('MQTT'),
            ),
            ButtonSegment<_SettingsSection>(
              value: _SettingsSection.armazenamento,
              icon: Icon(Icons.storage_rounded, size: 16),
              label: Text('Armazenamento'),
            ),
            ButtonSegment<_SettingsSection>(
              value: _SettingsSection.alertas,
              icon: Icon(Icons.notifications_active_rounded, size: 16),
              label: Text('Alertas'),
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

  Widget _buildSelectedSettingsPanel(BuildContext context, WidgetRef ref) {
    switch (_selectedSection) {
      case _SettingsSection.conexao:
        return _buildConnectionPanel(context, ref);
      case _SettingsSection.armazenamento:
        return _buildStoragePanel(context);
      case _SettingsSection.alertas:
        return _buildAlertPanel(context);
    }
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
    await controller.applyRemoteHistoryRetention();
  }

  void _setRetentionAmount(int amount) {
    controller.setHistoryRetentionDays(
      _retentionDaysFromAmount(amount, _retentionUnit),
    );
    _retentionController.text =
        _displayAmountForDays(
          controller.historyRetentionDays,
          _retentionUnit,
        ).toString();
  }

  void _setRemoteRetentionAmount(int amount) {
    controller.setRemoteHistoryRetentionDays(
      _retentionDaysFromAmount(amount, _remoteRetentionUnit),
    );
    _remoteRetentionController.text =
        _displayAmountForDays(
          controller.remoteHistoryRetentionDays,
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
            controller.historyRetentionDays,
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
            controller.remoteHistoryRetentionDays,
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

  void _syncRetentionControllers() {
    if (!_retentionFocusNode.hasFocus) {
      final String value =
          _displayAmountForDays(
            controller.historyRetentionDays,
            _retentionUnit,
          ).toString();
      if (_retentionController.text != value) {
        _retentionController.text = value;
      }
    }

    if (!_remoteRetentionFocusNode.hasFocus) {
      final String value =
          _displayAmountForDays(
            controller.remoteHistoryRetentionDays,
            _remoteRetentionUnit,
          ).toString();
      if (_remoteRetentionController.text != value) {
        _remoteRetentionController.text = value;
      }
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
