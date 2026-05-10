import 'package:flutter/material.dart';

import 'package:iotmotor/app/theme/app_theme.dart';
import 'package:iotmotor/features/iot_motor/view/motor_control_page.dart';

class MotorControlApp extends StatelessWidget {
  const MotorControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoTMotor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const MotorControlPage(),
    );
  }
}
