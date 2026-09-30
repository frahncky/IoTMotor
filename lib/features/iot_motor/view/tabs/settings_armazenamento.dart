part of 'settings_tab.dart';

/// Página Armazenamento: retenção do histórico no app e na placa.
extension _ConfiguracoesArmazenamento on _ConfiguracoesTabState {
  List<Widget> _buildStoragePage(BuildContext context) {
    return <Widget>[
      Form(
        key: _storageFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppSection(
              title: 'Neste celular',
              subtitle: controller.historyRetentionSummary,
              children: <Widget>[
                _retentionField(
                  label: 'Guardar por',
                  controllerField: _retentionController,
                  focusNode: _retentionFocusNode,
                  unit: _retentionUnit,
                  fieldLabel: 'a retenção local',
                  onSubmitted: _applyRetentionDays,
                ),
                _buildRetentionUnitSelector(
                  selected: _retentionUnit,
                  onChanged: _setRetentionUnit,
                ),
                const SizedBox(height: 12),
                AppButtons(
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _applyRetentionDays,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Aplicar'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          controller.historyEntryCount == 0
                              ? null
                              : controller.clearHistory,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Limpar histórico'),
                    ),
                  ],
                ),
              ],
            ),
            appSectionGap,
            AppSection(
              title: 'No cartão SD do ESP32',
              subtitle: controller.remoteHistoryRetentionSummary,
              children: <Widget>[
                _retentionField(
                  label: 'Guardar por',
                  controllerField: _remoteRetentionController,
                  focusNode: _remoteRetentionFocusNode,
                  unit: _remoteRetentionUnit,
                  fieldLabel: 'a retenção remota',
                  onSubmitted: _applyRemoteRetentionDays,
                ),
                _buildRetentionUnitSelector(
                  selected: _remoteRetentionUnit,
                  onChanged: _setRemoteRetentionUnit,
                ),
                const SizedBox(height: 12),
                AppButtons(
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _applyAndSendRemoteRetention,
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('Aplicar no ESP32'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _retentionField({
    required String label,
    required TextEditingController controllerField,
    required FocusNode focusNode,
    required _RetentionUnit unit,
    required String fieldLabel,
    required bool Function() onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controllerField,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: label,
          suffixText: _retentionUnitLabel(unit),
          hintText: 'Ex: 30',
        ),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator:
            (String? value) => MqttSettingsValidators.validateDecimal(
              value,
              fieldLabel: fieldLabel,
              min: 0,
              allowZero: false,
            ),
        onFieldSubmitted: (_) => onSubmitted(),
      ),
    );
  }

  Widget _buildRetentionUnitSelector({
    required _RetentionUnit selected,
    required ValueChanged<_RetentionUnit> onChanged,
  }) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<_RetentionUnit>(
        showSelectedIcon: false,
        selected: <_RetentionUnit>{selected},
        onSelectionChanged: (Set<_RetentionUnit> selection) {
          onChanged(selection.first);
        },
        segments: const <ButtonSegment<_RetentionUnit>>[
          ButtonSegment<_RetentionUnit>(
            value: _RetentionUnit.days,
            label: Text('Dias'),
          ),
          ButtonSegment<_RetentionUnit>(
            value: _RetentionUnit.months,
            label: Text('Meses'),
          ),
          ButtonSegment<_RetentionUnit>(
            value: _RetentionUnit.years,
            label: Text('Anos'),
          ),
        ],
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle?>(
            Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ),
    );
  }

  bool _applyRetentionDays() {
    if (!(_storageFormKey.currentState?.validate() ?? false)) {
      return false;
    }
    final int? amount = int.tryParse(_retentionController.text.trim());
    if (amount == null || amount <= 0) {
      _showSnackBar('Informe uma retenção local maior que zero.');
      return false;
    }
    _setRetentionAmount(amount);
    return true;
  }

  bool _applyRemoteRetentionDays() {
    if (!(_storageFormKey.currentState?.validate() ?? false)) {
      return false;
    }
    final int? amount = int.tryParse(_remoteRetentionController.text.trim());
    if (amount == null || amount <= 0) {
      _showSnackBar('Informe uma retenção remota maior que zero.');
      return false;
    }
    _setRemoteRetentionAmount(amount);
    return true;
  }

  Future<void> _applyAndSendRemoteRetention() async {
    if (!_applyRemoteRetentionDays()) {
      return;
    }
    await controller.applyRemoteHistoryRetention();
  }

  void _setRetentionAmount(int amount) {
    controller.setHistoryRetentionDays(
      _retentionDaysFromAmount(amount, _retentionUnit),
    );
    _retentionController.text =
        _displayAmountForDays(
          controller.historyRetentionDays,
          _retentionUnit,
        ).toString();
  }

  void _setRemoteRetentionAmount(int amount) {
    controller.setRemoteHistoryRetentionDays(
      _retentionDaysFromAmount(amount, _remoteRetentionUnit),
    );
    _remoteRetentionController.text =
        _displayAmountForDays(
          controller.remoteHistoryRetentionDays,
          _remoteRetentionUnit,
        ).toString();
  }

  void _setRetentionUnit(_RetentionUnit unit) {
    if (_retentionUnit == unit) {
      return;
    }
    _atualizar(() {
      _retentionUnit = unit;
      _retentionController.text =
          _displayAmountForDays(
            controller.historyRetentionDays,
            unit,
          ).toString();
    });
  }

  void _setRemoteRetentionUnit(_RetentionUnit unit) {
    if (_remoteRetentionUnit == unit) {
      return;
    }
    _atualizar(() {
      _remoteRetentionUnit = unit;
      _remoteRetentionController.text =
          _displayAmountForDays(
            controller.remoteHistoryRetentionDays,
            unit,
          ).toString();
    });
  }

  void _syncRetentionControllers({bool force = false}) {
    if (force || !_retentionFocusNode.hasFocus) {
      final String value =
          _displayAmountForDays(
            controller.historyRetentionDays,
            _retentionUnit,
          ).toString();
      if (_retentionController.text != value) {
        _retentionController.text = value;
      }
    }

    if (force || !_remoteRetentionFocusNode.hasFocus) {
      final String value =
          _displayAmountForDays(
            controller.remoteHistoryRetentionDays,
            _remoteRetentionUnit,
          ).toString();
      if (_remoteRetentionController.text != value) {
        _remoteRetentionController.text = value;
      }
    }
  }

  int _retentionDaysFromAmount(int amount, _RetentionUnit unit) {
    switch (unit) {
      case _RetentionUnit.days:
        return amount;
      case _RetentionUnit.months:
        return amount * 30;
      case _RetentionUnit.years:
        return amount * 365;
    }
  }

  int _displayAmountForDays(int days, _RetentionUnit unit) {
    switch (unit) {
      case _RetentionUnit.days:
        return days;
      case _RetentionUnit.months:
        return (days / 30).ceil().clamp(1, 3650);
      case _RetentionUnit.years:
        return (days / 365).ceil().clamp(1, 3650);
    }
  }

  String _retentionUnitLabel(_RetentionUnit unit) {
    switch (unit) {
      case _RetentionUnit.days:
        return 'dias';
      case _RetentionUnit.months:
        return 'meses';
      case _RetentionUnit.years:
        return 'anos';
    }
  }
}
