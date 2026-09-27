import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../app/theme/app_theme.dart';
import '../../../../../app/versao.dart';
import '../../../controller/motor_control_controller.dart';
import '../../../models/device_names.dart';
import '../../../services/app_update_service.dart';

/// Firmware das placas e atualização do app, dentro da aba "Conexão".
class DeviceMaintenanceSection extends StatefulWidget {
  const DeviceMaintenanceSection({super.key, required this.controller});

  final MotorControlController controller;

  @override
  State<DeviceMaintenanceSection> createState() => _DeviceMaintenanceSectionState();
}

class _DeviceMaintenanceSectionState extends State<DeviceMaintenanceSection> {
  MotorControlController get controller => widget.controller;
  bool _verificandoAppUpdate = false;

  @override
  Widget build(BuildContext context) => _buildMaintenanceSection(context);

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
}
