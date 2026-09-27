import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:iotmotor/app/iot_motor_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // As fontes vem nos assets (assets/google_fonts): nada de baixar do Google
  // ao abrir o app, e o texto sai igual sem internet.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    for (final String familia in <String>['Manrope', 'Outfit']) {
      final String texto = await rootBundle.loadString('assets/google_fonts/$familia-OFL.txt');
      yield LicenseEntryWithLineBreaks(<String>[familia], texto);
    }
  });
  runApp(const ProviderScope(child: MotorControlApp()));
}
