import '../models/motor_app_settings.dart';
import 'motor_settings_store_stub.dart'
    if (dart.library.io) 'motor_settings_store_io.dart'
    as impl;

Future<MotorAppSettings?> loadPersistedMotorSettings() {
  return impl.loadPersistedMotorSettings();
}

Future<void> savePersistedMotorSettings(MotorAppSettings settings) {
  return impl.savePersistedMotorSettings(settings);
}
