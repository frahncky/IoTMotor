import 'package:flutter/material.dart';
import '../../../../../app/theme/app_theme.dart';
import '../../../controller/motor_control_controller.dart';
import '../../../services/mqtt_settings_validators.dart';
import 'settings_common.dart';

/// Limites que o próprio app confere nas leituras recebidas. Os alarmes que
/// valem de verdade ficam gravados na placa (aba Alertas); estes só geram
/// avisos no app.
class AlertSettingsPanel extends StatefulWidget {
  const AlertSettingsPanel({super.key, required this.controller});

  final MotorControlController controller;

  @override
  State<AlertSettingsPanel> createState() => _AlertSettingsPanelState();
}

class _AlertSettingsPanelState extends State<AlertSettingsPanel> {
  MotorControlController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final String? thresholdError = controller.alertThresholdsError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Avisar pelos limites do app'),
          value: controller.telemetryAlertsEnabled,
          onChanged: controller.setTelemetryAlertsEnabled,
        ),
        const SizedBox(height: 8),
        _campo('Tensão mínima', controller.voltageMinController, 'V', 'a tensão mínima'),
        _campo('Tensão máxima', controller.voltageMaxController, 'V', 'a tensão máxima'),
        _campo('Corrente máxima', controller.currentMaxController, 'A', 'o limite de corrente'),
        _campo('Vibração máxima', controller.vibrationMaxController, 'mm/s', 'o limite de vibração'),
        _campo('Temperatura máxima', controller.temperatureMaxController, '°C', 'o limite de temperatura'),
        if (thresholdError != null)
          Text(
            thresholdError,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.danger),
          ),
      ],
    );
  }

  Widget _campo(
    String label,
    TextEditingController campo,
    String unidade,
    String nomeNoErro,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: settingsTextField(
        width: double.infinity,
        label: label,
        controllerField: campo,
        keyboardType: TextInputType.number,
        suffixText: unidade,
        validator:
            (String? value) => MqttSettingsValidators.validateDecimal(
              value,
              fieldLabel: nomeNoErro,
              min: 0,
              allowZero: false,
            ),
        onChanged: () {
          setState(() {});
          controller.refreshPreview();
        },
      ),
    );
  }
}
