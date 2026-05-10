import 'package:flutter/material.dart';

class MqttConnectionStatusIcon extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;
  final double size;

  const MqttConnectionStatusIcon({
    Key? key,
    required this.isConnected,
    this.isConnecting = false,
    this.size = 24.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    if (isConnected) {
      color = Colors.green;
      icon = Icons.cloud_done;
    } else if (isConnecting) {
      color = Colors.orange;
      icon = Icons.cloud_sync;
    } else {
      color = Colors.red;
      icon = Icons.cloud_off;
    }
    return Icon(icon, color: color, size: size);
  }
}
