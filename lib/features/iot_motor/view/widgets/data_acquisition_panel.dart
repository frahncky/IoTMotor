import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/data_acquisition_config.dart';
import 'glass_panel.dart';

class DataAcquisitionPanel extends StatefulWidget {
  const DataAcquisitionPanel({
    super.key,
    required this.controller,
  });

  final MotorControlController controller;

  @override
  State<DataAcquisitionPanel> createState() => _DataAcquisitionPanelState();
}

class _DataAcquisitionPanelState extends State<DataAcquisitionPanel> {
  late DataAcquisitionConfig _draft;
  String _preset = 'custom';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.controller.dataAcquisitionConfig;
    _preset = _presetOf(_draft);
  }

  String _presetOf(DataAcquisitionConfig config) {
    if (config.signature == DataAcquisitionConfig.realtime.signature) {
      return 'realtime';
    }
    if (config.signature == DataAcquisitionConfig.monitoring.signature) {
      return 'monitoring';
    }
    if (config.signature == DataAcquisitionConfig.economic.signature) {
      return 'economic';
    }
    return 'custom';
  }

  String _durationLabel(int ms) {
    if (ms < 1000) return '${ms} ms';
    final double seconds = ms / 1000;
    if (seconds >= 60 && seconds % 60 == 0) {
      return '${(seconds / 60).round()} min';
    }
    return seconds == seconds.roundToDouble()
        ? '${seconds.round()} s'
        : '${seconds.toStringAsFixed(1)} s';
  }

  void _applyPreset(String? value) {
    if (value == null) return;
    setState(() {
      _preset = value;
      switch (value) {
        case 'realtime':
          _draft = DataAcquisitionConfig.realtime;
          break;
        case 'monitoring':
          _draft = DataAcquisitionConfig.monitoring;
          break;
        case 'economic':
          _draft = DataAcquisitionConfig.economic;
          break;
        default:
          break;
      }
    });
  }

  void _change(DataAcquisitionConfig next) {
    setState(() {
      _draft = next;
      _preset = _presetOf(next);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final bool ok = await widget.controller.applyDataAcquisitionConfig(_draft);
    if (!mounted) return;
    setState(() => _saving = false);
    final String? message = widget.controller.consumePendingMessage();
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } else if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuração enviada às duas placas.'),
        ),
      );
    }
  }

  Widget _select({
    required String label,
    required int value,
    required List<int> values,
    required ValueChanged<int> onChanged,
    String? helper,
  }) {
    final List<int> items = <int>{...values, value}.toList()..sort();
    return SizedBox(
      width: 250,
      child: DropdownButtonFormField<int>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
        ),
        items: <DropdownMenuItem<int>>[
          for (final int option in items)
            DropdownMenuItem<int>(
              value: option,
              child: Text(_durationLabel(option)),
            ),
        ],
        onChanged: (int? next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  Widget _fixedCard(String title, String value, String subtitle) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.brandBlue.withValues(alpha: 0.08),
        border: Border.all(
          color: AppTheme.brandBlue.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 5),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.brandMint,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool sync = widget.controller.dataAcquisitionSynchronized;
    final String? validation = _draft.validationMessage;

    return GlassPanel(
      tint: AppTheme.brandBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.monitor_heart_rounded, color: AppTheme.brandMint),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Aquisição e registro de dados',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'A mesma configuração é gravada nas placas e lida pelo app e pelo painel web.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Chip(
                avatar: Icon(
                  sync ? Icons.sync_rounded : Icons.sync_problem_rounded,
                  size: 18,
                ),
                label: Text(sync ? 'Sincronizado' : 'Aguardando sincronismo'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              value: _preset,
              decoration: const InputDecoration(labelText: 'Perfil de aquisição'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'realtime', child: Text('Tempo real')),
                DropdownMenuItem(value: 'monitoring', child: Text('Monitoramento')),
                DropdownMenuItem(value: 'economic', child: Text('Econômico')),
                DropdownMenuItem(value: 'custom', child: Text('Personalizado')),
              ],
              onChanged: _applyPreset,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Aquisição física',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _fixedCard(
                'MPU6050 · aquisição',
                '1000 Hz · fixo',
                'Protegido para preservar a banda e o cálculo de vibração.',
              ),
              _select(
                label: 'Janela RMS de vibração',
                value: _draft.vibrationWindowMs,
                values: const <int>[500, 1000, 2000],
                onChanged: (int value) => _change(
                  _draft.copyWith(vibrationWindowMs: value),
                ),
              ),
              _select(
                label: 'Leitura elétrica PZEM',
                value: _draft.pzemIntervalMs,
                values: const <int>[1000, 2000, 3000, 5000, 10000],
                onChanged: (int value) => _change(
                  _draft.copyWith(pzemIntervalMs: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Telemetria, visualização e armazenamento',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _select(
                label: 'Publicação MQTT',
                value: _draft.mqttIntervalMs,
                values: const <int>[1000, 2000, 5000, 10000, 30000, 60000],
                helper: 'Taxa com que as placas entregam telemetria.',
                onChanged: (int value) => _change(
                  _draft.copyWith(mqttIntervalMs: value),
                ),
              ),
              _select(
                label: 'Pontos dos gráficos',
                value: _draft.chartIntervalMs,
                values: const <int>[1000, 2000, 5000, 10000, 30000, 60000],
                helper: 'Nunca pode ser menor que a publicação MQTT.',
                onChanged: (int value) => _change(
                  _draft.copyWith(chartIntervalMs: value),
                ),
              ),
              _select(
                label: 'Registro de dados',
                value: _draft.recordIntervalMs,
                values: const <int>[
                  1000,
                  2000,
                  5000,
                  10000,
                  30000,
                  60000,
                  300000,
                  600000,
                ],
                helper: 'Intervalo entre pontos persistidos/CSV.',
                onChanged: (int value) => _change(
                  _draft.copyWith(recordIntervalMs: value),
                ),
              ),
              _fixedCard(
                'Histórico da placa',
                '1 s → 1 h → 7 dias',
                'Amostra local a cada 1 s, consolidação horária e retenção por 7 dias.',
              ),
            ],
          ),
          if (validation != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              validation,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _saving || validation != null ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(
                  _saving ? 'Sincronizando…' : 'Aplicar e sincronizar',
                ),
              ),
              OutlinedButton.icon(
                onPressed: widget.controller.isConnected
                    ? widget.controller.requestDataAcquisitionConfig
                    : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Ler das placas'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
