import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/iot_motor/services/motor_animation_prefs.dart';

final motorAnimationPrefsProvider = ChangeNotifierProvider<MotorAnimationPrefs>(
  (ref) => MotorAnimationPrefs(),
);
