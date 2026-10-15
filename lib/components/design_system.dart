import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NEUTRAL COLOR TOKENS
// (La marca sigue viviendo en SaluteColors; aquí solo van los neutros.)
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DsColors {
  /// Texto principal. Contraste ~16:1 sobre blanco.
  static const Color textPrimary = Color(0xFF1A1D1F);

  /// Texto secundario (descripciones, etiquetas). Contraste ~5.7:1 (AA).
  static const Color textSecondary = Color(0xFF5F6670);

  /// Solo para placeholders / elementos decorativos. No usar para info clave.
  static const Color textTertiary = Color(0xFF8A919A);

  static const Color surface = Colors.white;
  static const Color border = Color(0xFFEDEFF1);
  static const Color divider = Color(0xFFE5E7EA);
  static const Color track = Color(0xFFE9ECEF);
  static const Color onBrand = Colors.white;
}

// ─────────────────────────────────────────────────────────────────────────────
// SPACING TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DsSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double huge = 48.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// SIZE TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DsSizes {
  /// Área táctil mínima recomendada (Material / WCAG).
  static const double tapTarget = 48.0;
  static const double buttonHeight = 56.0;
  static const double iconSm = 16.0;
  static const double iconMd = 20.0;
  static const double iconLg = 24.0;

  /// Ancho máximo del contenido en pantallas anchas (tablet / web).
  static const double maxContentWidth = 640.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// BORDER RADIUS TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DsBorderRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double full = 24.0;
  static const double circle = 999.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHADOW TOKENS (const: no se reconstruyen en cada build)
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DsShadow {
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 8)),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// MOTION TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DsMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve curve = Curves.easeOutCubic;
}

// ─────────────────────────────────────────────────────────────────────────────
// FONT SIZE TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DsFontSize {
  static const double xs = 10.0; // solo para badges muy compactos
  static const double sm = 11.0;
  static const double base = 12.0;
  static const double md = 13.0;
  static const double lg = 14.0;
  static const double xl = 16.0;
  static const double xxl = 18.0;
  static const double sectionTitle = 20.0;
  static const double h4 = 24.0;
  static const double display = 28.0;
  static const double h3 = 28.0;
  static const double h2 = 32.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// FONT WEIGHT TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DsFontWeight {
  static const FontWeight w500 = FontWeight.w500;
  static const FontWeight w600 = FontWeight.w600;
  static const FontWeight w700 = FontWeight.w700;
  static const FontWeight w800 = FontWeight.w800;
  static const FontWeight w900 = FontWeight.w900;
}

// ─────────────────────────────────────────────────────────────────────────────
// LINE HEIGHT TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DsLineHeight {
  static const double tight = 1.1;
  static const double normal = 1.4;
  static const double relaxed = 1.6;
}

// ─────────────────────────────────────────────────────────────────────────────
// TEXT STYLES
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DsTextStyles {
  static const TextStyle display = TextStyle(
    fontSize: DsFontSize.display,
    fontWeight: DsFontWeight.w800,
    color: DsColors.textPrimary,
    height: DsLineHeight.tight,
    letterSpacing: -0.5,
  );

  static const TextStyle heading1 = TextStyle(
    fontSize: DsFontSize.h2,
    fontWeight: DsFontWeight.w800,
    color: DsColors.textPrimary,
    height: DsLineHeight.tight,
    letterSpacing: -0.5,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: DsFontSize.h3,
    fontWeight: DsFontWeight.w800,
    color: DsColors.textPrimary,
    height: DsLineHeight.tight,
    letterSpacing: -0.4,
  );

  static const TextStyle heading3 = TextStyle(
    fontSize: DsFontSize.h4,
    fontWeight: DsFontWeight.w800,
    color: DsColors.textPrimary,
    height: DsLineHeight.normal,
    letterSpacing: -0.3,
  );

  /// Títulos de sección y de estados vacíos.
  static const TextStyle title = TextStyle(
    fontSize: DsFontSize.sectionTitle,
    fontWeight: DsFontWeight.w800,
    color: DsColors.textPrimary,
    height: DsLineHeight.normal,
    letterSpacing: -0.2,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: DsFontSize.lg,
    fontWeight: DsFontWeight.w600,
    color: DsColors.textPrimary,
    height: DsLineHeight.normal,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: DsFontSize.md,
    fontWeight: DsFontWeight.w500,
    color: DsColors.textPrimary,
    height: DsLineHeight.normal,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: DsFontSize.base,
    fontWeight: DsFontWeight.w500,
    color: DsColors.textPrimary,
    height: DsLineHeight.normal,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: DsFontSize.md,
    fontWeight: DsFontWeight.w700,
    color: DsColors.textPrimary,
    letterSpacing: 0.3,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: DsFontSize.sm,
    fontWeight: DsFontWeight.w700,
    color: DsColors.textSecondary,
    letterSpacing: 0.8,
  );

  static const TextStyle caption = TextStyle(
    fontSize: DsFontSize.sm,
    fontWeight: DsFontWeight.w500,
    color: DsColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontSize: DsFontSize.lg,
    fontWeight: DsFontWeight.w800,
    letterSpacing: 0.3,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION TITLE (con barra de acento)
// ─────────────────────────────────────────────────────────────────────────────

class DsSectionTitle extends StatelessWidget {
  final String title;

  const DsSectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: SaluteColors.primaryGreen,
              borderRadius: BorderRadius.circular(DsBorderRadius.circle),
            ),
          ),
          const SizedBox(width: DsSpacing.md),
          Flexible(
            child: Text(
              title,
              style: DsTextStyles.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

class DsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final double? borderRadius;
  final Border? border;
  final List<BoxShadow>? boxShadow;

  /// Si se define, la tarjeta es interactiva (ripple + foco + semántica).
  final VoidCallback? onTap;

  const DsCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.borderRadius,
    this.border,
    this.boxShadow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius ?? DsBorderRadius.xl);
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(DsSpacing.lg),
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? DsColors.surface,
        borderRadius: radius,
        border: border ?? Border.all(color: DsColors.border),
        boxShadow: boxShadow ?? DsShadow.sm,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: radius, child: content),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BUTTON PRIMARY COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

class DsButtonPrimary extends StatelessWidget {
  final String label;

  /// `null` deshabilita el botón.
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final double? height;

  /// Muestra un spinner y bloquea la interacción.
  final bool isLoading;

  /// Ocupa todo el ancho disponible.
  final bool expand;

  const DsButtonPrimary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.height,
    this.isLoading = false,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final base = color ?? SaluteColors.primaryGreen;
    final enabled = onPressed != null && !isLoading;

    return SizedBox(
      width: expand ? double.infinity : null,
      height: height ?? DsSizes.buttonHeight,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: base,
          foregroundColor: DsColors.onBrand,
          disabledBackgroundColor: base.withValues(alpha: 0.35),
          disabledForegroundColor: DsColors.onBrand.withValues(alpha: 0.85),
          padding: const EdgeInsets.symmetric(horizontal: DsSpacing.xxl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DsBorderRadius.lg),
          ),
          elevation: 0,
        ),
        child: AnimatedSwitcher(
          duration: DsMotion.fast,
          child: isLoading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: DsColors.onBrand,
                  ),
                )
              : Row(
                  key: const ValueKey('label'),
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: DsSizes.iconMd),
                      const SizedBox(width: DsSpacing.md),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: DsTextStyles.button,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BUTTON SECONDARY COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

class DsButtonSecondary extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool expand;

  const DsButtonSecondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final base = color ?? SaluteColors.primaryGreen;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: base,
        minimumSize: Size(expand ? double.infinity : 0, DsSizes.tapTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.xl,
          vertical: DsSpacing.md,
        ),
        side: BorderSide(
          color: onPressed == null ? base.withValues(alpha: 0.3) : base,
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DsBorderRadius.lg),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: DsSizes.iconMd),
            const SizedBox(width: DsSpacing.md),
          ],
          Flexible(
            child: Text(
              label,
              style: DsTextStyles.button.copyWith(
                fontWeight: DsFontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ICON CONTAINER COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

class DsIconContainer extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final double size;
  final double borderRadius;

  const DsIconContainer({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    this.size = 40,
    this.borderRadius = DsBorderRadius.md,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Center(
          child: Icon(icon, color: iconColor, size: size * 0.5),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BADGE COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

class DsBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color labelColor;
  final double? padding;

  const DsBadge({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.labelColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding ?? DsSpacing.md,
        vertical: DsSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(DsBorderRadius.circle),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: DsFontSize.sm,
          fontWeight: DsFontWeight.w700,
          color: labelColor,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIVIDER COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

class DsDivider extends StatelessWidget {
  final Color? color;
  final double? height;

  const DsDivider({super.key, this.color, this.height});

  @override
  Widget build(BuildContext context) {
    return Divider(
      color: color ?? DsColors.divider,
      height: height ?? DsSpacing.lg,
      thickness: 1,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROGRESS BAR COMPONENT (animada)
// ─────────────────────────────────────────────────────────────────────────────

class DsProgressBar extends StatelessWidget {
  final double value;
  final Color? backgroundColor;
  final Color? valueColor;
  final double height;

  const DsProgressBar({
    super.key,
    required this.value,
    this.backgroundColor,
    this.valueColor,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);

    return Semantics(
      value: '${(target * 100).round()}%',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        duration: DsMotion.slow,
        curve: DsMotion.curve,
        builder: (context, animated, _) => ClipRRect(
          borderRadius: BorderRadius.circular(DsBorderRadius.circle),
          child: LinearProgressIndicator(
            value: animated,
            minHeight: height,
            backgroundColor: backgroundColor ?? DsColors.track,
            valueColor: AlwaysStoppedAnimation<Color>(
              valueColor ?? SaluteColors.primaryGreen,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEGMENTED BAR COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

class DsSegmentedBar extends StatelessWidget {
  final int activeSegments;
  final int totalSegments;
  final Color? activeColor;
  final Color? inactiveColor;
  final double height;
  final double spacing;

  const DsSegmentedBar({
    super.key,
    required this.activeSegments,
    required this.totalSegments,
    this.activeColor,
    this.inactiveColor,
    this.height = 6,
    this.spacing = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: '$activeSegments/$totalSegments',
      child: Row(
        children: List.generate(totalSegments, (i) {
          final isActive = i < activeSegments;
          return Expanded(
            child: AnimatedContainer(
              duration: DsMotion.normal,
              curve: DsMotion.curve,
              height: height,
              margin: EdgeInsets.only(
                right: i < totalSegments - 1 ? spacing : 0,
              ),
              decoration: BoxDecoration(
                color: isActive
                    ? (activeColor ?? SaluteColors.primaryGreen)
                    : (inactiveColor ?? DsColors.track),
                borderRadius: BorderRadius.circular(DsBorderRadius.circle),
              ),
            ),
          );
        }),
      ),
    );
  }
}
