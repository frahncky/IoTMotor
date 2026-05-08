import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/iot_motor/models/motor_app_settings.dart';

final preferencesProvider =
    StateNotifierProvider<PreferencesNotifier, MotorAppSettings>(
      (ref) => PreferencesNotifier(),
    );

class PreferencesNotifier extends StateNotifier<MotorAppSettings> {
  PreferencesNotifier() : super(MotorAppSettings.initial());

  void updateRetentionDays(int days) {
    state = state.copyWith(historyRetentionDays: days.clamp(1, 3650));
  }

  void updateRemoteRetentionDays(int days) {
    state = state.copyWith(remoteHistoryRetentionDays: days.clamp(1, 3650));
  }
}
