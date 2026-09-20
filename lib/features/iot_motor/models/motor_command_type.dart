/// Tempos de um contator dentro de uma partida, em milissegundos contados do
/// início. `offMs` em 0 significa que ele fica ligado até parar.
class ContactorTiming {
  const ContactorTiming({
    required this.use,
    required this.onMs,
    required this.offMs,
  });

  final bool use;
  final int onMs;
  final int offMs;

  Map<String, dynamic> toBoard() =>
      <String, dynamic>{'use': use, 'on': onMs, 'off': offMs};

  @override
  bool operator ==(Object other) =>
      other is ContactorTiming &&
      other.use == use &&
      other.onMs == onMs &&
      other.offMs == offMs;

  @override
  int get hashCode => Object.hash(use, onMs, offMs);
}

class MotorCommandType {
  const MotorCommandType({
    required this.id,
    required this.label,
    required this.command,
    required this.mode,
    required this.feedback,
    this.sequence = false,
    this.mask = 1,
    this.main = 1,
    this.star = 2,
    this.delta = 3,
    this.seconds = 5,
    this.timings,
  });

  final String id;
  final String label;
  final String command;
  final String mode;
  final String feedback;

  /// Perfil enviado ao ESP32 de comandos. Direta (`sequence == false`) liga
  /// ao mesmo tempo os contatores da máscara (bit 0 = CNT 1 ... bit 3 = CNT 4).
  /// Estrela-triângulo usa os contatores principal, estrela e triângulo
  /// (1 a 4, distintos) e fica `seconds` segundos em estrela.
  final bool sequence;
  final int mask;
  final int main;
  final int star;
  final int delta;
  final int seconds;

  /// Tempos por contator quando a partida vem da placa (fonte da verdade).
  final List<ContactorTiming>? timings;

  bool get isStop => command == 'stop';

  /// Perfil válido segundo as mesmas regras do firmware.
  bool get profileIsValid {
    if (!sequence) return mask >= 1 && mask <= 15;
    final bool faixa = <int>[main, star, delta].every((int c) => c >= 1 && c <= 4);
    return faixa &&
        main != star &&
        main != delta &&
        star != delta &&
        seconds >= 2 &&
        seconds <= 30;
  }

  /// Texto curto dos contatores, para listas e confirmações.
  String get profileSummary {
    final List<ContactorTiming>? tempos = timings;
    if (tempos != null) {
      final List<String> partes = <String>[
        for (int i = 0; i < tempos.length; i++)
          if (tempos[i].use)
            'CNT ${i + 1}: ${_segundos(tempos[i].onMs)}s'
                '${tempos[i].offMs == 0 ? ' até parar' : ' a ${_segundos(tempos[i].offMs)}s'}',
      ];
      return partes.isEmpty ? 'Nenhum contator marcado.' : partes.join(' · ');
    }
    if (!sequence) {
      final List<String> ligados = <String>[
        for (int i = 0; i < 4; i++)
          if (mask & (1 << i) != 0) 'CNT ${i + 1}',
      ];
      return 'Direta: ${ligados.join(' + ')}';
    }
    return 'Estrela-triângulo: principal CNT $main, estrela CNT $star, '
        'triângulo CNT $delta, $seconds s em estrela';
  }

  static const MotorCommandType stop = MotorCommandType(
    id: 'stop',
    label: 'Parada Manual',
    command: 'stop',
    mode: 'manual_stop',
    feedback: 'Comando enviado: parada do motor.',
  );

  static const MotorCommandType directStart = MotorCommandType(
    id: 'direct',
    label: 'Direta',
    command: 'start',
    mode: 'direct',
    feedback: 'Comando enviado: partida direta.',
  );

  static const MotorCommandType starDeltaStart = MotorCommandType(
    id: 'star_delta',
    label: 'Estrela-Triângulo',
    command: 'start',
    mode: 'star_delta',
    feedback: 'Comando enviado: partida estrela-triângulo.',
    sequence: true,
  );

  static String _segundos(int ms) {
    final double s = ms / 1000;
    return s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1);
  }

  /// Modos antigos de estrela-triângulo ("star_delta", "sequence", "estrela").
  /// Não basta conter "star": "soft_starter" é partida direta.
  static bool modeLooksLikeSequence(String mode) {
    return RegExp(r'star[_\- ]?delta|sequence|estrela').hasMatch(mode.toLowerCase());
  }

  /// Partida como está gravada no ESP32: cada contator com seus tempos.
  factory MotorCommandType.fromBoard({
    required String id,
    required String label,
    required List<ContactorTiming> timings,
  }) {
    return MotorCommandType(
      id: id,
      label: label,
      command: 'start',
      mode: id,
      feedback: 'Comando enviado: partida ${label.toLowerCase()}.',
      timings: timings,
    );
  }

  /// Contatores e tempos no formato que a placa grava e republica.
  List<Map<String, dynamic>> timingsToBoard() {
    final List<ContactorTiming> tempos = timings ?? _timingsFromLegacy();
    return tempos.map((ContactorTiming t) => t.toBoard()).toList(growable: false);
  }

  /// Converte os campos antigos (máscara ou estrela-triângulo) em tempos.
  List<ContactorTiming> _timingsFromLegacy() {
    const int atraso = 500, tempoMorto = 700;
    return List<ContactorTiming>.generate(4, (int i) {
      final int contator = i + 1;
      if (!sequence) {
        return ContactorTiming(
          use: mask & (1 << i) != 0,
          onMs: atraso,
          offMs: 0,
        );
      }
      if (contator == main) return const ContactorTiming(use: true, onMs: atraso, offMs: 0);
      if (contator == star) {
        return ContactorTiming(use: true, onMs: atraso, offMs: atraso + seconds * 1000);
      }
      if (contator == delta) {
        return ContactorTiming(
          use: true,
          onMs: atraso + seconds * 1000 + tempoMorto,
          offMs: 0,
        );
      }
      return const ContactorTiming(use: false, onMs: 0, offMs: 0);
    });
  }

  factory MotorCommandType.start({
    required String id,
    required String label,
    required String mode,
    bool? sequence,
    int mask = 1,
    int main = 1,
    int star = 2,
    int delta = 3,
    int seconds = 5,
  }) {
    return MotorCommandType(
      id: id,
      label: label,
      command: 'start',
      mode: mode,
      feedback: 'Comando enviado: partida ${label.toLowerCase()}.',
      sequence: sequence ?? modeLooksLikeSequence(mode),
      mask: mask,
      main: main,
      star: star,
      delta: delta,
      seconds: seconds,
    );
  }

  MotorCommandType copyAsStart({
    required String label,
    required String mode,
    bool? sequence,
    int? mask,
    int? main,
    int? star,
    int? delta,
    int? seconds,
  }) {
    return MotorCommandType(
      id: id,
      label: label,
      command: 'start',
      mode: mode,
      feedback: 'Comando enviado: partida ${label.toLowerCase()}.',
      sequence: sequence ?? this.sequence,
      mask: mask ?? this.mask,
      main: main ?? this.main,
      star: star ?? this.star,
      delta: delta ?? this.delta,
      seconds: seconds ?? this.seconds,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is MotorCommandType &&
        other.id == id &&
        other.command == command &&
        other.mode == mode &&
        other.label == label &&
        other.feedback == feedback &&
        other.sequence == sequence &&
        other.mask == mask &&
        other.main == main &&
        other.star == star &&
        other.delta == delta &&
        other.seconds == seconds;
  }

  @override
  int get hashCode => Object.hash(
    id,
    command,
    mode,
    label,
    feedback,
    sequence,
    mask,
    main,
    star,
    delta,
    seconds,
  );
}
