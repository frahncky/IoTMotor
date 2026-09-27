import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../app/providers/motor_sound_provider.dart';
import '../../../../../app/theme/app_theme.dart';
import '../../../controller/motor_control_controller.dart';
import '../../../models/device_names.dart';
import '../../../models/motor_info.dart';
import '../../widgets/glass_panel.dart';
import 'settings_common.dart';

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
          buildPanelTitle(
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
            buildInlineNotice(
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
            buildInlineNotice(
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

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }}
