import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../widgets/delayed_reveal.dart';
import '../widgets/glass_panel.dart';

class HistoricoTab extends StatelessWidget {
  const HistoricoTab({super.key, required this.controller});

  final MotorControlController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey<String>('tab_historico'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DelayedReveal(
                delay: const Duration(milliseconds: 200),
                child: _buildConnectionDataPanel(context),
              ),
              const SizedBox(height: 12),
              DelayedReveal(
                delay: const Duration(milliseconds: 250),
                child: _buildConnectionTypePanel(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionDataPanel(BuildContext context) {
    final bool connected = controller.isConnected;
    final Color stateColor = connected ? AppTheme.online : AppTheme.offline;
    final String deviceId = controller.selectedDeviceId;
    final String devicesList =
        controller.knownDeviceIds.isEmpty ? '--' : controller.knownDeviceIds.join(', ');

    return GlassPanel(
      tint: AppTheme.brandMint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Dados de Conexão',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              Chip(
                avatar: Icon(Icons.circle, size: 12, color: stateColor),
                label: Text(connected ? 'Online' : 'Offline'),
              ),
              Chip(
                avatar: const Icon(Icons.lan_rounded, size: 16),
                label: Text(controller.connectionProtocol),
              ),
              Chip(
                avatar: const Icon(Icons.memory_rounded, size: 16),
                label: Text('Device $deviceId'),
              ),
              Chip(
                avatar: const Icon(Icons.hub_rounded, size: 16),
                label: Text('ESPs ${controller.knownDeviceCount}'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _dataLine(context, 'Host', controller.connectionHost),
          _dataLine(context, 'Porta', controller.connectionPort),
          _dataLine(context, 'Client ID', controller.connectionClientId),
          _dataLine(context, 'Dispositivos vistos', devicesList),
          _dataLine(context, 'Tópico comando', controller.commandTopic),
          _dataLine(context, 'Tópico telemetria', controller.telemetryTopic),
          _dataLine(context, 'Tópico status', controller.statusTopic),
        ],
      ),
    );
  }

  Widget _buildConnectionTypePanel(BuildContext context) {
    return GlassPanel(
      tint: AppTheme.brandBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Tipo de Ligação',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          _dataLine(
            context,
            'Última ligação enviada',
            controller.lastConnectionType,
          ),
          _dataLine(context, 'Horário', controller.lastConnectionTime),
        ],
      ),
    );
  }

  Widget _dataLine(BuildContext context, String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.surfaceSoft.withValues(alpha: 0.92),
        border: Border.all(
          color: AppTheme.inputBorder.withValues(alpha: 0.6),
        ),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: <InlineSpan>[
            TextSpan(
              text: '$label: ',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            TextSpan(text: value.isEmpty ? '--' : value),
          ],
        ),
      ),
    );
  }
}

