import 'package:saluteapp/components/a11y_tap.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';

/// Widgets de inicio de sesión social compartidos entre
/// [LoginScreen] y [RegisterScreen] para no duplicar el botón
/// de Google en los dos lugares.

/// Separador tipo "O INGRESA CON" / "O REGISTRATE CON".
class AuthDivider extends StatelessWidget {
  final String label;
  const AuthDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(color: Colors.grey[300], thickness: 1, height: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: SaluteColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Expanded(
          child: Divider(color: Colors.grey[300], thickness: 1, height: 1),
        ),
      ],
    );
  }
}

/// Botón circular con el logo de Google. `onTap` queda deshabilitado
/// (atenuado) mientras `loading` sea true.
class GoogleAuthButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool loading;
  const GoogleAuthButton({super.key, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: A11yTap(
        label: loading ? 'Ingresando con Google, esperá' : 'Continuar con Google',
        onTap: loading ? null : onTap,
        child: Opacity(
          opacity: loading ? 0.5 : 1,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE8E8E8), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(child: _GoogleLogo()),
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

/// Logo oficial de Google ("G" de cuatro colores) dibujado con los paths
/// vectoriales originales (viewBox 48x48), sin depender de assets.
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  static const _blue =
      'M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17z';
  static const _green =
      'M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46z';
  static const _yellow =
      'M11.69 28.18C11.25 26.86 11 25.45 11 24s.25-2.86.69-4.18v-5.7H4.34C2.85 17.09 2 20.45 2 24c0 3.55.85 6.91 2.34 9.88l7.35-5.7z';
  static const _red =
      'M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z';

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    void fill(String d, Color c) =>
        canvas.drawPath(_parse(d), Paint()..color = c..style = PaintingStyle.fill..isAntiAlias = true);
    fill(_blue, const Color(0xFF4285F4));
    fill(_green, const Color(0xFF34A853));
    fill(_yellow, const Color(0xFFFBBC05));
    fill(_red, const Color(0xFFEA4335));
  }

  /// Parser mínimo de paths SVG: M m L l H h V v C c S s Z z.
  static Path _parse(String d) {
    final tokens = RegExp(r'[a-zA-Z]|-?(?:\d*\.\d+|\d+)').allMatches(d).map((m) => m[0]!).toList();
    final isCmd = RegExp(r'^[a-zA-Z]$');
    final path = Path();
    var i = 0;
    var cmd = '';
    double x = 0, y = 0, sx = 0, sy = 0;
    double cx2 = 0, cy2 = 0; // último punto de control (para S)
    var prevCubic = false;

    double n() {
      var t = tokens[i++];
      if (t.startsWith('.')) t = '0$t';
      if (t.startsWith('-.')) t = '-0${t.substring(1)}';
      return double.parse(t);
    }

    while (i < tokens.length) {
      if (isCmd.hasMatch(tokens[i])) cmd = tokens[i++];
      final rel = cmd == cmd.toLowerCase();
      var cubic = false;
      switch (cmd.toUpperCase()) {
        case 'M':
          final nx = n() + (rel ? x : 0), ny = n() + (rel ? y : 0);
          x = nx; y = ny; sx = x; sy = y;
          path.moveTo(x, y);
          cmd = rel ? 'l' : 'L'; // pares extra = líneas
          break;
        case 'L':
          x = n() + (rel ? x : 0); y = n() + (rel ? y : 0);
          path.lineTo(x, y);
          break;
        case 'H':
          x = n() + (rel ? x : 0);
          path.lineTo(x, y);
          break;
        case 'V':
          y = n() + (rel ? y : 0);
          path.lineTo(x, y);
          break;
        case 'C':
          final x1 = n() + (rel ? x : 0), y1 = n() + (rel ? y : 0);
          final x2 = n() + (rel ? x : 0), y2 = n() + (rel ? y : 0);
          final ex = n() + (rel ? x : 0), ey = n() + (rel ? y : 0);
          path.cubicTo(x1, y1, x2, y2, ex, ey);
          cx2 = x2; cy2 = y2; x = ex; y = ey; cubic = true;
          break;
        case 'S':
          final x1 = prevCubic ? 2 * x - cx2 : x;
          final y1 = prevCubic ? 2 * y - cy2 : y;
          final x2 = n() + (rel ? x : 0), y2 = n() + (rel ? y : 0);
          final ex = n() + (rel ? x : 0), ey = n() + (rel ? y : 0);
          path.cubicTo(x1, y1, x2, y2, ex, ey);
          cx2 = x2; cy2 = y2; x = ex; y = ey; cubic = true;
          break;
        case 'Z':
          path.close();
          x = sx; y = sy;
          break;
        default:
          throw FormatException('Comando SVG no soportado: $cmd');
      }
      prevCubic = cubic;
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
