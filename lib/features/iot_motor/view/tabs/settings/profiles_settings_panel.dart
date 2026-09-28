import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../app/providers/mqtt_profiles_provider.dart';
import '../../../../../app/theme/app_theme.dart';
import '../../../controller/motor_control_controller.dart';
import '../../../models/mqtt_connection_config.dart';
import '../../../services/mqtt_settings_validators.dart';
import '../../widgets/app_section.dart';

/// Aba "Perfis": perfis MQTT salvos, editor e exclusão.
class ProfilesSettingsPanel extends ConsumerStatefulWidget {
  const ProfilesSettingsPanel({super.key, required this.controller, required this.validateConnection});

  final MotorControlController controller;

  /// Valida o formulário da aba "Conexão" antes de salvar como perfil.
  final bool Function() validateConnection;

  @override
  ConsumerState<ProfilesSettingsPanel> createState() => _ProfilesSettingsPanelState();
}

class _ProfilesSettingsPanelState extends ConsumerState<ProfilesSettingsPanel> {
  MotorControlController get controller => widget.controller;

  @override
  Widget build(BuildContext context) => _buildProfilesPanel(context);

  Widget _buildProfilesPanel(BuildContext context) {
    final MqttProfilesState profilesState = ref.watch(mqttProfilesProvider);
    final String? activeId = profilesState.activeProfileId;
    final bool podeExcluir = profilesState.profiles.length > 1;

    return AppSection(
      title: 'Perfil',
      subtitle: 'Toque em um perfil para usá-lo.',
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      children: <Widget>[
        if (profilesState.profiles.isEmpty)
          Text('Nenhum perfil salvo.', style: Theme.of(context).textTheme.bodyMedium)
        else
          for (final MqttProfile profile in profilesState.profiles)
            _buildProfileTile(
              context,
              profile: profile,
              isActive: profile.id == activeId,
              podeExcluir: podeExcluir,
            ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Expanded(
              child: TextButton.icon(
                onPressed: () => _openProfileEditor(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Novo perfil'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: _saveCurrentConnectionAsProfile,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar atual'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileTile(
    BuildContext context, {
    required MqttProfile profile,
    required bool isActive,
    required bool podeExcluir,
  }) {
    return ListTile(
      key: ValueKey<String>('perfil_${profile.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isActive ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
        color: isActive ? AppTheme.brandMint : AppTheme.labelSoft,
      ),
      title: Text(profile.name),
      subtitle: Text(
        '${profile.config.host}:${profile.config.port}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap:
          isActive
              ? null
              : () => ref.read(mqttProfilesProvider.notifier).setActiveProfile(profile.id),
      trailing: PopupMenuButton<String>(
        tooltip: 'Opções do perfil',
        onSelected: (String acao) {
          if (acao == 'editar') _openProfileEditor(initial: profile);
          if (acao == 'excluir') _confirmDeleteProfile(profile);
        },
        itemBuilder:
            (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'editar', child: Text('Editar')),
              PopupMenuItem<String>(
                value: 'excluir',
                enabled: podeExcluir,
                child: const Text('Excluir'),
              ),
            ],
      ),
    );
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
    if (!(widget.validateConnection())) {
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
  }}
