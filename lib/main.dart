import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/iot_motor_app.dart';
import 'features/iot_motor/services/background_mqtt_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;
  await BackgroundMqttService.instance.initialize();
  runApp(const MotorControlApp());
}
