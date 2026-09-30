import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../app/providers/motor_animation_provider.dart';
import '../../../../../app/providers/motor_sound_provider.dart';
import '../../../../../app/theme/app_theme.dart';
import '../../../controller/motor_control_controller.dart';
import '../../../models/device_names.dart';
import '../../../models/motor_info.dart';
import '../../../services/motor_animation_prefs.dart';
import '../../widgets/app_section.dart';

/// Aba "Motor" das configurações: dados de placa, som e ações do motor.
class MotorSettingsPanel extends ConsumerStatefulWidget {
  const MotorSettingsPanel({super.key, required this.controller});

  final MotorControlController controller;

  @override
  ConsumerState<MotorSettingsPanel> createState() => _MotorSettingsPanelState();
}

class _MotorSettingsPanelState extends ConsumerState<MotorSettingsPanel> {
  MotorControlController get controller => widget.controller;

  @override
  Widget build(BuildContext context) => _buildMotorPanel(context);

  Widget _buildMotorPanel(BuildContext context) {
    final MotorInfo? info = controller.motorInfo;
    final MotorUsage? uso = controller.motorUsage;
    final MaintenanceStatus? manutencao = controller.maintenanceStatus;
    final bool disponivel =
        controller.isConnected && controller.motorDeviceId != null;
    final sound = ref.watch(motorSoundServiceProvider);
    final MotorAnimationPrefs animacao = ref.watch(motorAnimationPrefsProvider);
    final MotorAnimationEffects efeitos = animacao.efeitos;
    final TextTheme texto = Theme.of(context).textTheme;

    final List<Widget> dados = <Widget>[];
    void linha(String rotulo, String valor) {
      dados.add(AppInfoRow(label: rotulo, value: valor));
    }

    if (info != null) {
      if (info.currentA != null) {
        linha('Corrente', '${_motorPair(info.currentA, info.currentYA)} A');
      }
      if (info.voltageV != null) {
        linha('Tensão', '${_motorPair(info.voltageV, info.voltageYV)} V');
      }
      if (info.powerCv != null)
        linha('Potência', '${_motorNumber(info.powerCv)} cv');
      if (info.rpm != null)
        linha('Rotação', '${_motorNumber(info.rpm, casas: 0)} rpm');
      if (info.serviceFactor != null)
        linha('Fator de serviço', _motorNumber(info.serviceFactor));
      if (info.phases != null)
        linha('Tipo', info.phases == 3 ? 'Trifásico' : 'Monofásico');
      if (info.connectionLabel != null) linha('Ligação', info.connectionLabel!);
      if (info.maintIntervalH != null && info.maintIntervalH! > 0) {
        linha(
          'Manutenção',
          'a cada ${_motorNumber(info.maintIntervalH, casas: 0)} h',
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSection(
          title: 'Dados de placa',
          subtitle:
              controller.motorDeviceId == null
                  ? null
                  : 'Gravados em ${nomeDaPlaca(controller.motorDeviceId!)}',
          children: <Widget>[
            if (dados.isEmpty)
              Text(
                controller.isConnected
                    ? 'Nenhum dado cadastrado para este motor.'
                    : 'Conecte ao broker para ler os dados gravados no quadro.',
                style: texto.bodyMedium,
              )
            else
              ...dados,
            const SizedBox(height: 12),
            AppButtons(
              children: <Widget>[
                FilledButton.icon(
                  onPressed: disponivel ? () => _editMotorInfo(context) : null,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Editar dados do motor'),
                ),
              ],
            ),
          ],
        ),
        appSectionGap,
        AppSection(
          title: 'Uso e manutenção',
          children: <Widget>[
            Text(
              uso == null ? 'Sem leitura do horímetro ainda.' : usageLine(uso),
              style: texto.bodyMedium,
            ),
            if (manutencao != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                manutencao.texto,
                style: texto.bodyMedium?.copyWith(
                  color: manutencao.vencida ? AppTheme.brandOrange : null,
                  fontWeight: manutencao.vencida ? FontWeight.w700 : null,
                ),
              ),
            ],
            const SizedBox(height: 12),
            AppButtons(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed:
                      disponivel
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
                TextButton.icon(
                  onPressed:
                      disponivel && !controller.isMotorRunning
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
          ],
        ),
        appSectionGap,
        AppSection(
          title: 'Perda de conex\u00e3o',
          subtitle: 'Comportamento gravado no quadro de comando.',
          children: <Widget>[
            Text(
              _linkLossSummary(controller.linkGraceSeconds),
              style: texto.bodyMedium,
            ),
            const SizedBox(height: 12),
            AppButtons(
              children: <Widget>[
                FilledButton.icon(
                  onPressed:
                      controller.hasLiveMotorState
                          ? () => _editLinkLossBehavior(context)
                          : null,
                  icon: const Icon(Icons.wifi_off_rounded),
                  label: const Text('Configurar perda de conex\u00e3o'),
                ),
              ],
            ),
          ],
        ),
        appSectionGap,
        AppSection(
          title: 'Som do motor',
          subtitle: 'Acompanha o estado confirmado do motor.',
          trailing: Switch(
            value: sound.enabled,
            onChanged: (bool value) {
              sound.setEnabled(value);
            },
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.volume_down_rounded, size: 20),
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
                  width: 42,
                  child: Text(
                    '${sound.volumePercent}%',
                    textAlign: TextAlign.end,
                    style: texto.labelMedium,
                  ),
                ),
              ],
            ),
            if (sound.lastError != null)
              Text(
                sound.lastError!,
                style: texto.bodySmall?.copyWith(color: AppTheme.danger),
              ),
            AppButtons(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed:
                      controller.isMotorRunning
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
              ],
            ),
          ],
        ),
        appSectionGap,
        AppSection(
          title: 'Animação do motor',
          subtitle:
              'Efeitos do desenho na tela Início, só neste aparelho. '
              '"Reduzir movimento" do sistema continua valendo.',
          children: <Widget>[
            SwitchListTile(
              key: const ValueKey<String>('anim_giro'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Girar'),
              subtitle: const Text('Partida, regime e parada por inércia'),
              value: efeitos.giro,
              onChanged: (bool v) => animacao.set(efeitos.copyWith(giro: v)),
            ),
            SwitchListTile(
              key: const ValueKey<String>('anim_tremor'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Tremer com a vibração'),
              subtitle: const Text('Nas zonas Alerta e Crítica'),
              value: efeitos.tremor,
              onChanged: (bool v) => animacao.set(efeitos.copyWith(tremor: v)),
            ),
            SwitchListTile(
              key: const ValueKey<String>('anim_calor'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Cor da temperatura'),
              subtitle: const Text('A carcaça esquenta perto do limite'),
              value: efeitos.calor,
              onChanged: (bool v) => animacao.set(efeitos.copyWith(calor: v)),
            ),
            SwitchListTile(
              key: const ValueKey<String>('anim_alarme'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Piscar nos alarmes'),
              value: efeitos.alarme,
              onChanged: (bool v) => animacao.set(efeitos.copyWith(alarme: v)),
            ),
          ],
        ),
      ],
    );
  }

  String _linkLossSummary(int? seconds) {
    if (seconds == null) {
      return 'Aguardando o quadro informar a configura\u00e7\u00e3o atual.';
    }
    if (seconds < 0) {
      return 'Manter o motor ligado se a conex\u00e3o cair, respeitando a '
          'dura\u00e7\u00e3o m\u00e1xima do ensaio e as prote\u00e7\u00f5es.';
    }
    if (seconds == 0) return 'Desligar imediatamente se a conex\u00e3o cair.';
    return 'Desligar ap\u00f3s $seconds segundos sem conex\u00e3o.';
  }

  Future<void> _editLinkLossBehavior(BuildContext context) async {
    final int atual = controller.linkGraceSeconds ?? 10;
    final TextEditingController espera = TextEditingController(
      text: atual >= 0 ? '$atual' : '10',
    );
    String comportamento = atual < 0 ? 'keep' : 'stop';
    String erro = '';

    final int? seconds = await showDialog<int>(
      context: context,
      builder:
          (BuildContext dialogContext) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              void salvar() {
                if (comportamento == 'keep') {
                  Navigator.of(dialogContext).pop(-1);
                  return;
                }
                final int? valor = int.tryParse(espera.text.trim());
                if (valor == null || valor < 0 || valor > 3600) {
                  setDialogState(() => erro = 'Informe de 0 a 3600 segundos.');
                  return;
                }
                Navigator.of(dialogContext).pop(valor);
              }

              return AlertDialog(
                title: const Text('Se a conex\u00e3o cair'),
                content: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      DropdownButtonFormField<String>(
                        initialValue: comportamento,
                        decoration: const InputDecoration(
                          labelText: 'Decis\u00e3o do quadro',
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                            value: 'stop',
                            child: Text('Desligar o motor'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'keep',
                            child: Text('Manter o motor ligado'),
                          ),
                        ],
                        onChanged: (String? value) {
                          setDialogState(() {
                            comportamento = value ?? 'stop';
                            erro = '';
                          });
                        },
                      ),
                      if (comportamento == 'stop') ...<Widget>[
                        const SizedBox(height: 12),
                        TextField(
                          controller: espera,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Espera antes de desligar (segundos)',
                            helperText: 'Use 0 para desligar imediatamente.',
                          ),
                        ),
                      ] else ...<Widget>[
                        const SizedBox(height: 12),
                        const Text(
                          'O motor continuar\u00e1 ligado sem rede, mas o limite do '
                          'ensaio e as prote\u00e7\u00f5es continuam valendo.',
                        ),
                      ],
                      if (erro.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(erro, style: TextStyle(color: AppTheme.danger)),
                      ],
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(onPressed: salvar, child: const Text('Gravar')),
                ],
              );
            },
          ),
    );
    espera.dispose();
    if (seconds == null || !mounted) return;
    final bool ok = await controller.saveLinkGraceSeconds(seconds);
    if (ok && mounted) {
      _showSnackBar('Configura\u00e7\u00e3o enviada ao quadro.');
    }
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
      final String faixa =
          max.isFinite
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
      text:
          atual?.serviceFactor == null
              ? ''
              : _motorNumber(atual!.serviceFactor),
    );
    final TextEditingController manutencao = TextEditingController(
      text:
          atual?.maintIntervalH == null
              ? ''
              : _motorNumber(atual!.maintIntervalH, casas: 0),
    );
    int fases = atual?.phases ?? 0;
    String ligacao = atual?.star == true ? 'star' : 'delta';
    String erro = '';

    final Map<String, dynamic>? dados = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            void salvar() {
              try {
                final List<double> correntes = _parseMotorPair(
                  corrente.text,
                  'Corrente',
                );
                final List<double> tensoes = _parseMotorPair(
                  tensao.text,
                  'Tensão',
                );
                final bool dupla = correntes.length == 2 || tensoes.length == 2;

                if (dupla && (correntes.length != 2 || tensoes.length != 2)) {
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
                            setDialogState(() => ligacao = value ?? 'delta');
                          },
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: potencia,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Potência (cv)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: rpm,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Rotação (rpm)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: fs,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
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
                        Text(erro, style: TextStyle(color: AppTheme.danger)),
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

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
