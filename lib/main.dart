import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/iot_motor_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;
  runApp(const MotorControlApp());
}
