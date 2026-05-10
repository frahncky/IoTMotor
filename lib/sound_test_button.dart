import 'package:flutter/material.dart';
import 'shared/sound_player.dart';

class SoundTestButton extends StatelessWidget {
  const SoundTestButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => SoundPlayer.playAsset('assets/sound/alert.mp3'),
      child: const Text('Tocar Som'),
    );
  }
}
