import 'package:flutter/material.dart';

// Peças de layout usadas por todas as abas das configurações.

Widget buildPanelTitle(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String title,
  required String subtitle,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(icon, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ],
  );
}

Widget buildInlineNotice(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String text,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color.withValues(alpha: 0.34)),
    ),
    child: Row(
      children: <Widget>[
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}

double fieldWidthFor(double availableWidth) {
  if (availableWidth >= 840) {
    return (availableWidth - 20) / 2;
  }
  if (availableWidth >= 560) {
    return (availableWidth - 20) / 2;
  }
  return availableWidth;
}

/// Campo de texto das configurações; [onChanged] roda a cada tecla.
Widget settingsTextField({
  required double width,
  required String label,
  required TextEditingController controllerField,
  required VoidCallback onChanged,
  TextInputType? keyboardType,
  bool obscureText = false,
  String? Function(String?)? validator,
  String? suffixText,
  String? helperText,
}) {
  return SizedBox(
    width: width,
    child: TextFormField(
      controller: controllerField,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textInputAction: TextInputAction.next,
      onChanged: (_) => onChanged(),
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffixText,
        helperText: helperText,
        helperMaxLines: 2,
      ),
    ),
  );
}
