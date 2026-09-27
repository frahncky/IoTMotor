import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/esp_local_comm_provider.dart';
import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/device_names.dart';
import '../../models/acquisition_config.dart';
import '../../services/mqtt_path_check.dart';
import '../widgets/alertas_no_celular_panel.dart';
import '../widgets/connection_path_dialog.dart';
import '../../services/mqtt_settings_validators.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';
import 'settings/alert_settings_panel.dart';
import 'settings/device_maintenance_section.dart';
import 'settings/motor_settings_panel.dart';
import 'settings/profiles_settings_panel.dart';
import 'settings/settings_common.dart';

enum _RetentionUnit { days, months, years }

class ConfiguracoesTab extends ConsumerStatefulWidget {
  const ConfiguracoesTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  ConsumerState<ConfiguracoesTab> createState() => _ConfiguracoesTabState();
}

class _ConfiguracoesTabState extends ConsumerState<ConfiguracoesTab> {
  final _connectionFormKey = GlobalKey<FormState>();
  final _storageFormKey = GlobalKey<FormState>();

  final _retentionController = TextEditingController();
  final _remoteRetentionController = TextEditingController();
  final _retentionFocusNode = FocusNode();
  final _remoteRetentionFocusNode = FocusNode();
  final _espIpController = TextEditingController();
  final _acqPzemController = TextEditingController();
  final _acqPublishController = TextEditingController();
  final _acqChartController = TextEditingController();
  final _acqRecordController = TextEditingController();
  String _acqPreset = 'custom';
  int _lastAcqRevision = -1;
  _RetentionUnit _retentionUnit = _RetentionUnit.days;
  _RetentionUnit _remoteRetentionUnit = _RetentionUnit.days;
  int _selectedSettingsTab = 0;
  bool _isTestingLocalComm = false;

  MotorControlController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _syncRetentionControllers(force: true);
    _syncAcquisitionControllers(force: true);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ConfiguracoesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _syncRetentionControllers(force: true);
      _syncAcquisitionControllers(force: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _retentionController.dispose();
    _remoteRetentionController.dispose();
    _retentionFocusNode.dispose();
    _remoteRetentionFocusNode.dispose();
    _espIpController.dispose();
    _acqPzemController.dispose();
    _acqPublishController.dispose();
    _acqChartController.dispose();
    _acqRecordController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      _syncRetentionControllers();
      _syncAcquisitionControllers();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DelayedReveal(
                  delay: const Duration(milliseconds: 120),
                  child: _buildTabHeader(context),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: IndexedStack(
                    index: _selectedSettingsTab,
                    children: <Widget>[
                      _buildTabScrollView(
                        key: 'settings_connection',
                        delay: const Duration(milliseconds: 180),
                        child: _buildConnectionPanel(context),
                      ),
                      _buildTabScrollView(
                        key: 'settings_motor',
                        delay: const Duration(milliseconds: 180),
                        child: MotorSettingsPanel(controller: controller),
                      ),
                      _buildTabScrollView(
                        key: 'settings_profiles',
                        delay: const Duration(milliseconds: 180),
                        child: ProfilesSettingsPanel(
                          controller: controller,
                          validateConnection: () =>
                              _connectionFormKey.currentState?.validate() ?? false,
                        ),
                      ),
                      _buildTabScrollView(
                        key: 'settings_storage',
                        delay: const Duration(milliseconds: 180),
                        child: _buildStoragePanel(context),
                      ),
                      _buildTabScrollView(
                        key: 'settings_alerts',
                        delay: const Duration(milliseconds: 180),
                        child: Column(
                          children: <Widget>[
                            AlertasNoCelularPanel(controller: controller),
                            const SizedBox(height: 12),
                            AlertSettingsPanel(controller: controller),
                          ],
                        ),
                      ),
                      _buildTabScrollView(
                        key: 'settings_telemetry',
                        delay: const Duration(milliseconds: 180),
                        child: _buildTelemetryFormatPanel(context),
                      ),
                      _buildTabScrollView(
                        key: 'settings_acquisition',
                        delay: const Duration(milliseconds: 180),
                        child: _buildAcquisitionPanel(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabHeader(BuildContext context) {
    return GlassPanel(
      tint: AppTheme.brandBlue,
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: TabBar(
        isScrollable: true,
        onTap: (int index) {
          setState(() {
            _selectedSettingsTab = index;
          });
        },
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppTheme.brandMint.withValues(alpha: 0.22),
          border: Border.all(color: AppTheme.brandMint.withValues(alpha: 0.35)),
        ),
        labelColor: AppTheme.brandMint,
        unselectedLabelColor: AppTheme.inkSoft,
        labelStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        unselectedLabelStyle: Theme.of(context).textTheme.labelLarge,
        tabs: const <Widget>[
          Tab(
            height: 48,
            iconMargin: EdgeInsets.only(bottom: 2),
            icon: Icon(Icons.settings_input_component_rounded),
            text: 'Conexão',
          ),
          Tab(
            height: 48,
            iconMargin: EdgeInsets.only(bottom: 2),
            icon: Icon(Icons.electric_bolt_rounded),
            text: 'Motor',
          ),
          Tab(
            height: 48,
            iconMargin: EdgeInsets.only(bottom: 2),
            icon: Icon(Icons.account_tree_rounded),
            text: 'Perfis',
          ),
          Tab(
            height: 48,
            iconMargin: EdgeInsets.only(bottom: 2),
            icon: Icon(Icons.storage_rounded),
            text: 'Armazenamento',
          ),
          Tab(
            height: 48,
            iconMargin: EdgeInsets.only(bottom: 2),
            icon: Icon(Icons.notification_important_rounded),
            text: 'Alertas',
          ),
          Tab(
            height: 48,
            iconMargin: EdgeInsets.only(bottom: 2),
            icon: Icon(Icons.data_object_rounded),
            text: 'Telemetria',
          ),
          Tab(
            height: 48,
            iconMargin: EdgeInsets.only(bottom: 2),
            icon: Icon(Icons.speed_rounded),
            text: 'Aquisição',
          ),
        ],
      ),
    );
  }

  Widget _buildTabScrollView({
    required String key,
    required Duration delay,
    required Widget child,
  }) {
    return SingleChildScrollView(
      key: ValueKey<String>(key),
      padding: const EdgeInsets.only(bottom: 96),
      child: DelayedReveal(delay: delay, child: child),
    );
  }

  Widget _buildConnectionPanel(BuildContext context) {
    return Form(
      key: _connectionFormKey,
      child: GlassPanel(
        tint: AppTheme.brandBlue,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double fieldWidth = fieldWidthFor(constraints.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                buildPanelTitle(
                  context,
                  icon: Icons.settings_input_component_rounded,
                  color: AppTheme.brandBlue,
                  title: 'Conexão MQTT',
                  subtitle: 'Broker, tópicos e comunicação local do ESP32.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _textField(
                      width: fieldWidth,
                      label: 'Broker host',
                      controllerField: controller.brokerController,
                      validator: MqttSettingsValidators.validateBroker,
                      helperText:
                          'Rede que bloqueia MQTT: ws://test.mosquitto.org '
                          'na porta 8080',
                    ),
                    _textField(
                      width: fieldWidth,
                      label: 'Porta',
                      controllerField: controller.portController,
                      keyboardType: TextInputType.number,
                      validator: MqttSettingsValidators.validatePort,
                    ),
                    _textField(
                      width: fieldWidth,
                      label: 'Client ID',
                      controllerField: controller.clientIdController,
                      validator: MqttSettingsValidators.validateClientId,
                    ),
                    _textField(
                      width: fieldWidth,
                      label: 'Topic prefix',
                      controllerField: controller.topicPrefixController,
                      validator: MqttSettingsValidators.validateTopicPrefix,
                    ),
                    _textField(
                      width: fieldWidth,
                      label: 'Usuário (opcional)',
                      controllerField: controller.usernameController,
                    ),
                    _textField(
                      width: fieldWidth,
                      label: 'Senha (opcional)',
                      controllerField: controller.passwordController,
                      obscureText: true,
                    ),
                    // Só aparece se a placa foi gravada exigindo comando
                    // cifrado; por padrão os comandos viajam abertos.
                    if (controller.commandPasswordNeeded)
                      _textField(
                        width: fieldWidth,
                        label: 'Senha de comando',
                        controllerField: controller.commandPasswordController,
                        obscureText: true,
                      ),
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<String>(
                        // initialValue só vale na criação: a chave recria o
                        // campo quando a placa escolhida muda por fora.
                        key: ValueKey<String>(controller.deviceIdController.text),
                        initialValue:
                            controller.deviceIdController.text.isEmpty
                                ? null
                                : controller.deviceIdController.text,
                        decoration: const InputDecoration(
                          labelText: 'Motor em Operação',
                          hintText: 'Selecione o ID do dispositivo',
                        ),
                        items: () {
                          final Set<String> allIds = {
                            ...controller.knownDeviceIds,
                            ...controller.connectedDeviceIds,
                            if (controller.deviceIdController.text.isNotEmpty)
                              controller.deviceIdController.text,
                          };

                          final List<String> sortedIds =
                              allIds.toList()..sort();

                          return sortedIds.map<DropdownMenuItem<String>>((id) {
                            final isOnline = controller.connectedDeviceIds
                                .contains(id);
                            final isKnown = controller.knownDeviceIds.contains(
                              id,
                            );

                            return DropdownMenuItem<String>(
                              value: id,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 10,
                                    color:
                                        isOnline
                                            ? AppTheme.brandMint
                                            : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isKnown
                                        ? nomeComId(id)
                                        : '${nomeDaPlaca(id)} (manual)',
                                  ),
                                ],
                              ),
                            );
                          }).toList();
                        }(),
                        onChanged: (val) {
                          controller.setDeviceId(val ?? '');
                          controller.refreshPreview();
                        },
                      ),
                    ),
                    _textField(
                      width: fieldWidth,
                      label: 'IP do ESP32 (local)',
                      controllerField: _espIpController,
                      keyboardType: TextInputType.url,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.wifi_tethering_rounded),
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
                          controller.isBusy ? null : _handleConnectionToggle,
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
                    OutlinedButton.icon(
                      onPressed: _testarCaminhos,
                      icon: const Icon(Icons.travel_explore_rounded),
                      label: const Text('Testar caminhos de conexão'),
                    ),
                    Chip(
                      avatar: Icon(
                        controller.isConnected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 16,
                      ),
                      label: Text(controller.connectionMessage),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.brandBlue.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.brandBlue.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Dispositivos: ${controller.devicesPresenceSummary}',
                        key: const ValueKey<String>('connection_devices_summary'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Clientes: ${controller.commandClientsSummary}',
                        key: const ValueKey<String>('connection_clients_summary'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                buildInlineNotice(
                  context,
                  icon: Icons.info_outline_rounded,
                  color: AppTheme.brandBlue,
                  text: controller.statusMessage,
                ),
                const SizedBox(height: 12),
                DeviceMaintenanceSection(controller: controller),
                const SizedBox(height: 12),
                _buildTopicPreview(context),
              ],
            );
          },
        ),
      ),
    );
  }


  void _syncAcquisitionControllers({bool force = false}) {
    final AcquisitionConfig cfg = controller.acquisitionConfig;
    if (!force && cfg.revision == _lastAcqRevision) return;
    _lastAcqRevision = cfg.revision;
    _acqPzemController.text = (cfg.pzemReadMs / 1000).toStringAsFixed(0);
    _acqPublishController.text = (cfg.publishMs / 1000).toStringAsFixed(0);
    _acqChartController.text = (cfg.chartMs / 1000).toStringAsFixed(0);
    _acqRecordController.text = (cfg.recordMs / 1000).toStringAsFixed(0);
    _acqPreset = 'custom';
    for (final MapEntry<String, AcquisitionConfig> entry in AcquisitionConfig.presets.entries) {
      final AcquisitionConfig p = entry.value;
      if (p.pzemReadMs == cfg.pzemReadMs &&
          p.publishMs == cfg.publishMs &&
          p.chartMs == cfg.chartMs &&
          p.recordMs == cfg.recordMs) {
        _acqPreset = entry.key;
        break;
      }
    }
  }

  AcquisitionConfig? _acquisitionFromFields() {
    int? ms(TextEditingController campo) {
      final int? s = int.tryParse(campo.text.trim());
      return s == null ? null : s * 1000;
    }
    final int? pzem = ms(_acqPzemController);
    final int? pub = ms(_acqPublishController);
    final int? chart = ms(_acqChartController);
    final int? record = ms(_acqRecordController);
    if (pzem == null || pub == null || chart == null || record == null) return null;
    return AcquisitionConfig(
      revision: controller.acquisitionConfig.revision,
      pzemReadMs: pzem,
      publishMs: pub,
      chartMs: chart,
      recordMs: record,
    );
  }

  Widget _buildAcquisitionPanel(BuildContext context) {
    final AcquisitionConfig cfg = controller.acquisitionConfig;
    return GlassPanel(
      tint: AppTheme.brandMint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          buildPanelTitle(
            context,
            icon: Icons.speed_rounded,
            color: AppTheme.brandMint,
            title: 'Aquisição e registro de dados',
            subtitle: 'Configuração única do sistema. Alterações feitas aqui também valem no painel web e nas placas.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _acqPreset,
            decoration: const InputDecoration(labelText: 'Perfil'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'custom', child: Text('Personalizado')),
              DropdownMenuItem(value: 'realtime', child: Text('Tempo real')),
              DropdownMenuItem(value: 'monitoring', child: Text('Monitoramento')),
              DropdownMenuItem(value: 'economic', child: Text('Econômico')),
            ],
            onChanged: (String? value) {
              if (value == null) return;
              setState(() {
                _acqPreset = value;
                final AcquisitionConfig? p = AcquisitionConfig.presets[value];
                if (p != null) {
                  _acqPzemController.text = '${p.pzemReadMs ~/ 1000}';
                  _acqPublishController.text = '${p.publishMs ~/ 1000}';
                  _acqChartController.text = '${p.chartMs ~/ 1000}';
                  _acqRecordController.text = '${p.recordMs ~/ 1000}';
                }
              });
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _textField(width: 210, label: 'Aquisição elétrica (s)', controllerField: _acqPzemController, keyboardType: TextInputType.number),
              _textField(width: 210, label: 'Publicação MQTT (s)', controllerField: _acqPublishController, keyboardType: TextInputType.number),
              _textField(width: 210, label: 'Pontos do gráfico (s)', controllerField: _acqChartController, keyboardType: TextInputType.number),
              _textField(width: 210, label: 'Registro de dados (s)', controllerField: _acqRecordController, keyboardType: TextInputType.number),
            ],
          ),
          const SizedBox(height: 14),
          buildInlineNotice(
            context,
            icon: Icons.lock_clock_rounded,
            color: AppTheme.brandBlue,
            text: 'Parâmetros protegidos: vibração ${cfg.vibrationHz} Hz, janela RMS ${cfg.vibrationWindowMs ~/ 1000} s, histórico consolidado a cada ${cfg.historyBucketS ~/ 60} min por ${cfg.historyRetentionDays} dias.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilledButton.icon(
                onPressed: controller.isConnected
                    ? () async {
                        final AcquisitionConfig? nova = _acquisitionFromFields();
                        if (nova == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Informe os quatro intervalos em segundos.')),
                          );
                          return;
                        }
                        final String? erro = nova.validate();
                        if (erro != null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
                          return;
                        }
                        await controller.saveAcquisitionConfig(nova);
                      }
                    : null,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Gravar e sincronizar'),
              ),
              OutlinedButton.icon(
                onPressed: controller.isConnected ? controller.requestAcquisitionConfig : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Ler da placa'),
              ),
              Chip(
                label: Text(cfg.revision > 0
                    ? 'Sincronizado · revisão ${cfg.revision}'
                    : 'Aguardando ESP32-01'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStoragePanel(BuildContext context) {
    return Form(
      key: _storageFormKey,
      child: GlassPanel(
        tint: AppTheme.brandMint,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double fieldWidth = fieldWidthFor(constraints.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                buildPanelTitle(
                  context,
                  icon: Icons.storage_rounded,
                  color: AppTheme.brandMint,
                  title: 'Armazenamento',
                  subtitle: 'Retenção local do app e política remota do SD.',
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
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator:
                            (String? value) =>
                                MqttSettingsValidators.validateDecimal(
                                  value,
                                  fieldLabel: 'a retenção local',
                                  min: 0,
                                  allowZero: false,
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
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator:
                            (String? value) =>
                                MqttSettingsValidators.validateDecimal(
                                  value,
                                  fieldLabel: 'a retenção remota',
                                  min: 0,
                                  allowZero: false,
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
      ),
    );
  }

  Widget _buildTelemetryFormatPanel(BuildContext context) {
    return GlassPanel(
      tint: AppTheme.brandOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          buildPanelTitle(
            context,
            icon: Icons.data_object_rounded,
            color: AppTheme.brandOrange,
            title: 'Formato da Telemetria',
            subtitle: 'Payloads aceitos no tópico de telemetria.',
          ),
          const SizedBox(height: 12),
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
              '{"voltage":220.4,"current":3.9,"power":858,"pf":0.98,"frequency":60,"energy":1.234,"vibration_mms":2.1,"temperature":37.8}\n'
              'ou\n'
              '{"voltage":220.4}\n'
              '{"current":3.9}\n'
              '{"power":858,"pf":0.98,"frequency":60,"energy":1.234}\n'
              '{"vibration_mms":2.1}\n'
              '{"temperature":37.8}\n'
              'ou\n'
              '{"data":{"voltage":"220.4","current":"3.9","power":"858","pf":"0.98","frequency":"60","energy":"1.234","vibration_mms":"2.1","temperature":"37.8"}}',
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

  Widget _buildTopicPreview(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppTheme.surfaceSoft.withValues(alpha: 0.94),
        border: Border.all(color: AppTheme.brandBlue.withValues(alpha: 0.36)),
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

  Widget _textField({
    required double width,
    required String label,
    required TextEditingController controllerField,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
    String? suffixText,
    String? helperText,
  }) {
    return settingsTextField(
      width: width,
      label: label,
      controllerField: controllerField,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      suffixText: suffixText,
      helperText: helperText,
      onChanged: () {
        setState(() {});
        controller.refreshPreview();
      },
    );
  }

  /// Abre o teste dos caminhos e aplica o que a pessoa escolher.
  Future<void> _testarCaminhos() async {
    final MqttPathCandidate? escolhido = await ConnectionPathDialog.mostrar(
      context,
      controller.brokerController.text,
    );
    if (escolhido == null || !mounted) return;
    controller.brokerController.text = escolhido.host;
    controller.portController.text = '${escolhido.port}';
    controller.setTls(escolhido.useTls);
    setState(() {});
    _showSnackBar('Configurado: ${escolhido.host}:${escolhido.port}');
  }

  Future<void> _handleConnectionToggle() async {
    if (controller.isConnected) {
      await controller.disconnect();
      return;
    }

    if (!(_connectionFormKey.currentState?.validate() ?? false)) {
      _showSnackBar('Revise os dados da conexão MQTT.');
      return;
    }

    await controller.connect();
    if (!mounted || controller.isConnected) return;

    // Sem isto, o motivo da falha ficava numa linha de status fora da tela e
    // o app parecia apenas "não conectar".
    final bool? testar = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext dialogo) => AlertDialog(
            title: const Text('Não conectou'),
            content: Text(controller.statusMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogo).pop(false),
                child: const Text('Fechar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogo).pop(true),
                child: const Text('Testar caminhos'),
              ),
            ],
          ),
    );
    if ((testar ?? false) && mounted) await _testarCaminhos();
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
    if (!(_storageFormKey.currentState?.validate() ?? false)) {
      return false;
    }
    final int? amount = int.tryParse(_retentionController.text.trim());
    if (amount == null || amount <= 0) {
      _showSnackBar('Informe uma retenção local maior que zero.');
      return false;
    }
    _setRetentionAmount(amount);
    return true;
  }

  bool _applyRemoteRetentionDays() {
    if (!(_storageFormKey.currentState?.validate() ?? false)) {
      return false;
    }
    final int? amount = int.tryParse(_remoteRetentionController.text.trim());
    if (amount == null || amount <= 0) {
      _showSnackBar('Informe uma retenção remota maior que zero.');
      return false;
    }
    _setRemoteRetentionAmount(amount);
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

  void _syncRetentionControllers({bool force = false}) {
    if (force || !_retentionFocusNode.hasFocus) {
      final String value =
          _displayAmountForDays(
            controller.historyRetentionDays,
            _retentionUnit,
          ).toString();
      if (_retentionController.text != value) {
        _retentionController.text = value;
      }
    }

    if (force || !_remoteRetentionFocusNode.hasFocus) {
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
}
