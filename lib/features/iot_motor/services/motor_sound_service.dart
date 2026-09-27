import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Som do motor, igual ao do painel web.
///
/// A gravação vem em três partes, geradas de `motor-ligado.mp3` com o mesmo
/// processamento do painel (`tools/gerar-audio-motor.js`):
/// - `motor-partida.wav`: estalo de ligar e o motor acelerando;
/// - `motor-laco.wav`: o trecho estável, com a emenda já fundida. Ele é
///   repetido pelo próprio Android (SoundPool, em memória), amostra por
///   amostra, sem o reinício perceptível de trocar de player por código;
/// - `motor-parada.wav`: estalos de desligar e o motor parando.
///
/// Na partida, o laço entra por cima do fim da partida (0,25 s, potência
/// constante), no mesmo ponto em que o painel passa a repetir.
class MotorSoundService extends ChangeNotifier {
  MotorSoundService() {
    _load();
  }

  static const String _enabledKey = 'motor_sound_enabled_v1';
  static const String _volumeKey = 'motor_sound_volume_v1';
  static final AssetSource _partida = AssetSource('audio/motor-partida.wav');
  static final AssetSource _laco = AssetSource('audio/motor-laco.wav');
  static final AssetSource _parada = AssetSource('audio/motor-parada.wav');

  /// Onde o laço começa dentro da partida, e quanto os dois se sobrepõem.
  static const Duration _entradaDoLaco = Duration(milliseconds: 1000);
  static const Duration _sobreposicao = Duration(milliseconds: 250);
  static const Duration _duracaoDoTeste = Duration(seconds: 5);

  AudioPlayer? _playerPartida;
  AudioPlayer? _playerLaco;
  AudioPlayer? _playerParada;
  StreamSubscription<void>? _fimDaParada;
  Timer? _timer;

  bool _enabled = false;
  bool _foreground = true;
  double _volume = 0.70;
  bool? _lastMotorOn;
  bool _baselinePending = true;
  bool _playing = false;
  bool _testMode = false;
  int _generation = 0;
  String? _lastError;

  bool get enabled => _enabled;
  bool get foreground => _foreground;
  double get volume => _volume;
  int get volumePercent => (_volume * 100).round();
  bool get playing => _playing;
  bool get testing => _testMode;
  String? get lastError => _lastError;

  /// Mesma curva do painel (gainForVolume): o nível já vem nos arquivos, e o
  /// controle de volume é quadrático, então 70% soa igual nos dois.
  double get _ganho => _volume * _volume;

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _volume = (prefs.getDouble(_volumeKey) ?? 0.70).clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  /// O áudio só pode tocar enquanto o app estiver em primeiro plano.
  ///
  /// Ao sair do app, qualquer áudio é interrompido imediatamente e o próximo
  /// estado recebido vira uma nova referência. Assim, ao voltar com o motor já
  /// ligado, retomamos apenas o som contínuo, sem simular uma nova partida.
  Future<void> setForeground(bool value) async {
    if (_foreground == value) return;
    _foreground = value;

    if (!value) {
      _baselinePending = true;
      await _stopAll();
    }

    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);

    if (!value) {
      await _stopAll();
    } else if (_foreground && _lastMotorOn == true && !_baselinePending) {
      await _startContinuous(includeStartup: false);
    }
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0).toDouble();
    if (_playing) {
      // Muda na hora o que está tocando (o laço em transição ajusta sozinho).
      await _playerLaco?.setVolume(_ganho);
      await _playerParada?.setVolume(_ganho);
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, _volume);
    notifyListeners();
  }

  Future<void> syncConfirmedState({
    required bool connected,
    required bool hasConfirmedState,
    required bool motorOn,
  }) async {
    if (!_foreground) {
      if (connected && hasConfirmedState) {
        _lastMotorOn = motorOn;
      } else {
        _lastMotorOn = null;
      }
      _baselinePending = true;
      if (_playing || _testMode) {
        await _stopAll();
      }
      return;
    }

    if (!connected || !hasConfirmedState) {
      _baselinePending = true;
      _lastMotorOn = null;
      await _stopAll();
      notifyListeners();
      return;
    }

    if (_baselinePending || _lastMotorOn == null) {
      // Primeiro estado depois de conectar: motor já ligado entra direto no
      // trecho estável, sem estalo de partida (como a reconexão do painel).
      _baselinePending = false;
      _lastMotorOn = motorOn;
      if (_enabled && motorOn) {
        await _startContinuous(includeStartup: false);
      } else if (!motorOn) {
        await _stopAll();
      }
      notifyListeners();
      return;
    }

    if (_lastMotorOn == motorOn) return;
    _lastMotorOn = motorOn;

    if (!_enabled) {
      await _stopAll();
      notifyListeners();
      return;
    }

    if (motorOn) {
      await _startContinuous(includeStartup: true);
    } else {
      await _playShutdown();
    }
    notifyListeners();
  }

  /// Teste local, como o do painel: partida, 5 s ligado e desligamento.
  Future<void> testSound() async {
    if (!_foreground) return;
    await _startContinuous(includeStartup: true, test: true);
    if (!_testMode) return;
    final int token = _generation;
    _timer = Timer(_duracaoDoTeste, () {
      if (token == _generation && _testMode) unawaited(_playShutdown());
    });
    notifyListeners();
  }

  Future<void> stopTest() async {
    if (!_testMode) return;
    await _stopAll();
    notifyListeners();
  }

  Future<void> _startContinuous({required bool includeStartup, bool test = false}) async {
    if (!_foreground) return;
    _lastError = null;
    await _stopAll();
    final int token = _generation;
    _testMode = test;
    _playing = true;

    try {
      final AudioPlayer laco = await _ensureLaco();
      if (token != _generation) return;
      if (!includeStartup) {
        await laco.setVolume(_ganho);
        await laco.resume();
        return;
      }

      final AudioPlayer partida = await _ensurePartida();
      if (token != _generation) return;
      await partida.setVolume(_ganho);
      await partida.resume();

      // O laço entra onde o painel passa a repetir, subindo em seno enquanto
      // a partida (já gravada com a saída em cosseno) desce.
      _timer = Timer(_entradaDoLaco, () => unawaited(_entrarNoLaco(laco, token)));
    } catch (_) {
      _playing = false;
      _testMode = false;
      _lastError = 'Não foi possível reproduzir o som do motor.';
    }
  }

  Future<void> _entrarNoLaco(AudioPlayer laco, int token) async {
    if (token != _generation) return;
    try {
      await laco.setVolume(0);
      await laco.resume();
      const int passos = 10;
      final int passoMs = _sobreposicao.inMilliseconds ~/ passos;
      for (int i = 1; i <= passos; i++) {
        await Future<void>.delayed(Duration(milliseconds: passoMs));
        if (token != _generation) return;
        await laco.setVolume(_ganho * math.sin(i / passos * math.pi / 2));
      }
    } catch (_) {
      _lastError = 'Houve uma falha ao manter o som contínuo.';
    }
  }

  Future<void> _playShutdown() async {
    if (!_foreground) {
      await _stopAll();
      return;
    }
    _lastError = null;
    _timer?.cancel();
    final int token = ++_generation;
    _playing = true;

    try {
      final AudioPlayer parada = await _ensureParada();
      if (token != _generation) return;
      await parada.setVolume(_ganho);
      await parada.seek(Duration.zero);
      await parada.resume();
      // O laço some em ~50 ms enquanto os estalos de desligar começam.
      final AudioPlayer? laco = _playerLaco;
      if (laco != null) {
        for (final double fator in <double>[0.6, 0.3, 0.1]) {
          await laco.setVolume(_ganho * fator);
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        await laco.stop();
      }
      await _playerPartida?.stop();
    } catch (_) {
      _playing = false;
      _testMode = false;
      _lastError = 'Não foi possível reproduzir o som de desligamento.';
    }
    notifyListeners();
  }

  Future<AudioPlayer> _ensureLaco() async {
    final AudioPlayer? pronto = _playerLaco;
    if (pronto != null) return pronto;
    final AudioPlayer player = AudioPlayer();
    // SoundPool: o trecho fica decodificado na memória e o Android repete sem
    // emenda. (O MediaPlayer faz uma pausa ao voltar ao início do arquivo.)
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setReleaseMode(ReleaseMode.loop);
    await player.setSource(_laco);
    _playerLaco = player;
    return player;
  }

  Future<AudioPlayer> _ensurePartida() async {
    final AudioPlayer? pronto = _playerPartida;
    if (pronto != null) return pronto;
    final AudioPlayer player = AudioPlayer();
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(_partida);
    _playerPartida = player;
    return player;
  }

  Future<AudioPlayer> _ensureParada() async {
    final AudioPlayer? pronto = _playerParada;
    if (pronto != null) return pronto;
    final AudioPlayer player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(_parada);
    _fimDaParada = player.onPlayerComplete.listen((_) {
      _playing = false;
      _testMode = false;
      notifyListeners();
    });
    _playerParada = player;
    return player;
  }

  Future<void> _stopAll() async {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _testMode = false;
    _playing = false;
    await Future.wait(<Future<void>>[
      for (final AudioPlayer? player in <AudioPlayer?>[_playerPartida, _playerLaco, _playerParada])
        if (player != null) player.stop(),
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fimDaParada?.cancel();
    _playerPartida?.dispose();
    _playerLaco?.dispose();
    _playerParada?.dispose();
    super.dispose();
  }
}
