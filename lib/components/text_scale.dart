import 'package:flutter/widgets.dart';

/// Escala una altura "de diseño" según el tamaño de texto actual (sistema ×
/// app, ver `AccessibilityController.applyTo`).
///
/// Sirve para contenedores que necesitan altura fija (carruseles, tarjetas
/// dentro de un `ListView` horizontal) pero tienen texto adentro: con texto
/// grande una altura fija desborda. A escala 1,0 devuelve [base] sin cambios.
double scaledHeight(BuildContext context, double base, {double maxFactor = 2.0}) {
  final factor = MediaQuery.textScalerOf(context).scale(100) / 100;
  return base * factor.clamp(1.0, maxFactor);
}
