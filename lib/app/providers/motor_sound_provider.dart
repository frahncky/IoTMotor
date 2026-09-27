import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/iot_motor/services/motor_sound_service.dart';

final motorSoundServiceProvider =
    ChangeNotifierProvider<MotorSoundService>((ref) => MotorSoundService());
