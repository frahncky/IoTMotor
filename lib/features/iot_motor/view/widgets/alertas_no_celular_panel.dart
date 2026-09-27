import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/mqtt_connection_config.dart';
import '../../services/alertas_no_celular.dart';
import 'glass_panel.dart';

/// Chave dos alertas no celular (Configurações).
///
/// Desligada por padrão: ligada, o Android mostra uma notificação fixa
/// enquanto o app vigia os alarmes da placa, mesmo fechado.
class AlertasNoCelularPanel extends StatefulWidget {
  const AlertasNoCelularPanel({super.key, required this.controller});

  final MotorControlController controller;

  @override
  State<AlertasNoCelularPanel> createState() => _AlertasNoCelularPanelState();
}

class _AlertasNoCelularPanelState extends State<AlertasNoCelularPanel> {
  bool _ligado = false;
  bool _ocupado = false;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    AlertasNoCelular.ligado().then((bool ligado) {
      if (mounted) setState(() => _ligado = ligado);
    });
  }

  Future<void> _alternar(bool ligar) async {
    setState(() {
      _ocupado = true;
      _aviso = null;
    });
    String? erro;
    if (ligar) {
      final MqttConnectionConfig? config = widget.controller.configuracaoParaAlertas();
      erro = config == null
          ? 'Configure a conexão MQTT acima antes de ligar os alertas.'
          : await AlertasNoCelular.ligar(config);
    } else {
      await AlertasNoCelular.desligar();
    }
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _aviso = erro;
      if (erro == null) _ligado = ligar;
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    return GlassPanel(
      tint: AppTheme.brandOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.notifications_active_rounded, color: AppTheme.brandOrange),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Alertas no celular', style: texto.titleMedium),
                    Text(
                      'Avisa quando um alarme da placa dispara, mesmo com o app fechado.',
                      style: texto.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey<String>('alertas_no_celular_switch'),
                value: _ligado,
                onChanged: !AlertasNoCelular.suportado || _ocupado ? null : _alternar,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            !AlertasNoCelular.suportado
                ? 'Disponível só no Android.'
                : _ligado
                    ? 'Ligados. O Android mostra uma notificação fixa enquanto o app vigia; '
                        'os alarmes chegam com som e somem quando voltam ao normal.'
                    : 'Usa os alarmes gravados na placa de sensores (os mesmos do LED e do '
                        'buzzer). Ligados, o Android mantém uma notificação fixa e o app usa '
                        'um pouco de bateria e dados.',
            style: texto.bodySmall?.copyWith(color: AppTheme.bodySoft),
          ),
          if (_aviso != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(_aviso!, style: texto.bodySmall?.copyWith(color: AppTheme.danger)),
          ],
        ],
      ),
    );
  }
}
