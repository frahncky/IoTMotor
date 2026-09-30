part of 'inicio_tab.dart';

/// Painel de comando da aba Início: partida escolhida, ligar/desligar e editor.
extension _InicioPartida on _InicioTabState {
  Widget _buildCommandPanel(
    BuildContext context, {
    required List<MotorCommandType> startTypes,
    required MotorCommandType selectedStartType,
  }) {
    final bool connected = widget.controller.isConnected;
    final bool canSend =
        connected &&
        widget.controller.hasLiveMotorState &&
        (widget.controller.isBenchMotorOn ||
            widget.controller.hasValidBenchVoltage) &&
        !widget.controller.isBusy;
    final bool motorOn = widget.controller.isBenchMotorOn;
    // Seletor e botão na mesma altura, com o rótulo "Partida" dentro do
    // seletor: o painel ocupava ~110 px e agora ~66, que sobram para os
    // gráficos.
    const double controlHeight = 46;

    return SizedBox(
      width: double.infinity,
      child: GlassPanel(
        tint: AppTheme.brandBlue,
        padding: const EdgeInsets.all(10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: SizedBox(
                    height: controlHeight,
                    child: _buildStartTypeSelector(
                      context,
                      startTypes: startTypes,
                      selectedStartType: selectedStartType,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                height: controlHeight,
                child: FilledButton.icon(
                  onPressed:
                      canSend
                          ? () {
                            if (motorOn) {
                              widget.controller.sendCommand(
                                MotorCommandType.stop,
                              );
                            } else {
                              widget.controller.sendCommand(selectedStartType);
                            }
                          }
                          : null,
                  icon: Icon(
                    motorOn
                        ? Icons.power_off_rounded
                        : Icons.power_settings_new_rounded,
                  ),
                  label: Text(motorOn ? 'Desligar' : 'Ligar'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        motorOn ? AppTheme.danger : AppTheme.online,
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: (motorOn ? AppTheme.danger : AppTheme.online)
                          .withValues(alpha: 0.92),
                    ),
                    shadowColor: (motorOn ? AppTheme.danger : AppTheme.online)
                        .withValues(alpha: 0.45),
                    elevation: 2,
                    minimumSize: Size(0, controlHeight),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  MotorCommandType _resolveSelectedStartType(
    List<MotorCommandType> startTypes,
  ) {
    if (startTypes.isEmpty) {
      return MotorCommandType.directStart;
    }

    final String? selectedId = _selectedStartTypeId;
    if (selectedId != null) {
      for (final MotorCommandType type in startTypes) {
        if (type.id == selectedId) {
          return type;
        }
      }
    }
    return startTypes.first;
  }

  void _syncSelectedTypeFromDevice(MotorCommandType? detectedType) {
    if (detectedType == null) {
      return;
    }
    if (_selectedStartTypeId == detectedType.id) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _atualizar(() {
        _selectedStartTypeId = detectedType.id;
      });
    });
  }

  Widget _buildStartTypeSelector(
    BuildContext context, {
    required List<MotorCommandType> startTypes,
    required MotorCommandType selectedStartType,
  }) {
    return PopupMenuButton<String>(
      onSelected: (String action) {
        _atualizar(() {
          _selectedStartTypeId = action;
        });
      },
      itemBuilder: (BuildContext menuContext) {
        final List<PopupMenuEntry<String>> items = <PopupMenuEntry<String>>[
          ...startTypes.map(
            (MotorCommandType type) => PopupMenuItem<String>(
              value: type.id,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () {
                  Navigator.of(menuContext).pop();
                  Future<void>.delayed(Duration.zero, () {
                    if (!mounted) {
                      return;
                    }
                    _openStartTypeActions(context: this.context, type: type);
                  });
                },
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            type.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Contatores que esta partida aciona.
                          Text(
                            type.profileSummary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (type.id == selectedStartType.id)
                      Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: AppTheme.brandBlue,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            enabled: false,
            value: _InicioTabState._addStartTypeAction,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Navigator.of(menuContext).pop();
                Future<void>.delayed(Duration.zero, () {
                  if (!mounted) {
                    return;
                  }
                  _openStartTypeEditor(context: this.context);
                });
              },
              child: const Row(
                children: <Widget>[
                  Icon(Icons.add_circle_outline_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Adicionar partida'),
                ],
              ),
            ),
          ),
        ];
        return items;
      },
      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSoft.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.brandBlue.withValues(alpha: 0.34)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.list_alt_rounded, size: 18, color: AppTheme.brandBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Partida',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.inkSoft,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    selectedStartType.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.ink,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: AppTheme.brandBlue),
          ],
        ),
      ),
    );
  }

  Future<void> _openStartTypeActions({
    required BuildContext context,
    required MotorCommandType type,
  }) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext actionContext) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('Editar "${type.label}"'),
                onTap: () => Navigator.of(actionContext).pop('edit'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppTheme.danger),
                title: Text(
                  'Excluir "${type.label}"',
                  style: TextStyle(color: AppTheme.danger),
                ),
                onTap: () => Navigator.of(actionContext).pop('delete'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (action == 'edit') {
      await _openStartTypeEditor(context: this.context, initial: type);
      return;
    }

    if (action != 'delete') {
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: this.context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Excluir partida'),
          content: Text('Deseja excluir "${type.label}"?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    final bool removed = widget.controller.removeStartType(type.id);
    if (!removed || !mounted || _selectedStartTypeId != type.id) {
      return;
    }

    final List<MotorCommandType> remaining = widget.controller.startTypes;
    _atualizar(() {
      _selectedStartTypeId = remaining.isEmpty ? null : remaining.first.id;
    });
  }

  /// Editor de partidas: cada contator com o instante em que liga e em que
  /// desliga. A partida é gravada no ESP32, então vale também no painel.
  Future<void> _openStartTypeEditor({
    required BuildContext context,
    MotorCommandType? initial,
  }) async {
    String label = initial?.label ?? '';
    final List<ContactorTiming> tempos = List<ContactorTiming>.generate(4, (
      int i,
    ) {
      final List<ContactorTiming>? atuais = initial?.timings;
      if (atuais != null && i < atuais.length) return atuais[i];
      return ContactorTiming(use: i == 0, onMs: 500, offMs: 0);
    });

    String? problema() {
      if (label.trim().isEmpty) return 'Informe o nome da partida.';
      if (!tempos.any((ContactorTiming t) => t.use))
        return 'Marque pelo menos um contator.';
      for (int i = 0; i < tempos.length; i++) {
        final ContactorTiming t = tempos[i];
        if (!t.use) continue;
        if (t.offMs != 0 && t.offMs <= t.onMs) {
          return 'CNT ${i + 1}: desligar depois de ligar (ou 0 para ficar ligado).';
        }
      }
      return null;
    }

    Widget campoDeTempo(String rotulo, int valorMs, ValueChanged<int> aoMudar) {
      return SizedBox(
        width: 104,
        child: TextFormField(
          initialValue: (valorMs / 1000).toString(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: rotulo, suffixText: 's'),
          onChanged: (String texto) {
            final double? s = double.tryParse(texto.replaceAll(',', '.'));
            if (s != null && s >= 0 && s <= 300) aoMudar((s * 1000).round());
          },
        ),
      );
    }

    final bool? salvar = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter atualizar) {
            final String? erro = problema();
            return AlertDialog(
              title: Text(initial == null ? 'Nova partida' : 'Editar partida'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextFormField(
                        initialValue: label,
                        autofocus: initial == null,
                        // A placa guarda 24 bytes, e cada acento ocupa dois.
                        maxLength: 24,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        validator: (String? valor) {
                          final String nome = (valor ?? '').trim();
                          if (nome.isEmpty) return 'Informe o nome da partida.';
                          final int bytes = utf8.encode(nome).length;
                          return bytes > 24
                              ? 'Nome comprido para a placa ($bytes de 24; '
                                  'cada acento conta dois).'
                              : null;
                        },
                        onChanged:
                            (String value) => atualizar(() => label = value),
                        decoration: const InputDecoration(
                          labelText: 'Nome da partida',
                          hintText: 'Ex.: Estrela-triângulo 8 s',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tempos contados do início da partida. Desligar em 0 = '
                        'o contator fica ligado até você parar.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      for (int i = 0; i < 4; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: <Widget>[
                              SizedBox(
                                width: 112,
                                child: CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: Text('CNT ${i + 1}'),
                                  value: tempos[i].use,
                                  onChanged:
                                      (bool? marcado) => atualizar(() {
                                        tempos[i] = ContactorTiming(
                                          use: marcado ?? false,
                                          onMs: tempos[i].onMs,
                                          offMs: tempos[i].offMs,
                                        );
                                      }),
                                ),
                              ),
                              const SizedBox(width: 6),
                              campoDeTempo(
                                'Liga',
                                tempos[i].onMs,
                                (int ms) => atualizar(() {
                                  tempos[i] = ContactorTiming(
                                    use: tempos[i].use,
                                    onMs: ms,
                                    offMs: tempos[i].offMs,
                                  );
                                }),
                              ),
                              const SizedBox(width: 10),
                              campoDeTempo(
                                'Desliga',
                                tempos[i].offMs,
                                (int ms) => atualizar(() {
                                  tempos[i] = ContactorTiming(
                                    use: tempos[i].use,
                                    onMs: tempos[i].onMs,
                                    offMs: ms,
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      if (erro != null)
                        Text(
                          erro,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed:
                      erro == null
                          ? () => Navigator.of(dialogContext).pop(true)
                          : null,
                  child: const Text('Salvar na placa'),
                ),
              ],
            );
          },
        );
      },
    );

    if (salvar != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.saveStartTypeOnBoard(
        id: initial?.id ?? '',
        label: label,
        timings: tempos,
      );
    });
  }
}
