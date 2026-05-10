import 'package:flutter/material.dart';
import 'dart:ui';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final Color color;

  const GlassPanel({
    Key? key,
    required this.child,
    this.borderRadius = 16.0,
    this.blur = 8.0,
    this.color = Colors.white24,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          color: color,
          child: child,
        ),
      ),
    );
  }
}
