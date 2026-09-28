import 'package:flutter/material.dart';

// Campo de texto comum às telas das configurações.

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
