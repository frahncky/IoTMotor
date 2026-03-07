import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.tint,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final Color tintColor = tint ?? AppTheme.brandBlue;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppTheme.surfaceSoft.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ?? tintColor.withValues(alpha: 0.3),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                blurRadius: 16,
                spreadRadius: -10,
                color: Colors.black.withValues(alpha: 0.28),
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
