import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';

class ConfiguracoesTab extends StatelessWidget {
  const ConfiguracoesTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey<String>('tab_configuracoes'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DelayedReveal(
                delay: const Duration(milliseconds: 200),
                child: _buildConnectionPanel(context),
              ),
              const SizedBox(height: 12),
              DelayedReveal(
                delay: const Duration(milliseconds: 250),
                child: _buildTelemetryFormatPanel(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionPanel(BuildContext context) {
    return GlassPanel(
      tint: AppTheme.brandBlue,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double fieldWidth = _fieldWidthFor(constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Conex\u00e3o MQTT',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _textField(
                    width: fieldWidth,
                    label: 'Broker host',
                    controller: controller.brokerController,
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Porta',
                    controller: controller.portController,
                    keyboardType: TextInputType.number,
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Client ID',
                    controller: controller.clientIdController,
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Topic prefix',
                    controller: controller.topicPrefixController,
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Usu\u00e1rio (opcional)',
                    controller: controller.usernameController,
                  ),
                  _textField(
                    width: fieldWidth,
                    label: 'Senha (opcional)',
                    controller: controller.passwordController,
                    obscureText: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: AppTheme.brandBlue.withValues(alpha: 0.12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Switch(
                          value: controller.useTls,
                          onChanged: controller.setTls,
                        ),
                        Text(controller.useTls ? 'TLS ativo' : 'TLS inativo'),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed:
                        controller.isBusy
                            ? null
                            : (controller.isConnected
                                ? controller.disconnect
                                : controller.connect),
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
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: controller.clearHistory,
                icon: const Icon(Icons.auto_graph_rounded),
                label: const Text('Limpar hist\u00f3rico'),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: AppTheme.surfaceSoft.withValues(alpha: 0.94),
                  border: Border.all(
                    color: AppTheme.brandBlue.withValues(alpha: 0.36),
                  ),
                ),
                child: SelectableText(
                  'T\u00f3pico de comando: ${controller.commandTopic}\n'
                  'T\u00f3pico de telemetria: ${controller.telemetryTopic}\n'
                  'T\u00f3pico de status: ${controller.statusTopic}\n'
                  'T\u00f3pico de solicita\u00e7\u00e3o: ${controller.telemetryRequestTopic}\n'
                  'Dispositivos conectados: ${controller.connectedDeviceIds.isEmpty ? '--' : controller.connectedDeviceIds.join(', ')}\n'
                  'Dispositivos conhecidos: ${controller.knownDeviceIds.isEmpty ? '--' : controller.knownDeviceIds.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: AppTheme.inkSoft,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTelemetryFormatPanel(BuildContext context) {
    return GlassPanel(
      tint: AppTheme.brandOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Formato da Telemetria',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceSoft.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.brandOrange.withValues(alpha: 0.4),
              ),
            ),
            child: SelectableText(
              '{"voltage":220.4,"current":3.9,"vibration":0.12,"temperature":37.8}\n'
              'ou\n'
              '{"voltage":220.4}\n'
              '{"current":3.9}\n'
              '{"vibration":0.12}\n'
              '{"temperature":37.8}\n'
              'ou\n'
              '{"data":{"voltage":"220.4","current":"3.9","vibration":"0.12","temperature":"37.8"}}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: AppTheme.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required double width,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    bool obscureText = false,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onChanged: (_) => this.controller.refreshPreview(),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  double _fieldWidthFor(double availableWidth) {
    if (availableWidth >= 840) {
      return (availableWidth - 20) / 2;
    }
    if (availableWidth >= 560) {
      return (availableWidth - 20) / 2;
    }
    return availableWidth;
  }
}
