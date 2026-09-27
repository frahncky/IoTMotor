import 'dart:convert';

import '../models/board_alarm.dart';
import '../models/device_names.dart';

/// O que fazer com uma notificação do celular.
class AvisoDoCelular {
  const AvisoDoCelular({
    required this.id,
    required this.titulo,
    required this.texto,
    required this.comSom,
  });

  /// Um por alarme: o mesmo alarme atualiza a própria notificação.
  final int id;
  final String titulo;
  final String texto;

  /// Falso para atualizar sem tocar (voltou ao normal, ou disparou de novo
  /// logo depois de avisar).
  final bool comSom;
}

/// Decide quando o celular avisa, a partir do que as placas publicam.
///
/// Quem manda é a placa de sensores: ela avalia a lista de alarmes gravada
/// nela e publica em `alarms_firing` os que estão disparados agora (os mesmos
/// que acendem o LED e tocam o buzzer). Aqui só se compara com o que já foi
/// avisado:
/// - alarme que passou a disparar: notificação com som;
/// - alarme que voltou ao normal: a mesma notificação, sem som, dizendo isso;
/// - alarme que oscila em torno do limite: no máximo um som a cada
///   [intervaloEntreSons]; entre um e outro, só atualiza o texto.
///
/// Com o monitoramento da placa desligado (`alarm_enabled: false`) o celular
/// também fica quieto, como o buzzer.
class AlertasDaBancada {
  AlertasDaBancada({
    this.intervaloEntreSons = const Duration(minutes: 5),
    DateTime Function()? agora,
  }) : _agora = agora ?? DateTime.now;

  final Duration intervaloEntreSons;
  final DateTime Function() _agora;

  /// Lista de alarmes de cada placa (tópico retido `alarms`).
  final Map<String, Map<String, BoardAlarm>> _alarmesPorPlaca = <String, Map<String, BoardAlarm>>{};

  /// Disparados agora, por placa.
  final Map<String, Set<String>> _disparados = <String, Set<String>>{};

  /// Última leitura de cada grandeza, de qualquer placa (a corrente vem do
  /// quadro; a temperatura, dos sensores).
  final Map<String, double> _leituras = <String, double>{};

  /// Quando cada alarme tocou pela última vez.
  final Map<String, DateTime> _ultimoSom = <String, DateTime>{};

  /// Recebe uma mensagem MQTT e devolve os avisos a mostrar.
  List<AvisoDoCelular> receber(String topico, String payload) {
    final List<String> partes = topico.split('/');
    if (partes.length < 3) return const <AvisoDoCelular>[];
    final String tipo = partes.last;
    final String placa = partes[partes.length - 2];
    final Object? dados;
    try {
      dados = jsonDecode(payload);
    } catch (_) {
      return const <AvisoDoCelular>[];
    }
    if (dados is! Map<String, dynamic>) return const <AvisoDoCelular>[];
    if ((dados['device_id'] ?? placa) != placa) return const <AvisoDoCelular>[];

    if (tipo == 'alarms') {
      _alarmesPorPlaca[placa] = <String, BoardAlarm>{
        for (final BoardAlarm a in BoardAlarm.listFromPayload(payload)) a.id: a,
      };
      return const <AvisoDoCelular>[];
    }
    if (tipo != 'telemetry') return const <AvisoDoCelular>[];

    for (final MapEntry<String, dynamic> campo in dados.entries) {
      final Object? valor = campo.value;
      if (valor is num && valor.isFinite) _leituras[campo.key] = valor.toDouble();
    }

    final Object? lista = dados['alarms_firing'];
    if (lista is! List) return const <AvisoDoCelular>[];
    final bool monitorando = dados['alarm_enabled'] != false;
    final Set<String> agora = monitorando
        ? <String>{for (final Object? id in lista) if (id is String && id.isNotEmpty) id}
        : <String>{};
    final Set<String> antes = _disparados[placa] ?? <String>{};
    _disparados[placa] = agora;

    final List<AvisoDoCelular> avisos = <AvisoDoCelular>[];
    for (final String id in agora.difference(antes)) {
      avisos.add(_aviso(placa, id, disparou: true));
    }
    for (final String id in antes.difference(agora)) {
      avisos.add(_aviso(placa, id, disparou: false));
    }
    return avisos;
  }

  AvisoDoCelular _aviso(String placa, String id, {required bool disparou}) {
    final BoardAlarm? alarme = _alarmesPorPlaca[placa]?[id];
    final String oQue = alarme == null ? 'alarme "$id"' : _descricao(alarme);
    final String chave = '$placa/$id';
    if (!disparou) {
      return AvisoDoCelular(
        id: idDaNotificacao(chave),
        titulo: 'Normalizado: ${_maiuscula(oQue)}',
        texto: '${nomeDaPlaca(placa)} · voltou ao normal às ${_hora(_agora())}',
        comSom: false,
      );
    }
    final DateTime instante = _agora();
    final DateTime? ultimo = _ultimoSom[chave];
    final bool comSom = ultimo == null || instante.difference(ultimo) >= intervaloEntreSons;
    if (comSom) _ultimoSom[chave] = instante;
    final double? leitura = alarme == null ? null : _leituras[alarme.field];
    final AlarmQuantity? grandeza = alarme == null ? null : alarmQuantityFor(alarme.field);
    final String valor = leitura == null
        ? ''
        : ' · agora ${_numero(leitura)}${grandeza == null || grandeza.unit.isEmpty ? '' : ' ${grandeza.unit}'}';
    // Com desarme, a placa manda o quadro desligar o motor.
    final String desliga = alarme?.trip == true ? ' · desliga o motor' : '';
    return AvisoDoCelular(
      id: idDaNotificacao(chave),
      titulo: 'Alarme: ${_maiuscula(oQue)}',
      texto: '${nomeDaPlaca(placa)} · às ${_hora(instante)}$valor$desliga',
      comSom: comSom,
    );
  }

  /// "Temperatura acima de 60 °C", como se fala.
  static String _descricao(BoardAlarm alarme) {
    final AlarmQuantity? g = alarmQuantityFor(alarme.field);
    final String unidade = g == null || g.unit.isEmpty ? '' : ' ${g.unit}';
    return '${g?.label ?? alarme.field} ${alarme.above ? 'acima de' : 'abaixo de'} '
        '${_numero(alarme.limit)}$unidade';
  }

  /// Número estável por alarme (o Android usa inteiros de 31 bits).
  static int idDaNotificacao(String chave) {
    int h = 17;
    for (final int c in chave.codeUnits) {
      h = (h * 31 + c) & 0x3fffffff;
    }
    // Longe do id da notificação fixa do serviço.
    return 1000 + h % 1000000;
  }

  static String _maiuscula(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

  static String _hora(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 60 → "60"; 12,5 → "12,5"; 0,35 → "0,35".
  static String _numero(double v) {
    String texto = v.abs() >= 100
        ? v.toStringAsFixed(0)
        : v.abs() >= 10
            ? v.toStringAsFixed(1)
            : v.toStringAsFixed(2);
    if (texto.contains('.')) texto = texto.replaceFirst(RegExp(r'\.?0+$'), '');
    return texto.replaceAll('.', ',');
  }
}
