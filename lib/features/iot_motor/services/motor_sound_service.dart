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
  static final AssetSource _sample = AssetSource('audio/motor-ligado.mp3');

  static const Duration _loopStart = Duration(milliseconds: 1000);
  static const Duration _crossfadeAt = Duration(milliseconds: 3150);
  static const Duration _shutdownStart = Duration(milliseconds: 3700);

  AudioPlayer? _playerA;
  AudioPlayer? _playerB;
  AudioPlayer? _active;
  AudioPlayer? _standby;

  StreamSubscription<Duration>? _positionA;
  StreamSubscription<Duration>? _positionB;
  StreamSubscription<void>? _completeA;
  StreamSubscription<void>? _completeB;

  bool _enabled = false;
  double _volume = 0.70;
  bool? _lastMotorOn;
  bool _baselinePending = true;
  bool _looping = false;
  bool _playing = false;
  bool _testMode = false;
  bool _crossfading = false;
  int _generation = 0;
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
    _volume = (prefs.getDouble(_volumeKey) ?? 0.70)
        .clamp(0.0, 1.0)
        .toDouble();
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);

    if (!value) {
      await _stopAll();
    } else if (_lastMotorOn == true && !_baselinePending) {
      await _startContinuous(includeStartup: false);
    }
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0).toDouble();
    for (final AudioPlayer? player in <AudioPlayer?>[_playerA, _playerB]) {
      if (player != null && player == _active && !_crossfading) {
        await player.setVolume(_volume);
      }
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
    if (!connected || !hasConfirmedState) {
      _baselinePending = true;
      _lastMotorOn = null;
      await _stopAll();
      notifyListeners();
      return;
    }

    if (_baselinePending || _lastMotorOn == null) {
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

  Future<void> testSound() async {
    _lastError = null;
    final int token = ++_generation;
    _testMode = true;
    _looping = false;
    _playing = true;
    _crossfading = false;

    try {
      final (AudioPlayer a, AudioPlayer b) = await _ensurePlayers();
      if (token != _generation) return;
      await b.stop();
      await a.stop();
      await a.setVolume(_volume);
      await a.seek(Duration.zero);
      await a.resume();
      _active = a;
      _standby = b;
    } catch (_) {
      _testMode = false;
      _playing = false;
      _lastError = 'Não foi possível reproduzir o som do motor.';
    }
    notifyListeners();
  }

  Future<void> stopTest() async {
    if (!_testMode) return;
    await _stopAll();
    notifyListeners();
  }

  Future<void> _startContinuous({required bool includeStartup}) async {
    _lastError = null;
    final int token = ++_generation;
    _testMode = false;
    _looping = true;
    _playing = true;
    _crossfading = false;

    try {
      final (AudioPlayer a, AudioPlayer b) = await _ensurePlayers();
      if (token != _generation) return;

      await Future.wait(<Future<void>>[a.stop(), b.stop()]);
      await a.setVolume(_volume);
      await b.setVolume(0);
      await a.seek(includeStartup ? Duration.zero : _loopStart);
      await b.seek(_loopStart);

      _active = a;
      _standby = b;
      await a.resume();
    } catch (_) {
      _looping = false;
      _playing = false;
      _lastError = 'Não foi possível reproduzir o som do motor.';
    }
  }

  Future<void> _crossfadeLoop(AudioPlayer current) async {
    if (!_looping || _crossfading || current != _active) return;
    final AudioPlayer? next = _standby;
    if (next == null) return;

    _crossfading = true;
    final int token = _generation;

    try {
      await next.stop();
      await next.setVolume(0);
      await next.seek(_loopStart);
      await next.resume();

      const int steps = 8;
      const Duration step = Duration(milliseconds: 18);
      for (int i = 1; i <= steps; i++) {
        if (!_looping || token != _generation) return;
        final double t = i / steps;
        await current.setVolume(_volume * (1 - t));
        await next.setVolume(_volume * t);
        await Future<void>.delayed(step);
      }

      if (!_looping || token != _generation) return;
      await current.stop();
      await current.setVolume(0);
      await current.seek(_loopStart);

      _active = next;
      _standby = current;
      await next.setVolume(_volume);
    } catch (_) {
      _lastError = 'Houve uma falha ao manter o som contínuo.';
      _looping = false;
      _playing = false;
      await _stopAll(incrementGeneration: false);
    } finally {
      if (token == _generation) {
        _crossfading = false;
      }
    }
  }

  Future<void> _playShutdown() async {
    _lastError = null;
    final int token = ++_generation;
    _testMode = false;
    _looping = false;
    _playing = true;
    _crossfading = false;

    try {
      final (AudioPlayer a, AudioPlayer b) = await _ensurePlayers();
      if (token != _generation) return;
      await Future.wait(<Future<void>>[a.stop(), b.stop()]);
      await a.setVolume(_volume);
      await a.seek(_shutdownStart);
      _active = a;
      _standby = b;
      await a.resume();
    } catch (_) {
      _playing = false;
      _lastError = 'Não foi possível reproduzir o som de desligamento.';
    }
  }

  Future<(AudioPlayer, AudioPlayer)> _ensurePlayers() async {
    if (_playerA != null && _playerB != null) {
      return (_playerA!, _playerB!);
    }

    final AudioPlayer a = AudioPlayer();
    final AudioPlayer b = AudioPlayer();

    await a.setReleaseMode(ReleaseMode.stop);
    await b.setReleaseMode(ReleaseMode.stop);
    await a.setSource(_sample);
    await b.setSource(_sample);
    await a.setVolume(_volume);
    await b.setVolume(0);

    _positionA = a.onPositionChanged.listen(
      (Duration position) => _onPosition(a, position),
    );
    _positionB = b.onPositionChanged.listen(
      (Duration position) => _onPosition(b, position),
    );
    _completeA = a.onPlayerComplete.listen((_) => _onComplete(a));
    _completeB = b.onPlayerComplete.listen((_) => _onComplete(b));

    _playerA = a;
    _playerB = b;
    _active = a;
    _standby = b;
    return (a, b);
  }

  void _onPosition(AudioPlayer player, Duration position) {
    if (_looping &&
        !_crossfading &&
        player == _active &&
        position >= _crossfadeAt) {
      unawaited(_crossfadeLoop(player));
    }
  }

  void _onComplete(AudioPlayer player) {
    if (player != _active) return;
    if (_testMode) {
      _testMode = false;
      _playing = false;
      notifyListeners();
      return;
    }
    if (!_looping) {
      _playing = false;
      notifyListeners();
    }
  }

  Future<void> _stopAll({bool incrementGeneration = true}) async {
    if (incrementGeneration) {
      _generation++;
    }
    _looping = false;
    _testMode = false;
    _playing = false;
    _crossfading = false;

    final List<Future<void>> stops = <Future<void>>[];
    if (_playerA != null) stops.add(_playerA!.stop());
    if (_playerB != null) stops.add(_playerB!.stop());
    if (stops.isNotEmpty) {
      await Future.wait(stops);
    }
  }

  @override
  void dispose() {
    _positionA?.cancel();
    _positionB?.cancel();
    _completeA?.cancel();
    _completeB?.cancel();
    _playerA?.dispose();
    _playerB?.dispose();
    super.dispose();
  }
}
