part of 'settings_tab.dart';

/// Página Aquisição: intervalos gravados no ESP32-01 e predefinições.
extension _ConfiguracoesAquisicao on _ConfiguracoesTabState {
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
                _atualizar(() {
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
}
