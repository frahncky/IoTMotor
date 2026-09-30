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

part 'settings_conexao.dart';
part 'settings_aquisicao.dart';
part 'settings_armazenamento.dart';

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
    final List<(String, IconData, List<Widget> Function(BuildContext))> abas =
        <(String, IconData, List<Widget> Function(BuildContext))>[
          ('Conexão', Icons.cloud_outlined, _buildConnectionPage),
          (
            'Placas',
            Icons.memory_rounded,
            (BuildContext context) => <Widget>[
              DeviceMaintenanceSection(controller: controller),
            ],
          ),
          (
            'Motor',
            Icons.electric_bolt_rounded,
            (BuildContext context) => <Widget>[
              MotorSettingsPanel(controller: controller),
            ],
          ),
          (
            'Notificações',
            Icons.notifications_active_outlined,
            _buildNotificationsPage,
          ),
          ('Aquisição', Icons.speed_rounded, _buildAcquisitionPage),
          ('Armazenamento', Icons.storage_rounded, _buildStoragePage),
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
              for (final (String nome, IconData icone, _) in abas)
                Tab(
                  key: ValueKey<String>('config_$nome'),
                  text: nome,
                  // Ponto laranja em Placas: há firmware novo para instalar.
                  icon: Badge(
                    isLabelVisible: nome == 'Placas' && atualizacao,
                    backgroundColor: AppTheme.brandOrange,
                    smallSize: 8,
                    child: Icon(icone),
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

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // setState e protegido: as partes (extensoes) atualizam a tela por aqui.
  void _atualizar(VoidCallback mudanca) => setState(mudanca);
}
