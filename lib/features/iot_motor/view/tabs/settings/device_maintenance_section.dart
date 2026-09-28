import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../app/theme/app_theme.dart';
import '../../../../../app/versao.dart';
import '../../../controller/motor_control_controller.dart';
import '../../../models/device_names.dart';
import '../../../services/app_update_service.dart';
import '../../widgets/app_section.dart';

/// Firmware das placas e atualização do app (Configurações > Placas).
class DeviceMaintenanceSection extends StatefulWidget {
  const DeviceMaintenanceSection({super.key, required this.controller});

  final MotorControlController controller;

  @override
  State<DeviceMaintenanceSection> createState() =>
      _DeviceMaintenanceSectionState();
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
    final List<String> placas =
        <String>{
            ...widget.controller.firmwareByDevice.keys,
            ...widget.controller.firmwareUpdateDeviceIds,
          }.toList()
          ..sort();
    final bool otaEmAndamento = widget.controller.firmwareUpdateDeviceIds.any(
      widget.controller.isFirmwareUpdating,
    );
    final bool temAtualizacao = widget.controller.boardsToUpdate.isNotEmpty;
    final Widget iconeFirmware =
        otaEmAndamento && !temAtualizacao
            ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
            : const Icon(Icons.system_update_alt_rounded);
    final Widget textoFirmware = Text(
      otaEmAndamento && !temAtualizacao
          ? 'Atualizando firmware…'
          : 'Atualizar firmware',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSection(
          title: 'Firmware das placas',
          children: <Widget>[
            if (placas.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Nenhuma placa informou a versão ainda.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            // Versão/estado OTA de cada placa. Durante o reboot da OTA,
            // mantém "Atualizando firmware…" em vez de "desconectado".
            for (final String placa in placas)
              _buildFirmwareLine(context, placa),
            const SizedBox(height: 8),
            AppButtons(
              children: <Widget>[
                // Nunca fica desabilitado: o toque informa por que a ação
                // não pode ser executada naquele instante. Em destaque só
                // quando há firmware novo para instalar.
                if (temAtualizacao)
                  FilledButton.icon(
                    onPressed: () => _acaoAtualizarFirmware(context),
                    icon: iconeFirmware,
                    label: textoFirmware,
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _acaoAtualizarFirmware(context),
                    icon: iconeFirmware,
                    label: textoFirmware,
                  ),
                OutlinedButton.icon(
                  onPressed: () => _acaoCadastrarWifi(context),
                  icon: const Icon(Icons.wifi_password_rounded),
                  label: const Text('Cadastrar Wi-Fi'),
                ),
              ],
            ),
          ],
        ),
        appSectionGap,
        AppSection(
          title: 'Este app',
          children: <Widget>[
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder:
                  (BuildContext context, AsyncSnapshot<PackageInfo> pacote) =>
                      AppInfoRow(
                        label: 'Versão ${pacote.data?.version ?? '…'}',
                        value: nomeDaVersao,
                      ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              // Continua clicável durante a verificação; um novo toque apenas
              // informa que a checagem já está em andamento.
              onPressed: _acaoAtualizarApp,
              icon:
                  _verificandoAppUpdate
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.phone_android_rounded),
              label: Text(
                _verificandoAppUpdate ? 'Verificando…' : 'Atualizar este app',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _acaoCadastrarWifi(BuildContext context) async {
    if (!widget.controller.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conecte ao MQTT para cadastrar uma rede Wi-Fi.'),
        ),
      );
      return;
    }
    if (widget.controller.maintenanceBoards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma placa compatível está conectada agora.'),
        ),
      );
      return;
    }
    await _cadastrarWifi(context);
  }

  Future<void> _acaoAtualizarApp() async {
    if (_verificandoAppUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A verificação de atualização já está em andamento.'),
        ),
      );
      return;
    }
    await _verificarAtualizacaoDoApp();
  }

  Future<void> _acaoAtualizarFirmware(BuildContext context) async {
    if (!widget.controller.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conecte ao MQTT para atualizar o firmware.'),
        ),
      );
      return;
    }

    final List<String> atualizando = widget.controller.firmwareUpdateDeviceIds
        .where(widget.controller.isFirmwareUpdating)
        .toList(growable: false);
    final List<String> alvos = widget.controller.boardsToUpdate;

    if (alvos.isEmpty) {
      final String mensagem =
          atualizando.isNotEmpty
              ? 'Atualização em andamento: ${atualizando.map(nomeDaPlaca).join(' e ')}.'
              : widget.controller.maintenanceBoards.isEmpty
              ? 'Nenhuma placa está conectada agora.'
              : 'O firmware das placas conectadas já está atualizado.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensagem)));
      return;
    }

    await _confirmarManutencao(
      context,
      action: 'update',
      placas: alvos,
      titulo: 'Atualizar firmware',
      texto:
          'Vai atualizar: ${alvos.map(nomeDaPlaca).join(' e ')}.\n\n'
          'Cada placa baixa o firmware publicado no GitHub e reinicia '
          '(cerca de 1 minuto fora do ar). O quadro de comando só aceita '
          'com o motor parado.',
    );
  }

  Widget _buildFirmwareLine(BuildContext context, String placa) {
    final TextTheme texto = Theme.of(context).textTheme;
    final String? ota = widget.controller.firmwareUpdateLabel(placa);
    final ({String texto, bool atualizar})? firmware = widget.controller
        .firmwareOf(placa);
    if (ota == null && firmware == null) return const SizedBox.shrink();

    final bool concluida =
        ota != null && widget.controller.firmwareUpdateSucceeded(placa);
    final bool atencao = ota != null ? !concluida : firmware!.atualizar;
    final Color cor = atencao ? AppTheme.brandOrange : AppTheme.brandMint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            atencao ? Icons.system_update_alt_rounded : Icons.check_circle,
            size: 20,
            color: cor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  nomeDaPlaca(placa),
                  style: texto.bodyLarge?.copyWith(color: AppTheme.ink),
                ),
                if (ota != null)
                  Text(
                    ota,
                    key: ValueKey<String>('firmware_update_$placa'),
                    style: texto.bodySmall?.copyWith(color: cor),
                  )
                else
                  Text(
                    firmware!.texto,
                    style: texto.bodySmall?.copyWith(
                      color: firmware.atualizar ? cor : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
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
      await widget.controller.sendMaintenanceCommand('wifi_portal', <String>[
        escolhida,
      ]);
    }
  }
}
