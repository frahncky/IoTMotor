class MotorCommandType {
  const MotorCommandType({
    required this.id,
    required this.label,
    required this.command,
    required this.mode,
    required this.feedback,
  });

  final String id;
  final String label;
  final String command;
  final String mode;
  final String feedback;

  bool get isStop => command == 'stop';

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
  );

  factory MotorCommandType.start({
    required String id,
    required String label,
    required String mode,
  }) {
    return MotorCommandType(
      id: id,
      label: label,
      command: 'start',
      mode: mode,
      feedback: 'Comando enviado: partida ${label.toLowerCase()}.',
    );
  }

  MotorCommandType copyAsStart({required String label, required String mode}) {
    return MotorCommandType(
      id: id,
      label: label,
      command: 'start',
      mode: mode,
      feedback: 'Comando enviado: partida ${label.toLowerCase()}.',
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
        other.feedback == feedback;
  }

  @override
  int get hashCode => Object.hash(id, command, mode, label, feedback);
}
