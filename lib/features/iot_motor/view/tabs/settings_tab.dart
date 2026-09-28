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
import '../widgets/app_section.dart';
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
    final bool atualizacao = controller.boardsToUpdate.isNotEmpty;
    final List<(String, Widget?, List<Widget> Function(BuildContext))> abas =
        <(String, Widget?, List<Widget> Function(BuildContext))>[
          ('Conexão', null, _buildConnectionPage),
          (
            'Placas',
            // Ponto laranja: há firmware novo para instalar.
            atualizacao
                ? Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppTheme.brandOrange,
                    shape: BoxShape.circle,
                  ),
                )
                : null,
            (BuildContext context) => <Widget>[
              DeviceMaintenanceSection(controller: controller),
            ],
          ),
          (
            'Motor',
            null,
            (BuildContext context) => <Widget>[
              MotorSettingsPanel(controller: controller),
            ],
          ),
          ('Notificações', null, _buildNotificationsPage),
          ('Aquisição', null, _buildAcquisitionPage),
          ('Armazenamento', null, _buildStoragePage),
        ];

    return DefaultTabController(
      key: const ValueKey<String>('tab_configuracoes'),
      length: abas.length,
      child: Column(
        children: <Widget>[
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: AppTheme.inputBorder.withValues(alpha: 0.3),
            tabs: <Widget>[
              for (final (String nome, Widget? marca, _) in abas)
                Tab(
                  key: ValueKey<String>('config_$nome'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(nome),
                      if (marca != null) ...<Widget>[
                        const SizedBox(width: 6),
                        marca,
                      ],
                    ],
                  ),
                ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                for (final (
                      String nome,
                      _,
                      List<Widget> Function(BuildContext) corpo,
                    )
                    in abas)
                  ListView(
                    key: ValueKey<String>('config_pagina_$nome'),
                    padding: appPagePadding,
                    children: corpo(context),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildConnectionPage(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    return <Widget>[
      ProfilesSettingsPanel(
        controller: controller,
        validateConnection:
            () => _connectionFormKey.currentState?.validate() ?? false,
      ),
      appSectionGap,
      Form(
        key: _connectionFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppSection(
              title: 'Broker MQTT',
              children: <Widget>[
                _textField(
                  label: 'Endereço do broker',
                  controllerField: controller.brokerController,
                  validator: MqttSettingsValidators.validateBroker,
                  helperText:
                      'Em rede que bloqueia MQTT: ws://test.mosquitto.org, porta 8080',
                ),
                _textField(
                  label: 'Porta',
                  controllerField: controller.portController,
                  keyboardType: TextInputType.number,
                  validator: MqttSettingsValidators.validatePort,
                ),
                _textField(
                  label: 'Usuário (opcional)',
                  controllerField: controller.usernameController,
                ),
                _textField(
                  label: 'Senha (opcional)',
                  controllerField: controller.passwordController,
                  obscureText: true,
                ),
                // Só aparece se a placa foi gravada exigindo comando
                // cifrado; por padrão os comandos viajam abertos.
                if (controller.commandPasswordNeeded)
                  _textField(
                    label: 'Senha de comando',
                    controllerField: controller.commandPasswordController,
                    obscureText: true,
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('TLS'),
                  subtitle: const Text('Conexão cifrada com o broker'),
                  value: controller.useTls,
                  onChanged: controller.setTls,
                ),
                const SizedBox(height: 4),
                Text(
                  controller.connectionMessage,
                  key: const ValueKey<String>('connection_message'),
                  style: texto.bodySmall,
                ),
                const SizedBox(height: 12),
                AppButtons(
                  children: <Widget>[
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
                  ],
                ),
              ],
            ),
            appSectionGap,
            _recolhido(
              context,
              key: 'config_avancado',
              titulo: 'Avançado',
              subtitulo: 'Identificação, tópicos e comunicação local',
              children: <Widget>[
                _textField(
                  label: 'Client ID',
                  controllerField: controller.clientIdController,
                  validator: MqttSettingsValidators.validateClientId,
                ),
                _textField(
                  label: 'Prefixo dos tópicos',
                  controllerField: controller.topicPrefixController,
                  validator: MqttSettingsValidators.validateTopicPrefix,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    // initialValue só vale na criação: a chave recria o
                    // campo quando a placa escolhida muda por fora.
                    key: ValueKey<String>(controller.deviceIdController.text),
                    initialValue:
                        controller.deviceIdController.text.isEmpty
                            ? null
                            : controller.deviceIdController.text,
                    decoration: const InputDecoration(
                      labelText: 'Placa em destaque',
                      hintText: 'Automático',
                    ),
                    items: () {
                      final Set<String> allIds = <String>{
                        ...controller.knownDeviceIds,
                        ...controller.connectedDeviceIds,
                        if (controller.deviceIdController.text.isNotEmpty)
                          controller.deviceIdController.text,
                      };
                      final List<String> sortedIds = allIds.toList()..sort();
                      return sortedIds.map<DropdownMenuItem<String>>((
                        String id,
                      ) {
                        final bool isOnline = controller.connectedDeviceIds
                            .contains(id);
                        final bool isKnown = controller.knownDeviceIds.contains(
                          id,
                        );
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.circle,
                                size: 10,
                                color: isOnline ? AppTheme.online : Colors.grey,
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
                    onChanged: (String? val) {
                      controller.setDeviceId(val ?? '');
                      controller.refreshPreview();
                    },
                  ),
                ),
                _textField(
                  label: 'IP do ESP32 (rede local)',
                  controllerField: _espIpController,
                  keyboardType: TextInputType.url,
                ),
                OutlinedButton.icon(
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
                          : const Icon(Icons.wifi_tethering_rounded),
                  label: Text(
                    _isTestingLocalComm
                        ? 'Testando...'
                        : 'Testar comunicação local',
                  ),
                ),
                const SizedBox(height: 16),
                AppInfoRow(
                  key: const ValueKey<String>('connection_devices_summary'),
                  label: 'Dispositivos',
                  value: controller.devicesPresenceSummary,
                ),
                AppInfoRow(
                  key: const ValueKey<String>('connection_clients_summary'),
                  label: 'Clientes',
                  value: controller.commandClientsSummary,
                ),
                AppInfoRow(label: 'Comandos', value: controller.commandTopic),
                AppInfoRow(
                  label: 'Telemetria',
                  value: controller.telemetryTopic,
                ),
                AppInfoRow(label: 'Status', value: controller.statusTopic),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  /// Seção que abre e fecha, para o que só se ajusta de vez em quando.
  Widget _recolhido(
    BuildContext context, {
    required String key,
    required String titulo,
    required String subtitulo,
    required List<Widget> children,
  }) {
    return Material(
      color: AppTheme.surfaceSoft,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey<String>(key),
          // Recolhido, os campos continuam montados: o Form da conexão
          // precisa validá-los mesmo com "Avançado" fechado.
          maintainState: true,
          title: Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(
            subtitulo,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  List<Widget> _buildNotificationsPage(BuildContext context) {
    return <Widget>[
      AlertasNoCelularPanel(controller: controller),
      appSectionGap,
      _recolhido(
        context,
        key: 'config_limites_app',
        titulo: 'Limites do app',
        subtitulo:
            'Avisos extras do app. Os alarmes da placa ficam na aba Alertas.',
        children: <Widget>[AlertSettingsPanel(controller: controller)],
      ),
    ];
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
    for (final MapEntry<String, AcquisitionConfig> entry
        in AcquisitionConfig.presets.entries) {
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
    if (pzem == null || pub == null || chart == null || record == null) {
      return null;
    }
    return AcquisitionConfig(
      revision: controller.acquisitionConfig.revision,
      pzemReadMs: pzem,
      publishMs: pub,
      chartMs: chart,
      recordMs: record,
    );
  }

  List<Widget> _buildAcquisitionPage(BuildContext context) {
    final AcquisitionConfig cfg = controller.acquisitionConfig;
    return <Widget>[
      AppSection(
        title: 'Intervalos',
        subtitle: 'Valem para o app, o painel web e as placas.',
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              initialValue: _acqPreset,
              decoration: const InputDecoration(labelText: 'Perfil'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'custom', child: Text('Personalizado')),
                DropdownMenuItem(value: 'realtime', child: Text('Tempo real')),
                DropdownMenuItem(
                  value: 'monitoring',
                  child: Text('Monitoramento'),
                ),
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
          ),
          _textField(
            label: 'Leitura elétrica',
            suffixText: 's',
            controllerField: _acqPzemController,
            keyboardType: TextInputType.number,
          ),
          _textField(
            label: 'Envio pelo MQTT',
            suffixText: 's',
            controllerField: _acqPublishController,
            keyboardType: TextInputType.number,
          ),
          _textField(
            label: 'Pontos do gráfico',
            suffixText: 's',
            controllerField: _acqChartController,
            keyboardType: TextInputType.number,
          ),
          _textField(
            label: 'Registro de dados',
            suffixText: 's',
            controllerField: _acqRecordController,
            keyboardType: TextInputType.number,
          ),
          Text(
            cfg.revision > 0
                ? 'Sincronizado com o quadro · revisão ${cfg.revision}'
                : 'Aguardando a configuração do quadro de comando',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          AppButtons(
            children: <Widget>[
              FilledButton.icon(
                onPressed:
                    controller.isConnected
                        ? () async {
                          final AcquisitionConfig? nova =
                              _acquisitionFromFields();
                          if (nova == null) {
                            _showSnackBar(
                              'Informe os quatro intervalos em segundos.',
                            );
                            return;
                          }
                          final String? erro = nova.validate();
                          if (erro != null) {
                            _showSnackBar(erro);
                            return;
                          }
                          await controller.saveAcquisitionConfig(nova);
                        }
                        : null,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Gravar e sincronizar'),
              ),
              OutlinedButton.icon(
                onPressed:
                    controller.isConnected
                        ? controller.requestAcquisitionConfig
                        : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Ler da placa'),
              ),
            ],
          ),
        ],
      ),
      appSectionGap,
      AppSection(
        title: 'Fixos no firmware',
        children: <Widget>[
          AppInfoRow(
            label: 'Amostragem da vibração',
            value: '${cfg.vibrationHz} Hz',
          ),
          AppInfoRow(
            label: 'Janela RMS',
            value: '${cfg.vibrationWindowMs ~/ 1000} s',
          ),
          AppInfoRow(
            label: 'Histórico da placa',
            value:
                'a cada ${cfg.historyBucketS ~/ 60} min, ${cfg.historyRetentionDays} dias',
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildStoragePage(BuildContext context) {
    return <Widget>[
      Form(
        key: _storageFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppSection(
              title: 'Neste celular',
              subtitle: controller.historyRetentionSummary,
              children: <Widget>[
                _retentionField(
                  label: 'Guardar por',
                  controllerField: _retentionController,
                  focusNode: _retentionFocusNode,
                  unit: _retentionUnit,
                  fieldLabel: 'a retenção local',
                  onSubmitted: _applyRetentionDays,
                ),
                _buildRetentionUnitSelector(
                  selected: _retentionUnit,
                  onChanged: _setRetentionUnit,
                ),
                const SizedBox(height: 12),
                AppButtons(
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _applyRetentionDays,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Aplicar'),
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
            ),
            appSectionGap,
            AppSection(
              title: 'No cartão SD do ESP32',
              subtitle: controller.remoteHistoryRetentionSummary,
              children: <Widget>[
                _retentionField(
                  label: 'Guardar por',
                  controllerField: _remoteRetentionController,
                  focusNode: _remoteRetentionFocusNode,
                  unit: _remoteRetentionUnit,
                  fieldLabel: 'a retenção remota',
                  onSubmitted: _applyRemoteRetentionDays,
                ),
                _buildRetentionUnitSelector(
                  selected: _remoteRetentionUnit,
                  onChanged: _setRemoteRetentionUnit,
                ),
                const SizedBox(height: 12),
                AppButtons(
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _applyAndSendRemoteRetention,
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('Aplicar no ESP32'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _retentionField({
    required String label,
    required TextEditingController controllerField,
    required FocusNode focusNode,
    required _RetentionUnit unit,
    required String fieldLabel,
    required bool Function() onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controllerField,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: label,
          suffixText: _retentionUnitLabel(unit),
          hintText: 'Ex: 30',
        ),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator:
            (String? value) => MqttSettingsValidators.validateDecimal(
              value,
              fieldLabel: fieldLabel,
              min: 0,
              allowZero: false,
            ),
        onFieldSubmitted: (_) => onSubmitted(),
      ),
    );
  }

  Widget _buildRetentionUnitSelector({
    required _RetentionUnit selected,
    required ValueChanged<_RetentionUnit> onChanged,
  }) {
    return SizedBox(
      width: double.infinity,
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
          textStyle: WidgetStatePropertyAll<TextStyle?>(
            Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controllerField,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
    String? suffixText,
    String? helperText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: settingsTextField(
        width: double.infinity,
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
      // Os campos de "Avançado" podem estar recolhidos: diz onde olhar.
      final bool avancado =
          MqttSettingsValidators.validateClientId(
                controller.clientIdController.text,
              ) !=
              null ||
          MqttSettingsValidators.validateTopicPrefix(
                controller.topicPrefixController.text,
              ) !=
              null;
      _showSnackBar(
        avancado
            ? 'Revise o Client ID ou o prefixo dos tópicos em "Avançado".'
            : 'Revise os dados da conexão MQTT.',
      );
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
