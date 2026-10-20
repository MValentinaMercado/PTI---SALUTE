import 'package:flutter/material.dart';

/// Área táctil accesible para controles que son solo un ícono o una imagen.
///
///  - Le da un nombre que lee el lector de pantalla ([label]) y lo marca como
///    botón. Si [label] es null, se usa el texto del propio [child].
///  - Garantiza un área táctil mínima de 48 × 48 dp (Material / WCAG 2.5.8)
///    sin necesidad de agrandar el dibujo: el ícono queda centrado.
///  - [selected] sirve para pestañas / ítems de navegación activos.
class A11yTap extends StatelessWidget {
  final String? label;
  final String? hint;
  final VoidCallback? onTap;
  final bool selected;
  final Widget child;

  const A11yTap({
    super.key,
    required this.onTap,
    required this.child,
    this.label,
    this.hint,
    this.selected = false,
  });

  static const double minTarget = 48;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: label,
      hint: hint,
      // Con etiqueta propia se oculta el ícono/imagen interior; sin etiqueta
      // se deja que el texto del hijo se lea.
      excludeSemantics: label != null,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: minTarget, minHeight: minTarget),
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            heightFactor: 1,
            child: child,
          ),
        ),
      ),
    );
  }
}
