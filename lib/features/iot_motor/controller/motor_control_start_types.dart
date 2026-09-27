part of 'motor_control_controller.dart';

/// Partidas (perfis de acionamento): lista local, lista da placa e edição.
extension MotorControlStartTypes on MotorControlController {
  MotorCommandType? startTypeById(String id) {
    for (final MotorCommandType type in _startTypes) {
      if (type.id == id) {
        return type;
      }
    }
    return null;
  }

  /// Lê a lista publicada pelo ESP32 e substitui a lista mostrada no app.
  ///
  /// O formato é o mesmo do painel: cada contator tem o instante em que liga e
  /// o instante em que desliga (0 = fica ligado até parar), em milissegundos.
  void _aplicarPerfisDaPlaca({required String deviceId, required String payload}) {
    final Object? dados;
    try {
      dados = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (dados is! Map<String, dynamic>) return;
    final Object? lista = dados['profiles'];
    if (lista is! List) return;

    final List<MotorCommandType> partidas = <MotorCommandType>[];
    for (final Object? bruto in lista) {
      if (bruto is! Map) continue;
      final String id = '${bruto['id'] ?? ''}'.trim();
      final String nome = '${bruto['name'] ?? ''}'.trim();
      final Object? contatores = bruto['cnt'];
      if (id.isEmpty || nome.isEmpty || contatores is! List || contatores.length != 4) continue;
      final List<ContactorTiming> tempos = <ContactorTiming>[];
      for (final Object? item in contatores) {
        if (item is! Map) break;
        tempos.add(ContactorTiming(
          use: item['use'] == true,
          onMs: (item['on'] as num?)?.round() ?? 0,
          offMs: (item['off'] as num?)?.round() ?? 0,
        ));
      }
      if (tempos.length != 4) continue;
      partidas.add(MotorCommandType.fromBoard(id: id, label: nome, timings: tempos));
    }
    if (partidas.isEmpty) return;

    _perfisDeviceId = deviceId;
    startTypesFromBoard = true;
    _startTypes
      ..clear()
      ..addAll(partidas);
    _notify();
  }

  void _tratarRespostaDeComando(String payload) {
    if (_ultimoComandoDePerfil == null) return;
    final Object? dados;
    try {
      dados = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (dados is! Map<String, dynamic>) return;
    if ('${dados['seq'] ?? ''}' != _ultimoComandoDePerfil) return;
    _ultimoComandoDePerfil = null;
    final String detalhe = '${dados['reason'] ?? dados['action'] ?? ''}';
    _pendingMessage = dados['accepted'] == true
        ? 'Placa confirmou: $detalhe'
        : 'Placa recusou: $detalhe';
    _notify();
  }

  /// Envia a partida para a placa, que grava e republica para todos.
  bool _enviarPerfilParaPlaca(String action, Map<String, dynamic> corpo) {
    final String? dev = _perfisDeviceId ?? _benchDeviceId;
    if (dev == null) {
      _pendingMessage = 'Aguardando a lista de partidas do ESP32 de comandos.';
      _notify();
      return false;
    }
    final String? seq = _service.sendRawCommand(deviceId: dev, action: action, body: corpo);
    if (seq == null) {
      _pendingMessage = 'Conecte-se ao broker antes de editar partidas.';
      _notify();
      return false;
    }
    _ultimoComandoDePerfil = seq;
    return true;
  }

  /// Cria ou atualiza uma partida na placa; ela grava e republica para todos.
  ///
  /// `id` vazio cria uma partida nova. Os tempos são os mesmos do painel:
  /// para cada contator, quando liga e quando desliga (0 = até parar).
  bool saveStartTypeOnBoard({
    required String id,
    required String label,
    required List<ContactorTiming> timings,
  }) {
    final String nome = _normalizeLabel(label);
    if (nome.isEmpty) {
      _pendingMessage = 'Informe o nome da partida.';
      _notify();
      return false;
    }
    if (!timings.any((ContactorTiming t) => t.use)) {
      _pendingMessage = 'Marque pelo menos um contator.';
      _notify();
      return false;
    }
    for (int i = 0; i < timings.length; i++) {
      final ContactorTiming t = timings[i];
      if (!t.use) continue;
      if (t.onMs < 0 || t.offMs < 0 || (t.offMs != 0 && t.offMs <= t.onMs)) {
        _pendingMessage = 'CNT ${i + 1}: desligar depois de ligar (ou 0 para ficar ligado).';
        _notify();
        return false;
      }
    }
    final String identificador = id.isNotEmpty
        ? id
        : 'p${DateTime.now().millisecondsSinceEpoch.toRadixString(36).substring(4)}';
    return _enviarPerfilParaPlaca('profile_save', <String, dynamic>{
      'profile': <String, dynamic>{
        'id': identificador,
        'name': nome,
        'cnt': timings.map((ContactorTiming t) => t.toBoard()).toList(growable: false),
      },
    });
  }

  Future<void> loadStartTypes() async {
    if (_startTypesLoaded) {
      return;
    }
    _startTypesLoaded = true;

    try {
      final List<MotorCommandType> persisted = await loadPersistedStartTypes();
      final List<MotorCommandType> normalized = _normalizePersistedStartTypes(
        persisted,
      );
      if (normalized.isEmpty) {
        return;
      }

      _startTypes
        ..clear()
        ..addAll(normalized);
      _notify();
    } catch (_) {
      // Keep defaults if storage is unavailable or content is invalid.
    }
  }

  /// Perfil (contatores) informado pelo editor de partidas.
  MotorCommandType _comPerfil(
    MotorCommandType base, {
    required bool sequence,
    required int mask,
    required int main,
    required int star,
    required int delta,
    required int seconds,
  }) {
    return base.copyAsStart(
      label: base.label,
      mode: base.mode,
      sequence: sequence,
      mask: mask,
      main: main,
      star: star,
      delta: delta,
      seconds: seconds,
    );
  }

  String? addStartType({
    required String label,
    required String mode,
    bool sequence = false,
    int mask = 1,
    int main = 1,
    int star = 2,
    int delta = 3,
    int seconds = 5,
  }) {
    final String normalizedLabel = _normalizeLabel(label);
    if (normalizedLabel.isEmpty) {
      _pendingMessage = 'Informe o nome da partida.';
      _notify();
      return null;
    }

    final String normalizedMode = _normalizeMode(mode, normalizedLabel);
    if (_containsMode(normalizedMode)) {
      _pendingMessage = 'Já existe uma partida com modo "$normalizedMode".';
      _notify();
      return null;
    }

    final String id =
        'custom_${DateTime.now().millisecondsSinceEpoch}_${_startTypes.length}';
    final MotorCommandType type = _comPerfil(
      MotorCommandType.start(id: id, label: normalizedLabel, mode: normalizedMode),
      sequence: sequence,
      mask: mask,
      main: main,
      star: star,
      delta: delta,
      seconds: seconds,
    );
    if (!type.profileIsValid) {
      _pendingMessage = 'Contatores inválidos para esta partida.';
      _notify();
      return null;
    }
    _startTypes.add(type);
    unawaited(_persistStartTypes());
    _pendingMessage = 'Partida "$normalizedLabel" adicionada.';
    _notify();
    return id;
  }

  bool updateStartType({
    required String id,
    required String label,
    required String mode,
    bool? sequence,
    int? mask,
    int? main,
    int? star,
    int? delta,
    int? seconds,
  }) {
    final int index = _startTypes.indexWhere(
      (MotorCommandType item) => item.id == id,
    );
    if (index == -1) {
      _pendingMessage = 'Partida não encontrada para edição.';
      _notify();
      return false;
    }

    final String normalizedLabel = _normalizeLabel(label);
    if (normalizedLabel.isEmpty) {
      _pendingMessage = 'Informe o nome da partida.';
      _notify();
      return false;
    }

    final String normalizedMode = _normalizeMode(mode, normalizedLabel);
    if (_containsMode(normalizedMode, ignoreId: id)) {
      _pendingMessage = 'Já existe uma partida com modo "$normalizedMode".';
      _notify();
      return false;
    }

    final MotorCommandType atualizado = _startTypes[index].copyAsStart(
      label: normalizedLabel,
      mode: normalizedMode,
      sequence: sequence,
      mask: mask,
      main: main,
      star: star,
      delta: delta,
      seconds: seconds,
    );
    if (!atualizado.profileIsValid) {
      _pendingMessage = 'Contatores inválidos para esta partida.';
      _notify();
      return false;
    }
    _startTypes[index] = atualizado;
    unawaited(_persistStartTypes());
    _pendingMessage = 'Partida "$normalizedLabel" atualizada.';
    _notify();
    return true;
  }

  bool removeStartType(String id) {
    if (_startTypes.length <= 1) {
      _pendingMessage = 'Mantenha pelo menos uma partida configurada.';
      _notify();
      return false;
    }
    // Lista da placa: quem remove é ela, e a nova lista chega por MQTT.
    if (startTypesFromBoard) {
      return _enviarPerfilParaPlaca('profile_remove', <String, dynamic>{'id': id});
    }

    final int index = _startTypes.indexWhere(
      (MotorCommandType item) => item.id == id,
    );
    if (index == -1) {
      _pendingMessage = 'Partida não encontrada para exclusão.';
      _notify();
      return false;
    }

    final String removed = _startTypes[index].label;
    _startTypes.removeAt(index);
    unawaited(_persistStartTypes());
    _pendingMessage = 'Partida "$removed" removida.';
    _notify();
    return true;
  }

  MotorCommandType? _startTypeByMode(String mode) {
    final String normalized = mode.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final MotorCommandType type in _startTypes) {
      if (!type.isStop && type.mode == normalized) {
        return type;
      }
    }
    return null;
  }

  bool _containsMode(String mode, {String? ignoreId}) {
    return _startTypes.any(
      (MotorCommandType item) => item.mode == mode && item.id != ignoreId,
    );
  }

  List<MotorCommandType> _normalizePersistedStartTypes(
    List<MotorCommandType> persisted,
  ) {
    if (persisted.isEmpty) {
      return const <MotorCommandType>[];
    }

    final Set<String> knownModes = <String>{};
    final List<MotorCommandType> normalized = <MotorCommandType>[];

    for (final MotorCommandType raw in persisted) {
      final String label = _normalizeLabel(raw.label);
      if (label.isEmpty) {
        continue;
      }

      final String mode = _normalizeMode(raw.mode, label);
      if (knownModes.contains(mode)) {
        continue;
      }
      knownModes.add(mode);

      final String id = raw.id.trim();
      final String normalizedId =
          id.isEmpty
              ? 'custom_${DateTime.now().millisecondsSinceEpoch}_${normalized.length}'
              : id;

      normalized.add(
        MotorCommandType.start(
          id: normalizedId,
          label: label,
          mode: mode,
          sequence: raw.sequence,
          mask: raw.mask,
          main: raw.main,
          star: raw.star,
          delta: raw.delta,
          seconds: raw.seconds,
        ),
      );
    }

    if (normalized.isEmpty) {
      return <MotorCommandType>[...MotorControlController._defaultStartTypes];
    }
    return normalized;
  }

  Future<void> _persistStartTypes() async {
    try {
      await savePersistedStartTypes(_startTypes);
    } catch (_) {
      // Keep in-memory flow active even if persistence fails.
    }
  }

  String _normalizeLabel(String raw) {
    final String compact = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= 40) {
      return compact;
    }
    return compact.substring(0, 40);
  }

  String _normalizeMode(String raw, String fallbackLabel) {
    String base = raw.trim();
    if (base.isEmpty) {
      base = fallbackLabel;
    }

    String normalized = base.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    normalized = normalized.replaceAll(RegExp(r'_+'), '_');
    normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');

    if (normalized.isNotEmpty) {
      return normalized;
    }
    return 'start_mode_${_startTypes.length + 1}';
  }
}
