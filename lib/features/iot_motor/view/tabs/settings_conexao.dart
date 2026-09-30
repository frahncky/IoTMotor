part of 'settings_tab.dart';

/// Páginas Conexão e Notificações das Configurações.
extension _ConfiguracoesConexao on _ConfiguracoesTabState {
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
}
