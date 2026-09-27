import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MotorSoundService extends ChangeNotifier {
  MotorSoundService() {
    _positionSub = _player.onPositionChanged.listen(_onPosition);
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (_testMode) {
        _testMode = false;
      }
      if (!_looping) {
        _playing = false;
        notifyListeners();
      }
    });
    _load();
  }

  static const String _enabledKey = 'motor_sound_enabled_v1';
  static const String _volumeKey = 'motor_sound_volume_v1';
  static const String _sampleUrl =
      'https://iotmotor.pages.dev/motor-ligado.mp3';

  static const Duration _loopStart = Duration(milliseconds: 1000);
  static const Duration _loopEnd = Duration(milliseconds: 3700);

  final AudioPlayer _player = AudioPlayer();

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

  bool get enabled => _enabled;
  double get volume => _volume;
  int get volumePercent => (_volume * 100).round();
  bool get playing => _playing;

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _volume = (prefs.getDouble(_volumeKey) ?? 0.70).clamp(0.0, 1.0);
    await _player.setVolume(_volume);
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
      await _player.stop();
    } else if (_lastMotorOn == true && !_baselinePending) {
      await _startContinuous(includeStartup: false);
    }
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
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
      await _player.stop();
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
        await _player.stop();
      }
      notifyListeners();
      return;
    }

    if (_lastMotorOn == motorOn) return;
    _lastMotorOn = motorOn;

    if (!_enabled) {
      _looping = false;
      _playing = false;
      await _player.stop();
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
    _testMode = true;
    _looping = false;
    _playing = true;
    await _player.stop();
    await _player.setVolume(_volume);
    await _player.play(UrlSource(_sampleUrl));
    notifyListeners();
  }

  Future<void> stopTest() async {
    if (!_testMode) return;
    _testMode = false;
    _looping = false;
    _playing = false;
    await _player.stop();
    notifyListeners();
  }

  Future<void> _startContinuous({required bool includeStartup}) async {
    _testMode = false;
    _looping = true;
    _playing = true;
    await _player.stop();
    await _player.setVolume(_volume);
    await _player.play(
      UrlSource(_sampleUrl),
      position: includeStartup ? Duration.zero : _loopStart,
    );
  }

  Future<void> _playShutdown() async {
    _testMode = false;
    _looping = false;
    _playing = true;
    await _player.stop();
    await _player.setVolume(_volume);
    await _player.play(
      UrlSource(_sampleUrl),
      position: _loopEnd,
    );
  }

  void _onPosition(Duration position) {
    if (!_looping || _seekingLoop || position < _loopEnd) return;
    _seekingLoop = true;
    _player.seek(_loopStart).whenComplete(() {
      _seekingLoop = false;
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
