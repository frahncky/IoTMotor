import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../services/mqtt_path_check.dart';

/// Testa os caminhos até o broker e mostra cada um assim que responde.
///
/// A janela abre com a lista inteira em "testando…" e vai preenchendo: sem
/// isso, quem toca no botão fica 20 s olhando uma tela parada, sem saber se
/// algo está acontecendo.
class ConnectionPathDialog extends StatefulWidget {
  const ConnectionPathDialog({super.key, required this.broker});

  final String broker;

  /// Devolve o caminho escolhido, ou `null` se ninguém aplicou nada.
  static Future<MqttPathCandidate?> mostrar(
    BuildContext context,
    String broker,
  ) {
    return showDialog<MqttPathCandidate>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) => ConnectionPathDialog(broker: broker),
    );
  }

  @override
  State<ConnectionPathDialog> createState() => _ConnectionPathDialogState();
}

class _ConnectionPathDialogState extends State<ConnectionPathDialog> {
  late final List<MqttPathCandidate> _candidatos = caminhosConhecidos(
    widget.broker,
  );
  final Map<String, MqttPathResult> _resultados = <String, MqttPathResult>{};
  int _emTeste = 0;
  bool _cancelado = false;

  @override
  void initState() {
    super.initState();
    _rodar();
  }

  @override
  void dispose() {
    _cancelado = true;
    super.dispose();
  }

  Future<void> _rodar() async {
    for (int i = 0; i < _candidatos.length; i++) {
      if (_cancelado) return;
      setState(() => _emTeste = i);
      final MqttPathResult resultado = await verificarCaminho(_candidatos[i]);
      if (_cancelado || !mounted) return;
      setState(() => _resultados[_candidatos[i].label] = resultado);
    }
    if (mounted) setState(() => _emTeste = _candidatos.length);
  }

  MqttPathResult? get _primeiroQueFuncionou {
    for (final MqttPathCandidate c in _candidatos) {
      final MqttPathResult? r = _resultados[c.label];
      if (r != null && r.ok) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bool terminou = _emTeste >= _candidatos.length;
    final MqttPathResult? bom = _primeiroQueFuncionou;

    return AlertDialog(
      title: const Text('Caminhos até o broker'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_candidatos.isEmpty)
              const Text('Informe o broker antes de testar.'),
            for (int i = 0; i < _candidatos.length; i++)
              _linha(
                context,
                _candidatos[i],
                _resultados[_candidatos[i].label],
                testando: i == _emTeste && !terminou,
              ),
            if (terminou && bom == null && _candidatos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Nenhum caminho passou. Tente pelos dados do celular: se lá '
                  'funcionar, é a rede daqui que bloqueia.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(terminou ? 'Fechar' : 'Cancelar'),
        ),
        if (bom != null)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(bom.candidate),
            child: const Text('Usar este caminho'),
          ),
      ],
    );
  }

  Widget _linha(
    BuildContext context,
    MqttPathCandidate candidato,
    MqttPathResult? resultado, {
    required bool testando,
  }) {
    final Widget marca;
    if (testando) {
      marca = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (resultado == null) {
      marca = const Icon(Icons.schedule_rounded, size: 18);
    } else {
      marca = Icon(
        resultado.ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
        size: 18,
        color: resultado.ok ? AppTheme.online : AppTheme.danger,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 20, child: Center(child: marca)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(candidato.label),
                Text(
                  testando ? 'testando…' : resultado?.detail ?? 'na fila',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
