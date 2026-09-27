import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/device_names.dart';
import '../../models/motor_info.dart';

/// Uso do motor, como no painel: carga, vibração pela ISO 10816, horímetro e
/// partidas, manutenção e aviso de firmware novo. Fica dentro do cartão do
/// motor, para sobrar altura para os gráficos. Some quando não há nada.
class MotorUsageStrip extends StatelessWidget {
  const MotorUsageStrip({super.key, required this.controller});

  final MotorControlController controller;

  @override
  Widget build(BuildContext context) {
    final MotorInfo? info = controller.motorInfo;
    final bool ligado = controller.isMotorRunning;
    final List<_Item> itens = <_Item>[];

    final int? carga = ligado ? motorLoad(controller.benchCurrent, info?.currentInUse) : null;
    if (carga != null) {
      itens.add(_Item(Icons.speed_rounded, 'Carga $carga%', carga > 100 ? AppTheme.danger : null));
    }
    // Vibração em mm/s RMS medida pela placa, com a zona ISO 10816.
    final VibrationSeverity? iso =
        ligado ? VibrationSeverity.zone(controller.sensorVibration, info?.powerCv) : null;
    if (iso != null) {
      itens.add(_Item(
        Icons.vibration_rounded,
        'Vibração ${iso.mmS.toStringAsFixed(2).replaceAll('.', ',')} mm/s RMS · ${iso.label}',
        iso.zona >= 2 ? (iso.zona == 3 ? AppTheme.danger : AppTheme.brandOrange) : null,
      ));
    }
    final MotorUsage? uso = controller.motorUsage;
    if (uso != null) {
      final String linha = usageLine(uso);
      if (linha.isNotEmpty) itens.add(_Item(Icons.timer_outlined, linha, null));
    }
    final MaintenanceStatus? manutencao = controller.maintenanceStatus;
    if (manutencao != null && (manutencao.vencida || manutencao.perto)) {
      itens.add(_Item(
        Icons.build_circle_outlined,
        manutencao.texto,
        manutencao.vencida ? AppTheme.danger : AppTheme.brandOrange,
      ));
    }
    for (final String placa in controller.firmwareByDevice.keys) {
      final ({String texto, bool atualizar})? firmware = controller.firmwareOf(placa);
      if (firmware != null && firmware.atualizar) {
        itens.add(_Item(
          Icons.system_update_alt_rounded,
          '${nomeDaPlaca(placa)}: firmware ${firmware.texto}. Atualize em Configurações.',
          AppTheme.brandOrange,
        ));
      }
    }
    if (itens.isEmpty) return const SizedBox.shrink();

    final TextStyle? estilo = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        key: const ValueKey<String>('motor_usage_strip'),
        spacing: 14,
        runSpacing: 4,
        children: <Widget>[
          for (final _Item item in itens)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(item.icone, size: 15, color: item.cor ?? AppTheme.labelSoft),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    item.texto,
                    style: estilo?.copyWith(color: item.cor ?? AppTheme.bodySoft),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Item {
  const _Item(this.icone, this.texto, this.cor);

  final IconData icone;
  final String texto;
  final Color? cor;
}
