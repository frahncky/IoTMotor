import 'package:audioplayers/audioplayers.dart';

class SoundPlayer {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> playAsset(String assetPath) async {
    await _player.play(AssetSource(assetPath));
  }

  static Future<void> stop() async {
    await _player.stop();
  }
}
