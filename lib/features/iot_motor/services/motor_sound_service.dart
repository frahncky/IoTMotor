import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MotorSoundService extends ChangeNotifier {
  MotorSoundService() {
    _load();
  }

  static const String _enabledKey = 'motor_sound_enabled_v1';
  static const String _volumeKey = 'motor_sound_volume_v1';
  static const String _sampleUrl =
      'https://iotmotor.pages.dev/motor-ligado.mp3';

  static const Duration _loopStart = Duration(milliseconds: 1000);
  static const Duration _loopEnd = Duration(milliseconds: 3400);
  static const Duration _shutdownStart = Duration(milliseconds: 3700);

  AudioPlayer? _player;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completeSub;

  bool _enabled = false;
  double _volume = 0.70;
  bool? _lastMotorOn;
  bool _baselinePending = true;
  bool _looping = false;
  bool _playing = false;
  bool _testMode = false;
  bool _seekingLoop = false;
  String? _lastError;

  bool get enabled => _enabled;
  double get volume => _volume;
  int get volumePercent => (_volume * 100).round();
  bool get playing => _playing;
  bool get testing => _testMode;
  String? get lastError => _lastError;

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _volume = (prefs.getDouble(_volumeKey) ?? 0.70).clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (!value) {
      _looping = false;
      _testMode = false;
      _playing = false;
      await _player?.stop();
    } else if (_lastMotorOn == true && !_baselinePending) {
      await _startContinuous(includeStartup: false);
    }
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0).toDouble();
    final AudioPlayer? player = _player;
    if (player != null) {
      await player.setVolume(_volume);
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, _volume);
    notifyListeners();
  }

  /// Sincroniza pelo estado confirmado da placa.
  ///
  /// [motorOn] nulo significa que o quadro ainda não informou os contatores.
  /// Ao reconectar, a primeira leitura vira somente referência para não tocar
  /// um falso estalo de partida.
  Future<void> syncConfirmedState({
    required bool connected,
    required bool hasConfirmedState,
    required bool motorOn,
  }) async {
    if (!connected || !hasConfirmedState) {
      _baselinePending = true;
      _lastMotorOn = null;
      _looping = false;
      _testMode = false;
      _playing = false;
      await _player?.stop();
      notifyListeners();
      return;
    }

    if (_baselinePending || _lastMotorOn == null) {
      _baselinePending = false;
      _lastMotorOn = motorOn;
      if (_enabled && motorOn) {
        await _startContinuous(includeStartup: false);
      } else if (!motorOn) {
        _looping = false;
        _playing = false;
        await _player?.stop();
      }
      notifyListeners();
      return;
    }

    if (_lastMotorOn == motorOn) return;
    _lastMotorOn = motorOn;

    if (!_enabled) {
      _looping = false;
      _playing = false;
      await _player?.stop();
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

  Future<void> testSound() async {
    _lastError = null;
    _testMode = true;
    _looping = false;
    _playing = true;
    try {
      await _player?.stop();
      final AudioPlayer player = await _ensurePlayer();
      await player.setVolume(_volume);
      await player.play(UrlSource(_sampleUrl));
    } catch (_) {
      _testMode = false;
      _playing = false;
      _lastError = 'Não foi possível carregar o som do motor.';
    }
    notifyListeners();
  }

  Future<void> stopTest() async {
    if (!_testMode) return;
    _testMode = false;
    _looping = false;
    _playing = false;
    await _player?.stop();
    notifyListeners();
  }

  Future<void> _startContinuous({required bool includeStartup}) async {
    _lastError = null;
    _testMode = false;
    _looping = true;
    _playing = true;
    try {
      await _player?.stop();
      final AudioPlayer player = await _ensurePlayer();
      await player.setVolume(_volume);
      await player.play(
        UrlSource(_sampleUrl),
        position: includeStartup ? Duration.zero : _loopStart,
      );
    } catch (_) {
      _looping = false;
      _playing = false;
      _lastError = 'Não foi possível reproduzir o som do motor.';
    }
  }

  Future<void> _playShutdown() async {
    _lastError = null;
    _testMode = false;
    _looping = false;
    _playing = true;
    try {
      await _player?.stop();
      final AudioPlayer player = await _ensurePlayer();
      await player.setVolume(_volume);
      await player.play(
        UrlSource(_sampleUrl),
        position: _shutdownStart,
      );
    } catch (_) {
      _playing = false;
      _lastError = 'Não foi possível reproduzir o som de desligamento.';
    }
  }

  Future<AudioPlayer> _ensurePlayer() async {
    final AudioPlayer? existing = _player;
    if (existing != null) return existing;

    final AudioPlayer player = AudioPlayer();
    _player = player;
    _positionSub = player.onPositionChanged.listen(_onPosition);
    _completeSub = player.onPlayerComplete.listen((_) {
      if (_testMode) {
        _testMode = false;
      }
      if (!_looping) {
        _playing = false;
        notifyListeners();
      }
    });
    await player.setVolume(_volume);
    return player;
  }

  void _onPosition(Duration position) {
    if (!_looping || _seekingLoop || position < _loopEnd) return;
    final AudioPlayer? player = _player;
    if (player == null) return;
    _seekingLoop = true;
    player.seek(_loopStart).whenComplete(() {
      _seekingLoop = false;
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _completeSub?.cancel();
    _player?.dispose();
    super.dispose();
  }
}
