import 'package:flutter/material.dart';

const _errorColor = Color(0xFFD64535);
const _errorBg = Color(0xFFFDEEEC);
const _errorBorder = Color(0xFFF4C7C1);

/// Aviso de error que aparece dentro del formulario, justo donde corresponde
/// (arriba del botón que falló). Si [message] es null no ocupa lugar; al
/// aparecer o desaparecer anima la altura para que no "salte" la pantalla.
class InlineErrorBanner extends StatelessWidget {
  final String? message;
  final VoidCallback? onDismiss;
  final EdgeInsetsGeometry margin;

  const InlineErrorBanner({
    super.key,
    required this.message,
    this.onDismiss,
    this.margin = const EdgeInsets.only(bottom: 14),
  });

  @override
  Widget build(BuildContext context) {
    final text = message;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                margin: margin,
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                decoration: BoxDecoration(
                  color: _errorBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _errorBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(Icons.error_outline, size: 20, color: _errorColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8A2A1E),
                        ),
                      ),
                    ),
                    if (onDismiss != null)
                      InkWell(
                        onTap: onDismiss,
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 18, color: _errorColor),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
