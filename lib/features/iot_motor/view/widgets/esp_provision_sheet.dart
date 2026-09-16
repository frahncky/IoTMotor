import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/esp_local_comm_provider.dart';
import '../../models/esp_local_status.dart';

/// Provisionamento do modulo pela rede local.
///
/// Fala com as rotas `/health`, `/wifi-networks` e `/provision` do firmware.
/// Gravar exige a chave que tambem protege a atualizacao — e a mesma do
/// `OTA_KEY` compilado no sketch, ou a que tiver sido trocada por aqui.
class EspProvisionSheet extends ConsumerStatefulWidget {
  const EspProvisionSheet({super.key, required this.espHost});

  final String espHost;

  /// Abre a folha e devolve a mensagem de sucesso, ou null se foi fechada.
  static Future<String?> show(
    BuildContext context, {
    required String espHost,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) => EspProvisionSheet(espHost: espHost),
    );
  }

  @override
  ConsumerState<EspProvisionSheet> createState() => _EspProvisionSheetState();
}

class _EspProvisionSheetState extends ConsumerState<EspProvisionSheet> {
  final _formKey = GlobalKey<FormState>();

  final _otaKeyController = TextEditingController();
  final _ssidController = TextEditingController();
  final _wifiPasswordController = TextEditingController();
  final _mqttHostController = TextEditingController();
  final _mqttPortController = TextEditingController(text: '1883');
  final _mqttUserController = TextEditingController();
  final _mqttPasswordController = TextEditingController();
  final _topicPrefixController = TextEditingController();
  final _newOtaKeyController = TextEditingController();

  bool _useTls = false;
  bool _carregando = false;
  bool _escaneando = false;
  bool _aplicando = false;
  String? _erro;
  EspHealth? _health;
  EspProvisionConfig? _config;
  List<EspWifiNetwork> _redes = const <EspWifiNetwork>[];

  @override
  void dispose() {
    _otaKeyController.dispose();
    _ssidController.dispose();
    _wifiPasswordController.dispose();
    _mqttHostController.dispose();
    _mqttPortController.dispose();
    _mqttUserController.dispose();
    _mqttPasswordController.dispose();
    _topicPrefixController.dispose();
    _newOtaKeyController.dispose();
    super.dispose();
  }

  EspLocalCommService get _servico => ref.read(espLocalCommProvider);

  void _definirErro(Object erro) {
    setState(() {
      _erro =
          erro is EspLocalCommException
              ? erro.message
              : 'Falha ao falar com o modulo: $erro';
    });
  }

  Future<void> _carregarConfiguracao() async {
    final String chave = _otaKeyController.text.trim();
    if (chave.isEmpty) {
      setState(() => _erro = 'Informe a chave de acesso do modulo.');
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      // O /health e aberto e da o contexto (qual modulo, que versao roda);
      // o /provision exige a chave e traz o que preencher no formulario.
      final EspHealth health = await _servico.fetchHealth(
        espHost: widget.espHost,
      );
      final EspProvisionConfig config = await _servico.fetchProvision(
        espHost: widget.espHost,
        otaKey: chave,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _health = health;
        _config = config;
        _ssidController.text = config.ssid;
        _mqttHostController.text = config.mqttHost;
        _mqttPortController.text = '${config.mqttPort}';
        _mqttUserController.text = config.mqttUser;
        _topicPrefixController.text = config.topicPrefix;
        _useTls = config.useTls;
        // As senhas nunca vem do modulo: ficam em branco e so sao enviadas
        // quando o operador digita algo.
        _wifiPasswordController.clear();
        _mqttPasswordController.clear();
      });
    } catch (erro) {
      if (mounted) {
        _definirErro(erro);
      }
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  Future<void> _buscarRedes() async {
    setState(() {
      _escaneando = true;
      _erro = null;
    });

    try {
      final List<EspWifiNetwork> redes = await _servico.fetchWifiNetworks(
        espHost: widget.espHost,
      );
      if (mounted) {
        setState(() => _redes = redes);
      }
    } catch (erro) {
      if (mounted) {
        _definirErro(erro);
      }
    } finally {
      if (mounted) {
        setState(() => _escaneando = false);
      }
    }
  }

  Future<void> _aplicar() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final bool confirmado = await _confirmar(
      titulo: 'Gravar provisionamento?',
      texto:
          'O modulo grava as credenciais e reinicia. Se os dados estiverem '
          'errados, ele nao volta para a rede e sera preciso usar o ponto de '
          'acesso de emergencia.',
      acao: 'Gravar e reiniciar',
    );
    if (!confirmado) {
      return;
    }

    setState(() {
      _aplicando = true;
      _erro = null;
    });

    try {
      final String mensagem = await _servico.applyProvision(
        espHost: widget.espHost,
        otaKey: _otaKeyController.text.trim(),
        ssid: _ssidController.text.trim(),
        wifiPassword: _wifiPasswordController.text,
        mqttHost: _mqttHostController.text.trim(),
        mqttPort: int.tryParse(_mqttPortController.text.trim()) ?? 1883,
        mqttUser: _mqttUserController.text.trim(),
        mqttPassword: _mqttPasswordController.text,
        topicPrefix: _topicPrefixController.text.trim(),
        useTls: _useTls,
        newOtaKey: _newOtaKeyController.text,
      );
      if (mounted) {
        Navigator.of(context).pop(mensagem);
      }
    } catch (erro) {
      if (mounted) {
        _definirErro(erro);
      }
    } finally {
      if (mounted) {
        setState(() => _aplicando = false);
      }
    }
  }

  Future<void> _restaurarPadroes() async {
    final bool confirmado = await _confirmar(
      titulo: 'Restaurar padroes de fabrica?',
      texto:
          'Apaga o provisionamento gravado. O modulo volta a usar o Wi-Fi e o '
          'broker compilados no firmware e reinicia.',
      acao: 'Restaurar',
      destrutivo: true,
    );
    if (!confirmado) {
      return;
    }

    setState(() {
      _aplicando = true;
      _erro = null;
    });

    try {
      final String mensagem = await _servico.resetProvision(
        espHost: widget.espHost,
        otaKey: _otaKeyController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop(mensagem);
      }
    } catch (erro) {
      if (mounted) {
        _definirErro(erro);
      }
    } finally {
      if (mounted) {
        setState(() => _aplicando = false);
      }
    }
  }

  Future<bool> _confirmar({
    required String titulo,
    required String texto,
    required String acao,
    bool destrutivo = false,
  }) async {
    final bool? resposta = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(titulo),
          content: Text(texto),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style:
                  destrutivo
                      ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                      : null,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(acao),
            ),
          ],
        );
      },
    );
    return resposta ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData tema = Theme.of(context);
    final bool ocupado = _carregando || _aplicando;
    final bool carregou = _config != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        // Levanta o conteudo acima do teclado.
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Provisionar modulo', style: tema.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Rede local: ${widget.espHost}',
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _otaKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Chave de acesso do modulo',
                  helperText: 'A mesma OTA_KEY compilada no firmware',
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: ocupado ? null : _carregarConfiguracao,
                icon:
                    _carregando
                        ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.download_rounded),
                label: Text(
                  _carregando ? 'Lendo...' : 'Ler configuracao atual',
                ),
              ),

              if (_erro != null) ...<Widget>[
                const SizedBox(height: 12),
                _Aviso(texto: _erro!, cor: tema.colorScheme.error),
              ],

              if (_health != null) ...<Widget>[
                const SizedBox(height: 12),
                _ResumoDoModulo(health: _health!, config: _config),
              ],

              if (carregou) ...<Widget>[
                const Divider(height: 32),
                Text('Rede Wi-Fi', style: tema.textTheme.titleMedium),
                const SizedBox(height: 10),

                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _ssidController,
                        decoration: const InputDecoration(labelText: 'SSID'),
                        validator:
                            (String? v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Informe a rede'
                                    : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _escaneando ? null : _buscarRedes,
                      tooltip: 'Buscar redes',
                      icon:
                          _escaneando
                              ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.wifi_find_rounded),
                    ),
                  ],
                ),

                if (_redes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        _redes.map((EspWifiNetwork rede) {
                          return ActionChip(
                            avatar: Icon(
                              rede.secure
                                  ? Icons.lock_rounded
                                  : Icons.lock_open_rounded,
                              size: 16,
                            ),
                            label: Text('${rede.ssid}  ${rede.rssi} dBm'),
                            onPressed:
                                () => setState(
                                  () => _ssidController.text = rede.ssid,
                                ),
                          );
                        }).toList(),
                  ),
                ],

                const SizedBox(height: 12),
                TextFormField(
                  controller: _wifiPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Senha do Wi-Fi',
                    helperText:
                        _config?.hasWifiPassword == true
                            ? 'Ha uma senha gravada; deixe em branco para apaga-la'
                            : 'Deixe em branco para rede aberta',
                  ),
                ),

                const Divider(height: 32),
                Text('Broker MQTT', style: tema.textTheme.titleMedium),
                const SizedBox(height: 10),

                TextFormField(
                  controller: _mqttHostController,
                  decoration: const InputDecoration(labelText: 'Host'),
                  validator:
                      (String? v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Informe o broker'
                              : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mqttPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Porta'),
                  validator: (String? v) {
                    final int? porta = int.tryParse((v ?? '').trim());
                    if (porta == null || porta < 1 || porta > 65535) {
                      return 'Porta entre 1 e 65535';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mqttUserController,
                  decoration: const InputDecoration(
                    labelText: 'Usuario (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mqttPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Senha (opcional)',
                    helperText:
                        _config?.hasMqttPassword == true
                            ? 'Ha uma senha gravada; deixe em branco para apaga-la'
                            : null,
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  value: _useTls,
                  onChanged: (bool v) => setState(() => _useTls = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('MQTT sobre TLS'),
                  subtitle: const Text(
                    'Use com um broker autenticado; a porta costuma ser 8883',
                  ),
                ),

                const Divider(height: 32),
                TextFormField(
                  controller: _topicPrefixController,
                  decoration: const InputDecoration(
                    labelText: 'Prefixo de topicos',
                    helperText:
                        'Num broker publico, um prefixo dificil de adivinhar '
                        'reduz a chance de alguem comandar o motor',
                  ),
                  validator:
                      (String? v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Informe o prefixo'
                              : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newOtaKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Nova chave de acesso (opcional)',
                    helperText: 'Minimo de 8 caracteres. Em branco, mantem a atual',
                  ),
                  validator: (String? v) {
                    final String texto = v ?? '';
                    if (texto.isNotEmpty && texto.length < 8) {
                      return 'Minimo de 8 caracteres';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _aplicando ? null : _aplicar,
                  icon:
                      _aplicando
                          ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.save_rounded),
                  label: Text(
                    _aplicando ? 'Gravando...' : 'Gravar e reiniciar',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _aplicando ? null : _restaurarPadroes,
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: const Text('Restaurar padroes de fabrica'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, required this.cor});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        border: Border.all(color: cor.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, color: cor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cor),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumoDoModulo extends StatelessWidget {
  const _ResumoDoModulo({required this.health, this.config});

  final EspHealth health;
  final EspProvisionConfig? config;

  @override
  Widget build(BuildContext context) {
    final ThemeData tema = Theme.of(context);
    final String papel = switch (health.role) {
      'actuator' => 'acionamento',
      'sensor' => 'sensores',
      _ => 'modulo',
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${health.deviceId} · $papel · firmware ${health.firmwareVersion}',
            style: tema.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(
            config?.provisioned == true
                ? 'Usando provisionamento gravado.'
                : 'Usando os padroes compilados no firmware.',
            style: tema.textTheme.bodySmall,
          ),
          if (health.fallbackAp)
            Text(
              'Ponto de acesso de emergencia ativo.',
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}
