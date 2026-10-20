import 'package:flutter/material.dart';

class SaluteColors {
  SaluteColors._();

  static const primaryGreen  = Color(0xFF1A5C3A);
  /// Oscurecido (antes 0xFF2E7D52, 3,7:1 sobre lightBrown / 4,2:1 sobre lightGreen)
  /// para que el texto y los íconos cumplan AA sobre los fondos tintados.
  static const darkGreen     = Color(0xFF236B46);
  static const lightGreen    = Color(0xFFD6F0E0);
  static const bgColor       = Color(0xFFF8F8F8);
  /// Oscurecido (antes 0xFFB35C2E, 3,4:1 sobre lightBrown / 4,4:1 sobre bgColor).
  static const brownOrange   = Color(0xFF974620);
  static const lightBrown    = Color(0xFFF5D6C8);
  static const terracotta    = Color(0xFF8B3A1A);
  static const cardBeige     = Color(0xFFF5EDE4);

  /// Gris para texto secundario y hints. Cumple WCAG AA (>= 4,5:1) sobre
  /// blanco (6,05), bgColor (5,70), lightGreen (5,01) y cardBeige (5,22).
  /// Reemplaza a Colors.grey[400..600], que sobre blanco dan 1,9 a 4,6:1.
  static const textMuted     = Color(0xFF5F6368);

  /// Estados. Todos cumplen WCAG AA (>= 4,5:1) como texto/ícono sobre blanco
  /// (warning 5,34 · danger 5,62) y sobre bgColor (5,03 · 5,29), y como fondo
  /// con texto blanco encima. Reemplazan a Colors.orange / red / redAccent,
  /// que dan 2,2 a 3,7:1. Nunca deben ser la ÚNICA señal: ir siempre con
  /// texto o ícono.
  static const warning       = Color(0xFFA85400);
  static const danger        = Color(0xFFC62828);
}