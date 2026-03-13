import '../models/motor_command_type.dart';
import 'start_types_store_stub.dart'
    if (dart.library.io) 'start_types_store_io.dart'
    as impl;

Future<List<MotorCommandType>> loadPersistedStartTypes() {
  return impl.loadPersistedStartTypes();
}

Future<void> savePersistedStartTypes(List<MotorCommandType> startTypes) {
  return impl.savePersistedStartTypes(startTypes);
}
