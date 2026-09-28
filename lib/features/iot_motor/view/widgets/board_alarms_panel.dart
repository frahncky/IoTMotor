import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../controller/motor_control_controller.dart';
import '../../models/board_alarm.dart';
import 'app_section.dart';

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

    return AppSection(
      title: 'Alarmes da placa',
      subtitle:
          placa == null
              ? 'Aguardando a placa enviar a lista.'
              : '${alarmes.length} de ${controller.boardAlarmsMax} · funcionam com o app fechado',
      trailing: IconButton(
        tooltip: 'Recarregar a lista da placa',
        onPressed: placa == null ? null : controller.requestBoardAlarms,
        icon: const Icon(Icons.refresh_rounded),
      ),
      children: <Widget>[
        if (placa != null && alarmes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Nenhum alarme cadastrado.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        for (final BoardAlarm alarme in alarmes)
          _AlarmTile(alarme: alarme, controller: controller),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed:
              placa == null || alarmes.length >= controller.boardAlarmsMax
                  ? null
                  : () => _editar(context, controller, null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Adicionar alarme'),
        ),
      ],
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
    final TextTheme texto = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _editar(context, controller, alarme),
      onLongPress: () => _remover(context, controller, alarme),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(
              disparado
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: disparado ? AppTheme.danger : AppTheme.inkSoft,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    describeAlarm(alarme),
                    style: texto.bodyLarge?.copyWith(color: AppTheme.ink),
                  ),
                  Text(
                    <String>[
                      if (disparado) 'Disparado',
                      if (alarme.trip) 'Desliga o motor',
                      if (!alarme.enabled) 'Pausado',
                      if (!disparado && !alarme.trip && alarme.enabled)
                        alarme.fromCommandBoard
                            ? 'Quadro de comando'
                            : 'Sensores',
                    ].join(' · '),
                    style: texto.bodySmall?.copyWith(
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
          ],
        ),
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
  bool desarma = alarme?.trip ?? false;
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
                  const SizedBox(height: 4),
                  // Desarme: desligado por padrão, escolhido por alarme.
                  SwitchListTile(
                    key: const ValueKey<String>('alarme_desarme'),
                    contentPadding: EdgeInsets.zero,
                    value: desarma,
                    onChanged:
                        (bool valor) => redesenhar(() => desarma = valor),
                    title: const Text('Desligar o motor'),
                    subtitle: const Text(
                      'Com o motor ligado, disparar faz o quadro desligar o motor. '
                      'Precisa das placas conectadas ao broker.',
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                if (alarme != null)
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogo).pop();
                      _remover(context, controller, alarme);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                    ),
                    child: const Text('Remover'),
                  ),
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
                        trip: desarma,
                      ),
                    );
                  },
                  child: const Text('Gravar'),
                ),
              ],
            );
          },
        ),
  );

  limite.dispose();
  if (resultado != null) await controller.saveBoardAlarm(resultado);
}
