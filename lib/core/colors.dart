import 'package:flutter/material.dart';

class SaluteColors {
  SaluteColors._();

  // Brand palette: deep forest greens through soft mint surfaces.
  static const green950 = Color(0xFF00391F);
  static const green900 = Color(0xFF00522F);
  static const green800 = Color(0xFF086C41);
  static const green700 = Color(0xFF2F8658);
  static const green600 = Color(0xFF4CA170);
  static const green500 = Color(0xFF67BC89);
  static const green400 = Color(0xFF83D8A3);
  static const green300 = Color(0xFF9EF5BE);
  static const green200 = Color(0xFFC1FFD4);

  static const primaryGreen = green900;
  static const darkGreen = green950;
  static const lightGreen = green200;
  static const bgColor = Color(0xFFF7FAF8);

  // Semantic accents are intentionally separate from the brand greens.
  static const success = green700;
  static const warning = Color(0xFFD9822B);
  static const alert = Color(0xFFC0392B);
  static const urgent = Color(0xFF9E1B32);
  static const info = Color(0xFF2878A6);

  // Legacy aliases retained for existing profile and map surfaces.
  static const brownOrange = Color(0xFFB35C2E);
  static const lightBrown = Color(0xFFF5D6C8);
  static const terracotta = Color(0xFF8B3A1A);
  static const cardBeige = Color(0xFFF5EDE4);
}
