import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/board_alarm.dart';
import '../../models/device_names.dart';
import 'glass_panel.dart';

/// Lista de alarmes gravada na placa, a mesma que o painel web edita.
///
/// Quem decide acender o LED e tocar o buzzer é a placa: aqui o app só mostra
/// e altera o que está gravado nela. As grandezas elétricas vêm do quadro de
/// comando, que a placa de sensores escuta pelo broker.
class BoardAlarmsPanel extends StatelessWidget {
  const BoardAlarmsPanel({super.key, required this.controller});

  final MotorControlController controller;

  @override
  Widget build(BuildContext context) {
    final List<BoardAlarm> alarmes = controller.boardAlarms;
    final String? placa = controller.alarmsDeviceId;

    return GlassPanel(
      tint: AppTheme.brandMint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.rule_rounded, color: AppTheme.brandMint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Alarmes da placa',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Recarregar a lista da placa',
                onPressed: placa == null ? null : controller.requestBoardAlarms,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            placa == null
                ? 'Aguardando a lista de alarmes. Conecte ao broker; se a placa '
                    'estiver online e nada chegar, ela está com firmware antigo.'
                : '${alarmes.length} de ${controller.boardAlarmsMax} alarmes '
                    'gravados em ${nomeDaPlaca(placa)}. A placa acende o LED e '
                    'apita sozinha, mesmo com o app fechado.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (placa != null && alarmes.isEmpty)
            Text(
              'Nenhum alarme cadastrado: a placa não vai acender nem apitar.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          for (final BoardAlarm alarme in alarmes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AlarmTile(alarme: alarme, controller: controller),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed:
                  placa == null || alarmes.length >= controller.boardAlarmsMax
                      ? null
                      : () => _editar(context, controller, null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar alarme'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({required this.alarme, required this.controller});

  final BoardAlarm alarme;
  final MotorControlController controller;

  @override
  Widget build(BuildContext context) {
    final bool disparado = alarme.firing;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: disparado ? AppTheme.danger : Colors.white24,
          width: disparado ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  describeAlarm(alarme),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    alarme.fromCommandBoard
                        ? 'quadro de comando'
                        : 'sensores do motor',
                    if (!alarme.enabled) 'desligado',
                    if (disparado) 'DISPARADO',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: disparado ? AppTheme.danger : null,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: alarme.enabled,
            onChanged:
                (bool ligado) => controller.saveBoardAlarm(
                  alarme.copyWith(enabled: ligado),
                ),
          ),
          IconButton(
            tooltip: 'Editar o limite',
            onPressed: () => _editar(context, controller, alarme),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Remover',
            onPressed: () => _remover(context, controller, alarme),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

Future<void> _remover(
  BuildContext context,
  MotorControlController controller,
  BoardAlarm alarme,
) async {
  final bool? confirma = await showDialog<bool>(
    context: context,
    builder:
        (BuildContext dialogo) => AlertDialog(
          title: const Text('Remover alarme'),
          content: Text('Tirar "${describeAlarm(alarme)}" da placa?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogo).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogo).pop(true),
              child: const Text('Remover'),
            ),
          ],
        ),
  );
  if (confirma ?? false) await controller.removeBoardAlarm(alarme.id);
}

/// Cria ou edita um alarme. Com [alarme] nulo, o formulário abre em branco.
Future<void> _editar(
  BuildContext context,
  MotorControlController controller,
  BoardAlarm? alarme,
) async {
  String campo = alarme?.field ?? kAlarmQuantities.first.field;
  bool acima = alarme?.above ?? true;
  final TextEditingController limite = TextEditingController(
    text: alarme == null ? '' : '${alarme.limit}',
  );

  final BoardAlarm? resultado = await showDialog<BoardAlarm>(
    context: context,
    builder:
        (BuildContext dialogo) => StatefulBuilder(
          builder: (BuildContext dialogo, StateSetter redesenhar) {
            final AlarmQuantity grandeza = alarmQuantityFor(campo)!;
            return AlertDialog(
              title: Text(alarme == null ? 'Novo alarme' : 'Editar alarme'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: campo,
                    decoration: const InputDecoration(labelText: 'Grandeza'),
                    // A grandeza define de qual placa vem a leitura.
                    items:
                        kAlarmQuantities
                            .map(
                              (AlarmQuantity q) => DropdownMenuItem<String>(
                                value: q.field,
                                child: Text(q.labelWithUnit),
                              ),
                            )
                            .toList(),
                    onChanged:
                        alarme != null
                            ? null
                            : (String? valor) =>
                                redesenhar(() => campo = valor ?? campo),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<bool>(
                    initialValue: acima,
                    decoration: const InputDecoration(
                      labelText: 'Dispara quando estiver',
                    ),
                    items: const <DropdownMenuItem<bool>>[
                      DropdownMenuItem<bool>(
                        value: true,
                        child: Text('Acima do limite'),
                      ),
                      DropdownMenuItem<bool>(
                        value: false,
                        child: Text('Abaixo do limite'),
                      ),
                    ],
                    onChanged:
                        (bool? valor) =>
                            redesenhar(() => acima = valor ?? acima),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: limite,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Limite (${grandeza.unit})',
                      helperText:
                          'de ${grandeza.min} a ${grandeza.max} ${grandeza.unit}',
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogo).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final double? valor = double.tryParse(
                      limite.text.trim().replaceAll(',', '.'),
                    );
                    if (valor == null ||
                        valor < grandeza.min ||
                        valor > grandeza.max) {
                      ScaffoldMessenger.of(dialogo).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${grandeza.labelWithUnit}: informe de '
                            '${grandeza.min} a ${grandeza.max}.',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogo).pop(
                      BoardAlarm(
                        id: alarme?.id ?? controller.newAlarmId(campo),
                        field: campo,
                        fromCommandBoard: grandeza.fromCommandBoard,
                        above: acima,
                        limit: valor,
                        enabled: alarme?.enabled ?? true,
                      ),
                    );
                  },
                  child: const Text('Gravar na placa'),
                ),
              ],
            );
          },
        ),
  );

  limite.dispose();
  if (resultado != null) await controller.saveBoardAlarm(resultado);
}
