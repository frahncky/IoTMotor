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
    final List<String> placas = <String>{
      ...widget.controller.firmwareByDevice.keys,
      ...widget.controller.firmwareUpdateDeviceIds,
    }.toList()..sort();
    final bool otaEmAndamento = widget.controller.firmwareUpdateDeviceIds
        .any(widget.controller.isFirmwareUpdating);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Manutenção do ESP32',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        // Versão/estado OTA de cada placa. Durante o reboot da OTA, mantém
        // "Atualizando firmware…" em vez de trocar para "desconectado".
        for (final String placa in placas)
          _buildFirmwareLine(context, placa),
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
                  conectado && widget.controller.maintenanceBoards.isNotEmpty
                      ? () => _cadastrarWifi(context)
                      : null,
              icon: const Icon(Icons.wifi_password_rounded),
              label: const Text('Cadastrar Wi-Fi'),
            ),
            OutlinedButton.icon(
              // Vai para cada placa no ar com firmware diferente do publicado.
              // Se todas as placas elegíveis já estão em OTA, fica desabilitado
              // mostrando o progresso; a outra placa continua independente.
              onPressed:
                  conectado && widget.controller.boardsToUpdate.isNotEmpty
                      ? () => _confirmarManutencao(
                        context,
                        action: 'update',
                        placas: widget.controller.boardsToUpdate,
                        titulo: 'Atualizar firmware',
                        texto:
                            'Vai atualizar: ${widget.controller.boardsToUpdate.map(nomeDaPlaca).join(' e ')}.\n\n'
                            'Cada placa baixa o firmware publicado no GitHub e reinicia '
                            '(cerca de 1 minuto fora do ar). O quadro de comando só aceita '
                            'com o motor parado.',
                      )
                      : null,
              icon:
                  otaEmAndamento && widget.controller.boardsToUpdate.isEmpty
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.system_update_alt_rounded),
              label: Text(
                otaEmAndamento && widget.controller.boardsToUpdate.isEmpty
                    ? 'Atualizando firmware…'
                    : conectado && widget.controller.boardsToUpdate.isEmpty
                    ? 'Sem atualização disponível'
                    : 'Atualizar firmware',
              ),
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

  Widget _buildFirmwareLine(BuildContext context, String placa) {
    final String? ota = widget.controller.firmwareUpdateLabel(placa);
    if (ota != null) {
      final bool concluida = widget.controller.firmwareUpdateSucceeded(placa);
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          '${nomeDaPlaca(placa)}: $ota.',
          key: ValueKey<String>('firmware_update_$placa'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: concluida ? AppTheme.brandMint : AppTheme.brandOrange,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    final ({String texto, bool atualizar})? firmware =
        widget.controller.firmwareOf(placa);
    if (firmware == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '${nomeDaPlaca(placa)}: firmware ${firmware.texto}'
        '${firmware.atualizar ? ' — use "Atualizar firmware"' : ''}.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color:
              firmware.atualizar
                  ? AppTheme.brandOrange
                  : AppTheme.bodySoft,
        ),
      ),
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
    required List<String> placas,
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
      await widget.controller.sendMaintenanceCommand(action, placas);
    }
  }

  /// A rede própria tira a placa do ar por 3 minutos: pergunta qual.
  Future<void> _cadastrarWifi(BuildContext context) async {
    final List<String> placas = widget.controller.maintenanceBoards;
    String escolhida = placas.first;
    final bool? confirmado = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext dialogContext) => StatefulBuilder(
            builder:
                (BuildContext context, StateSetter marcar) => AlertDialog(
                  title: const Text('Cadastrar Wi-Fi na placa'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'A placa sai da rede atual e abre a rede "IoTMotor-" por 3 minutos.\n\n'
                        'Conecte o celular nessa rede e informe o Wi-Fi novo na página que abrir. '
                        'A senha vai direto para a placa, sem passar pelo broker público.',
                      ),
                      const SizedBox(height: 8),
                      RadioGroup<String>(
                        groupValue: escolhida,
                        onChanged: (String? placa) {
                          if (placa != null) marcar(() => escolhida = placa);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (final String placa in placas)
                              RadioListTile<String>(
                                key: ValueKey<String>('wifi_placa_$placa'),
                                value: placa,
                                title: Text(nomeDaPlaca(placa)),
                                contentPadding: EdgeInsets.zero,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
          ),
    );
    if (confirmado ?? false) {
      await widget.controller.sendMaintenanceCommand('wifi_portal', <String>[escolhida]);
    }
  }
}
