import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/providers/esp_local_comm_provider.dart';
import '../../../../app/providers/mqtt_profiles_provider.dart';
import '../../../../app/providers/motor_sound_provider.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/versao.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/device_names.dart';
import '../../models/acquisition_config.dart';
import '../../models/mqtt_connection_config.dart';
import '../../models/motor_info.dart';
import '../../models/telemetry_alert.dart';
import '../../services/app_update_service.dart';
import '../../services/mqtt_path_check.dart';
import '../widgets/alertas_no_celular_panel.dart';
import '../widgets/connection_path_dialog.dart';
import '../../services/mqtt_settings_validators.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';

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
  bool _verificandoAppUpdate = false;

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
                        child: _buildMotorPanel(context),
                      ),
                      _buildTabScrollView(
                        key: 'settings_profiles',
                        delay: const Duration(milliseconds: 180),
                        child: _buildProfilesPanel(context),
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
                            _buildAlertPanel(context),
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
            final double fieldWidth = _fieldWidthFor(constraints.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildPanelTitle(
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
                _buildInlineNotice(
                  context,
                  icon: Icons.info_outline_rounded,
                  color: AppTheme.brandBlue,
                  text: controller.statusMessage,
                ),
                const SizedBox(height: 12),
                _buildMaintenanceSection(context),
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
          _buildPanelTitle(
            context,
            icon: Icons.speed_rounded,
            color: AppTheme.brandMint,
            title: 'Aquisição e registro de dados',
            subtitle: 'Configuração única do sistema. Alterações feitas aqui também valem no painel web e nas placas.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _acqPreset,
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
          _buildInlineNotice(
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

  Widget _buildMotorPanel(BuildContext context) {
    final MotorInfo? info = controller.motorInfo;
    final MotorUsage? uso = controller.motorUsage;
    final MaintenanceStatus? manutencao = controller.maintenanceStatus;
    final bool disponivel =
        controller.isConnected && controller.motorDeviceId != null;
    final sound = ref.watch(motorSoundServiceProvider);

    final List<Widget> dados = <Widget>[];
    void chip(String rotulo, String valor) {
      dados.add(Chip(label: Text('$rotulo: $valor')));
    }

    if (info != null) {
      if (info.currentA != null) {
        chip(
          'Corrente',
          '${_motorPair(info.currentA, info.currentYA)} A',
        );
      }
      if (info.voltageV != null) {
        chip(
          'Tensão',
          '${_motorPair(info.voltageV, info.voltageYV)} V',
        );
      }
      if (info.powerCv != null) chip('Potência', '${_motorNumber(info.powerCv)} cv');
      if (info.rpm != null) chip('Rotação', '${_motorNumber(info.rpm, casas: 0)} rpm');
      if (info.serviceFactor != null) chip('Fator de serviço', _motorNumber(info.serviceFactor));
      if (info.phases != null) chip('Tipo', info.phases == 3 ? 'Trifásico' : 'Monofásico');
      if (info.connectionLabel != null) chip('Ligação', info.connectionLabel!);
      if (info.maintIntervalH != null && info.maintIntervalH! > 0) {
        chip('Manutenção', 'a cada ${_motorNumber(info.maintIntervalH, casas: 0)} h');
      }
    }

    return GlassPanel(
      tint: AppTheme.brandBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildPanelTitle(
            context,
            icon: Icons.electric_bolt_rounded,
            color: AppTheme.brandBlue,
            title: 'Dados do motor',
            subtitle: 'Dados da placa do motor gravados no quadro de comando.',
          ),
          const SizedBox(height: 12),
          if (controller.motorDeviceId != null)
            Text(
              'Quadro: ${nomeComId(controller.motorDeviceId!)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.bodySoft,
              ),
            ),
          if (controller.motorDeviceId != null) const SizedBox(height: 8),
          if (dados.isEmpty)
            _buildInlineNotice(
              context,
              icon: Icons.info_outline_rounded,
              color: AppTheme.brandBlue,
              text: controller.isConnected
                  ? 'Ainda não há dados de placa cadastrados para este motor.'
                  : 'Conecte ao MQTT para ler os dados gravados no quadro.',
            )
          else
            Wrap(spacing: 8, runSpacing: 8, children: dados),
          if (uso != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              usageLine(uso),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (manutencao != null) ...<Widget>[
            const SizedBox(height: 8),
            _buildInlineNotice(
              context,
              icon: manutencao.vencida
                  ? Icons.warning_amber_rounded
                  : Icons.settings_outlined,
              color: manutencao.vencida
                  ? AppTheme.brandOrange
                  : AppTheme.brandBlue,
              text: manutencao.texto,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: disponivel ? () => _editMotorInfo(context) : null,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Editar dados do motor'),
              ),
              OutlinedButton.icon(
                onPressed: disponivel
                    ? () => _confirmMotorAction(
                          context,
                          titulo: 'Manutenção feita',
                          texto:
                              'Registrar a manutenção como feita agora? '
                              'O próximo lembrete contará a partir do horímetro atual.',
                          acao: controller.markMotorMaintenanceDone,
                        )
                    : null,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Manutenção feita'),
              ),
              OutlinedButton.icon(
                onPressed: disponivel && !controller.isMotorRunning
                    ? () => _confirmMotorAction(
                          context,
                          titulo: 'Zerar horímetro e partidas',
                          texto:
                              'Zerar o horímetro e os contadores de partidas? '
                              'Use esta opção ao trocar o motor. O motor deve estar parado.',
                          acao: controller.resetMotorCounters,
                        )
                    : null,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Zerar horímetro e partidas'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(color: AppTheme.inputBorder.withValues(alpha: 0.35)),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(Icons.volume_up_rounded, color: AppTheme.brandMint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Som do motor',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Switch(
                value: sound.enabled,
                onChanged: (bool value) {
                  sound.setEnabled(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Usa o mesmo som da página web e acompanha o estado confirmado do motor.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.bodySoft,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Icon(Icons.volume_down_rounded, size: 18),
              Expanded(
                child: Slider(
                  value: sound.volume,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  label: '${sound.volumePercent}%',
                  onChanged: (double value) {
                    sound.setVolume(value);
                  },
                ),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  '${sound.volumePercent}%',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: controller.isMotorRunning
                    ? null
                    : () {
                        if (sound.testing) {
                          sound.stopTest();
                        } else {
                          sound.testSound();
                        }
                      },
                icon: Icon(
                  sound.testing
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline_rounded,
                ),
                label: Text(sound.testing ? 'Parar teste' : 'Testar som'),
              ),
              if (sound.lastError != null)
                Text(
                  sound.lastError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.danger,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _motorNumber(double? valor, {int casas = 2}) {
    if (valor == null) return '—';
    String texto = valor.toStringAsFixed(casas).replaceAll('.', ',');
    if (casas > 0 && texto.contains(',')) {
      while (texto.endsWith('0')) {
        texto = texto.substring(0, texto.length - 1);
      }
      if (texto.endsWith(',')) {
        texto = texto.substring(0, texto.length - 1);
      }
    }
    return texto;
  }

  String _motorPair(double? primeiro, double? segundo) {
    if (primeiro == null) return '—';
    final String a = _motorNumber(primeiro);
    return segundo == null ? a : '$a/${_motorNumber(segundo)}';
  }

  List<double> _parseMotorPair(String texto, String campo) {
    final String limpo = texto.trim();
    if (limpo.isEmpty) return const <double>[];
    final List<String> partes = limpo.split('/');
    if (partes.length > 2) {
      throw FormatException('$campo: use um valor ou dois separados por /.');
    }
    final List<double> valores = <double>[];
    for (final String parte in partes) {
      final double? valor = double.tryParse(parte.trim().replaceAll(',', '.'));
      if (valor == null || !valor.isFinite || valor <= 0) {
        throw FormatException('$campo: informe um número positivo.');
      }
      valores.add(valor);
    }
    return valores;
  }

  double? _parseMotorOptional(
    String texto,
    String campo, {
    double min = 0,
    double max = double.infinity,
  }) {
    final String limpo = texto.trim();
    if (limpo.isEmpty) return null;
    final double? valor = double.tryParse(limpo.replaceAll(',', '.'));
    if (valor == null || !valor.isFinite || valor < min || valor > max) {
      final String faixa = max.isFinite
          ? ' entre ${_motorNumber(min)} e ${_motorNumber(max)}'
          : ' maior ou igual a ${_motorNumber(min)}';
      throw FormatException('$campo: informe um valor$faixa.');
    }
    return valor;
  }

  Future<void> _editMotorInfo(BuildContext context) async {
    final MotorInfo? atual = controller.motorInfo;
    final TextEditingController corrente = TextEditingController(
      text: atual == null ? '' : _motorPair(atual.currentA, atual.currentYA),
    );
    final TextEditingController tensao = TextEditingController(
      text: atual == null ? '' : _motorPair(atual.voltageV, atual.voltageYV),
    );
    final TextEditingController potencia = TextEditingController(
      text: atual?.powerCv == null ? '' : _motorNumber(atual!.powerCv),
    );
    final TextEditingController rpm = TextEditingController(
      text: atual?.rpm == null ? '' : _motorNumber(atual!.rpm, casas: 0),
    );
    final TextEditingController fs = TextEditingController(
      text: atual?.serviceFactor == null
          ? ''
          : _motorNumber(atual!.serviceFactor),
    );
    final TextEditingController manutencao = TextEditingController(
      text: atual?.maintIntervalH == null
          ? ''
          : _motorNumber(atual!.maintIntervalH, casas: 0),
    );
    int fases = atual?.phases ?? 0;
    String ligacao = atual?.star == true ? 'star' : 'delta';
    String erro = '';

    final Map<String, dynamic>? dados =
        await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            void salvar() {
              try {
                final List<double> correntes =
                    _parseMotorPair(corrente.text, 'Corrente');
                final List<double> tensoes =
                    _parseMotorPair(tensao.text, 'Tensão');
                final bool dupla =
                    correntes.length == 2 || tensoes.length == 2;

                if (dupla &&
                    (correntes.length != 2 || tensoes.length != 2)) {
                  throw const FormatException(
                    'Motor de dupla tensão: informe duas tensões e duas correntes.',
                  );
                }
                if (dupla && fases != 3) {
                  throw const FormatException(
                    'Duas tensões/correntes só podem ser usadas em motor trifásico.',
                  );
                }
                if (tensoes.length == 2 && tensoes[1] <= tensoes[0]) {
                  throw const FormatException(
                    'Tensão: informe primeiro a menor (triângulo) e depois a maior (estrela).',
                  );
                }
                if (correntes.length == 2 && correntes[1] >= correntes[0]) {
                  throw const FormatException(
                    'Corrente: informe primeiro a maior (triângulo) e depois a menor (estrela).',
                  );
                }

                final double? pot = _parseMotorOptional(
                  potencia.text,
                  'Potência',
                  max: 3000,
                );
                final double? rot = _parseMotorOptional(
                  rpm.text,
                  'Rotação',
                  max: 10000,
                );
                final double? fator = _parseMotorOptional(
                  fs.text,
                  'Fator de serviço',
                  min: 1,
                  max: 3,
                );
                final double? intervalo = _parseMotorOptional(
                  manutencao.text,
                  'Manutenção',
                  max: 100000,
                );

                Navigator.of(dialogContext).pop(<String, dynamic>{
                  if (correntes.isNotEmpty) 'current_a': correntes[0],
                  if (correntes.length == 2) 'current_y_a': correntes[1],
                  if (tensoes.isNotEmpty) 'voltage_v': tensoes[0],
                  if (tensoes.length == 2) 'voltage_y_v': tensoes[1],
                  if (pot != null) 'power_cv': pot,
                  if (rot != null) 'rpm': rot,
                  if (fator != null) 'service_factor': fator,
                  if (fases != 0) 'phases': fases,
                  if (dupla) 'connection': ligacao,
                  if (intervalo != null) 'maint_interval_h': intervalo,
                });
              } on FormatException catch (e) {
                setDialogState(() => erro = e.message.toString());
              }
            }

            return AlertDialog(
              title: const Text('Dados do motor'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: corrente,
                        keyboardType: TextInputType.text,
                        decoration: const InputDecoration(
                          labelText: 'Corrente nominal (A)',
                          hintText: 'Ex.: 12,6/7,3',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: tensao,
                        keyboardType: TextInputType.text,
                        decoration: const InputDecoration(
                          labelText: 'Tensão nominal (V)',
                          hintText: 'Ex.: 220/380',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        initialValue: fases,
                        decoration: const InputDecoration(labelText: 'Tipo'),
                        items: const <DropdownMenuItem<int>>[
                          DropdownMenuItem<int>(
                            value: 0,
                            child: Text('Não informado'),
                          ),
                          DropdownMenuItem<int>(
                            value: 3,
                            child: Text('Trifásico'),
                          ),
                          DropdownMenuItem<int>(
                            value: 1,
                            child: Text('Monofásico'),
                          ),
                        ],
                        onChanged: (int? value) {
                          setDialogState(() => fases = value ?? 0);
                        },
                      ),
                      if (fases == 3) ...<Widget>[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: ligacao,
                          decoration: const InputDecoration(
                            labelText: 'Ligação em uso',
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(
                              value: 'delta',
                              child: Text('Triângulo (Δ)'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'star',
                              child: Text('Estrela (Y)'),
                            ),
                          ],
                          onChanged: (String? value) {
                            setDialogState(
                              () => ligacao = value ?? 'delta',
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: potencia,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Potência (cv)'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: rpm,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Rotação (rpm)'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: fs,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Fator de serviço',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: manutencao,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Manutenção a cada (h de uso)',
                        ),
                      ),
                      if (erro.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          erro,
                          style: TextStyle(color: AppTheme.danger),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: salvar,
                  child: const Text('Gravar no quadro'),
                ),
              ],
            );
          },
        );
      },
    );

    for (final TextEditingController campo in <TextEditingController>[
      corrente,
      tensao,
      potencia,
      rpm,
      fs,
      manutencao,
    ]) {
      campo.dispose();
    }

    if (dados == null || !mounted) return;
    final bool ok = await controller.saveMotorInfo(dados);
    if (ok && mounted) {
      _showSnackBar('Dados do motor enviados ao quadro.');
    }
  }

  Future<void> _confirmMotorAction(
    BuildContext context, {
    required String titulo,
    required String texto,
    required Future<bool> Function() acao,
  }) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (!(confirmar ?? false)) return;
    final bool ok = await acao();
    if (ok && mounted) {
      _showSnackBar('$titulo: comando enviado.');
    }
  }

  /// Manutenção do ESP32 pelo app: cadastrar Wi-Fi e atualizar firmware.
  ///
  /// A senha do Wi-Fi não é enviada por MQTT: o broker é público. O app apenas
  /// pede que a placa abra a própria rede, onde a senha é digitada.
  Widget _buildMaintenanceSection(BuildContext context) {
    final bool conectado = widget.controller.isConnected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Manutenção do ESP32',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        // Versão de cada placa frente à publicada para OTA.
        for (final String placa in widget.controller.firmwareByDevice.keys)
          if (widget.controller.firmwareOf(placa) case final ({String texto, bool atualizar}) firmware)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${nomeDaPlaca(placa)}: firmware ${firmware.texto}${firmware.atualizar ? ' — use "Atualizar firmware" com a placa selecionada' : ''}.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: firmware.atualizar ? AppTheme.brandOrange : AppTheme.bodySoft,
                ),
              ),
            ),
        // Versão instalada do app, com o nome dela.
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (BuildContext context, AsyncSnapshot<PackageInfo> pacote) => Text(
            'App: versão ${pacote.data?.version ?? '…'} — $nomeDaVersao.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.bodySoft),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed:
                  conectado
                      ? () => _confirmarManutencao(
                        context,
                        action: 'wifi_portal',
                        titulo: 'Cadastrar Wi-Fi na placa',
                        texto:
                            'A placa sai da rede atual e abre a rede "IoTMotor-" por 3 minutos.\n\n'
                            'Conecte o celular nessa rede e informe o Wi-Fi novo na página que abrir. '
                            'A senha vai direto para a placa, sem passar pelo broker público.',
                      )
                      : null,
              icon: const Icon(Icons.wifi_password_rounded),
              label: const Text('Cadastrar Wi-Fi'),
            ),
            OutlinedButton.icon(
              onPressed:
                  conectado
                      ? () => _confirmarManutencao(
                        context,
                        action: 'update',
                        titulo: 'Atualizar firmware',
                        texto:
                            'A placa baixa o firmware publicado no GitHub e reinicia. '
                            'Só funciona com as saídas desligadas.',
                      )
                      : null,
              icon: const Icon(Icons.system_update_alt_rounded),
              label: const Text('Atualizar firmware'),
            ),
            OutlinedButton.icon(
              onPressed:
                  _verificandoAppUpdate ? null : _verificarAtualizacaoDoApp,
              icon:
                  _verificandoAppUpdate
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.phone_android_rounded),
              label: Text(
                _verificandoAppUpdate ? 'Verificando...' : 'Atualizar este app',
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// "2.1.0 — Alertas no celular"; sem o número de build, que só o CI usa.
  static String _comNome(String versao, String nome) {
    final String numero = versao.split('+').first;
    return nome.isEmpty ? numero : '$numero — $nome';
  }

  /// Verifica, baixa e entrega o APK ao instalador do Android, sem navegador.
  ///
  /// O sistema sempre pede a confirmação final: nenhum app se instala sozinho.
  Future<void> _verificarAtualizacaoDoApp() async {
    setState(() => _verificandoAppUpdate = true);
    final AppUpdateService servico = AppUpdateService();
    try {
      final AppUpdateInfo info = await servico.check();
      if (!mounted) return;
      if (!info.updateAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'O app já está na versão publicada (${_comNome(info.publishedVersion, info.publishedName)}).',
            ),
          ),
        );
        return;
      }
      final bool? atualizar = await showDialog<bool>(
        context: context,
        builder:
            (BuildContext dialogContext) => AlertDialog(
              title: const Text('Nova versão do app'),
              content: Text(
                'Publicada: ${_comNome(info.publishedVersion, info.publishedName)} (build ${info.publishedBuild}, commit ${info.commit}).\n'
                'Instalada: ${_comNome(info.installedVersion, nomeDaVersao)}'
                '${info.installedBuild.isEmpty ? " (sem selo de build)" : " (build ${info.installedBuild})"}.\n\n'
                'O app baixa a versão nova e abre a instalação do Android. '
                'Na primeira vez, autorize "instalar apps desconhecidos".',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Agora não'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Atualizar agora'),
                ),
              ],
            ),
      );
      if (!(atualizar ?? false) || info.apkUrl.isEmpty) return;
      if (!mounted) return;

      final ValueNotifier<double> progresso = ValueNotifier<double>(0);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (BuildContext dialogContext) => AlertDialog(
              title: const Text('Baixando a atualização'),
              content: ValueListenableBuilder<double>(
                valueListenable: progresso,
                builder: (BuildContext context, double valor, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      LinearProgressIndicator(value: valor > 0 ? valor : null),
                      const SizedBox(height: 10),
                      Text(
                        valor > 0
                            ? '${(valor * 100).toStringAsFixed(0)}%'
                            : 'Iniciando…',
                      ),
                    ],
                  );
                },
              ),
            ),
      );

      try {
        await servico.baixarEInstalar(
          info.apkUrl,
          onProgresso: (double valor) => progresso.value = valor,
          // Chega depois que a pessoa confirma ou recusa na tela do Android.
          onResultado: (String estado, String? motivo) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  estado == 'instalado'
                      ? 'Atualização instalada. Abra o app de novo.'
                      : 'Instalação não concluída: ${motivo ?? estado}',
                ),
              ),
            );
          },
        );
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Confirme a instalação na tela do Android.'),
            ),
          );
        }
      } catch (erro) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (mounted) {
          // Sem permissão ou download interrompido: oferece o caminho manual.
          final bool? navegador = await showDialog<bool>(
            context: context,
            builder:
                (BuildContext dialogContext) => AlertDialog(
                  title: const Text('Não deu para instalar daqui'),
                  content: Text('$erro'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Fechar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Baixar pelo navegador'),
                    ),
                  ],
                ),
          );
          if (navegador ?? false) {
            await launchUrl(
              Uri.parse(info.apkUrl),
              mode: LaunchMode.externalApplication,
            );
          }
        }
      } finally {
        progresso.dispose();
      }
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao verificar atualização: $erro')),
      );
    } finally {
      servico.dispose();
      if (mounted) setState(() => _verificandoAppUpdate = false);
    }
  }

  Future<void> _confirmarManutencao(
    BuildContext context, {
    required String action,
    required String titulo,
    required String texto,
  }) async {
    final bool? confirmado = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: Text(titulo),
            content: Text(texto),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
    if (confirmado ?? false) {
      await widget.controller.sendMaintenanceCommand(action);
    }
  }

  Widget _buildProfilesPanel(BuildContext context) {
    final MqttProfilesState profilesState = ref.watch(mqttProfilesProvider);
    final String? activeId = profilesState.activeProfileId;

    return GlassPanel(
      tint: AppTheme.brandBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildPanelTitle(
            context,
            icon: Icons.account_tree_rounded,
            color: AppTheme.brandBlue,
            title: 'Perfis MQTT',
            subtitle: 'Salve e alterne rapidamente entre brokers e tópicos.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => _openProfileEditor(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Novo perfil'),
              ),
              OutlinedButton.icon(
                onPressed: _saveCurrentConnectionAsProfile,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Salvar conexão atual'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (profilesState.profiles.isEmpty)
            _buildInlineNotice(
              context,
              icon: Icons.info_outline_rounded,
              color: AppTheme.brandBlue,
              text: 'Nenhum perfil MQTT salvo.',
            )
          else
            Column(
              children: <Widget>[
                for (final MqttProfile profile in profilesState.profiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildProfileTile(
                      context,
                      profile: profile,
                      isActive: profile.id == activeId,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildProfileTile(
    BuildContext context, {
    required MqttProfile profile,
    required bool isActive,
  }) {
    final Color color = isActive ? AppTheme.brandMint : AppTheme.brandBlue;
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
          Icon(
            isActive ? Icons.check_circle_rounded : Icons.dns_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  profile.name,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.config.host}:${profile.config.port} | '
                  '${profile.config.topicPrefix} | '
                  '${profile.config.useTls ? 'TLS' : 'TCP'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 4,
            children: <Widget>[
              IconButton(
                tooltip: isActive ? 'Perfil ativo' : 'Ativar perfil',
                onPressed:
                    isActive
                        ? null
                        : () => ref
                            .read(mqttProfilesProvider.notifier)
                            .setActiveProfile(profile.id),
                icon: const Icon(Icons.playlist_add_check_rounded),
              ),
              IconButton(
                tooltip: 'Editar perfil',
                onPressed: () => _openProfileEditor(initial: profile),
                icon: const Icon(Icons.edit_rounded),
              ),
              IconButton(
                tooltip: 'Excluir perfil',
                onPressed:
                    ref.watch(mqttProfilesProvider).profiles.length <= 1
                        ? null
                        : () => _confirmDeleteProfile(profile),
                icon: const Icon(Icons.delete_outline_rounded),
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
            final double fieldWidth = _fieldWidthFor(constraints.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildPanelTitle(
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
                    child: _buildPanelTitle(
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

  Widget _buildTelemetryFormatPanel(BuildContext context) {
    return GlassPanel(
      tint: AppTheme.brandOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildPanelTitle(
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

  Widget _buildPanelTitle(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
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
    required TextEditingController controllerField,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
    String? suffixText,
    String? helperText,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controllerField,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textInputAction: TextInputAction.next,
        onChanged: (_) {
          setState(() {});
          controller.refreshPreview();
        },
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffixText,
          helperText: helperText,
          helperMaxLines: 2,
        ),
      ),
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

  Future<void> _openProfileEditor({MqttProfile? initial}) async {
    final nameController = TextEditingController(
      text: initial?.name ?? _suggestProfileName(),
    );
    final brokerController = TextEditingController(
      text: initial?.config.host ?? controller.brokerController.text.trim(),
    );
    final portController = TextEditingController(
      text:
          (initial?.config.port ??
                  int.tryParse(controller.portController.text.trim()) ??
                  1883)
              .toString(),
    );
    final clientIdController = TextEditingController(
      text:
          initial?.config.clientId ?? controller.clientIdController.text.trim(),
    );
    final topicPrefixController = TextEditingController(
      text:
          initial?.config.topicPrefix ??
          controller.topicPrefixController.text.trim(),
    );
    final deviceIdController = TextEditingController(
      text:
          initial?.config.deviceId ??
          (controller.deviceIdController.text.isEmpty
              ? 'default'
              : controller.deviceIdController.text),
    );
    final usernameController = TextEditingController(
      text:
          initial?.config.username ?? controller.usernameController.text.trim(),
    );
    final passwordController = TextEditingController(
      text: initial?.config.password ?? controller.passwordController.text,
    );
    bool useTls = initial?.config.useTls ?? controller.useTls;
    final formKey = GlobalKey<FormState>();

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: Text(
                initial == null ? 'Novo perfil MQTT' : 'Editar perfil MQTT',
              ),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Nome'),
                          textInputAction: TextInputAction.next,
                          validator: (String? value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Informe o nome do perfil.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: brokerController,
                          decoration: const InputDecoration(
                            labelText: 'Broker host',
                          ),
                          textInputAction: TextInputAction.next,
                          validator: MqttSettingsValidators.validateBroker,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: portController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Porta'),
                          textInputAction: TextInputAction.next,
                          validator: MqttSettingsValidators.validatePort,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: clientIdController,
                          decoration: const InputDecoration(
                            labelText: 'Client ID',
                          ),
                          textInputAction: TextInputAction.next,
                          validator: MqttSettingsValidators.validateClientId,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: topicPrefixController,
                          decoration: const InputDecoration(
                            labelText: 'Topic prefix',
                          ),
                          textInputAction: TextInputAction.next,
                          validator: MqttSettingsValidators.validateTopicPrefix,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: deviceIdController,
                          decoration: const InputDecoration(
                            labelText: 'Device ID',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Usuário (opcional)',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: passwordController,
                          decoration: const InputDecoration(
                            labelText: 'Senha (opcional)',
                          ),
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Usar TLS'),
                          value: useTls,
                          onChanged: (bool value) {
                            setDialogState(() {
                              useTls = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!(formKey.currentState?.validate() ?? false)) {
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      _disposeControllers(<TextEditingController>[
        nameController,
        brokerController,
        portController,
        clientIdController,
        topicPrefixController,
        deviceIdController,
        usernameController,
        passwordController,
      ]);
      return;
    }

    final MqttProfile profile = MqttProfile(
      id: initial?.id ?? 'profile_${DateTime.now().millisecondsSinceEpoch}',
      name: nameController.text.trim(),
      config: MqttConnectionConfig(
        host: brokerController.text.trim(),
        port: int.parse(portController.text.trim()),
        clientId: clientIdController.text.trim(),
        topicPrefix: topicPrefixController.text.trim(),
        deviceId:
            deviceIdController.text.trim().isEmpty
                ? 'default'
                : deviceIdController.text.trim(),
        useTls: useTls,
        username:
            usernameController.text.trim().isEmpty
                ? null
                : usernameController.text.trim(),
        password:
            passwordController.text.isEmpty ? null : passwordController.text,
      ),
    );

    final MqttProfilesNotifier notifier = ref.read(
      mqttProfilesProvider.notifier,
    );
    if (initial == null) {
      await notifier.addProfile(profile);
      _showSnackBar('Perfil "${profile.name}" criado.');
    } else {
      await notifier.updateProfile(profile);
      _showSnackBar('Perfil "${profile.name}" atualizado.');
    }

    _disposeControllers(<TextEditingController>[
      nameController,
      brokerController,
      portController,
      clientIdController,
      topicPrefixController,
      deviceIdController,
      usernameController,
      passwordController,
    ]);
  }

  Future<void> _saveCurrentConnectionAsProfile() async {
    if (!(_connectionFormKey.currentState?.validate() ?? false)) {
      _showSnackBar('Revise os dados da conexão antes de salvar o perfil.');
      return;
    }
    await _openProfileEditor();
  }

  Future<void> _confirmDeleteProfile(MqttProfile profile) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Excluir perfil'),
          content: Text('Remover o perfil "${profile.name}"?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await ref.read(mqttProfilesProvider.notifier).deleteProfile(profile.id);
      _showSnackBar('Perfil "${profile.name}" removido.');
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

  String _suggestProfileName() {
    final String host = controller.brokerController.text.trim();
    if (host.isEmpty) {
      return 'Novo perfil';
    }
    return host;
  }

  void _disposeControllers(List<TextEditingController> controllers) {
    for (final TextEditingController controller in controllers) {
      controller.dispose();
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
