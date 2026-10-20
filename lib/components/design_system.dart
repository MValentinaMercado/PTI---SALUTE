import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SPACING TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract class DsSpacing {
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
// BORDER RADIUS TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract class DsBorderRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double full = 24.0;
  static const double circle = 999.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHADOW TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract class DsShadow {
  static final List<BoxShadow> sm = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static final List<BoxShadow> md = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];

  static final List<BoxShadow> lg = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.1),
      blurRadius: 16,
      offset: const Offset(0, 8),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// FONT SIZE TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract class DsFontSize {
  static const double xs = 12.0;
  static const double sm = 12.0;
  static const double base = 12.0;
  static const double md = 13.0;
  static const double lg = 14.0;
  static const double xl = 16.0;
  static const double xxl = 18.0;
  static const double display = 26.0;
  static const double h4 = 24.0;
  static const double h3 = 28.0;
  static const double h2 = 32.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// FONT WEIGHT TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract class DsFontWeight {
  static const FontWeight w500 = FontWeight.w500;
  static const FontWeight w600 = FontWeight.w600;
  static const FontWeight w700 = FontWeight.w700;
  static const FontWeight w800 = FontWeight.w800;
  static const FontWeight w900 = FontWeight.w900;
}

// ─────────────────────────────────────────────────────────────────────────────
// LINE HEIGHT TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract class DsLineHeight {
  static const double tight = 1.1;
  static const double normal = 1.4;
  static const double relaxed = 1.6;
}

// ─────────────────────────────────────────────────────────────────────────────
// TEXT STYLES
// ─────────────────────────────────────────────────────────────────────────────

abstract class DsTextStyles {
  static const TextStyle heading1 = TextStyle(
    fontSize: DsFontSize.h2,
    fontWeight: DsFontWeight.w900,
    color: Colors.black87,
    height: DsLineHeight.tight,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: DsFontSize.h3,
    fontWeight: DsFontWeight.w900,
    color: Colors.black87,
    height: DsLineHeight.tight,
  );

  static const TextStyle heading3 = TextStyle(
    fontSize: DsFontSize.h4,
    fontWeight: DsFontWeight.w800,
    color: Colors.black87,
    height: DsLineHeight.normal,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: DsFontSize.lg,
    fontWeight: DsFontWeight.w500,
    color: Colors.black87,
    height: DsLineHeight.normal,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: DsFontSize.md,
    fontWeight: DsFontWeight.w500,
    color: Colors.black87,
    height: DsLineHeight.normal,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: DsFontSize.sm,
    fontWeight: DsFontWeight.w500,
    color: Colors.black87,
    height: DsLineHeight.normal,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: DsFontSize.md,
    fontWeight: DsFontWeight.w700,
    color: Colors.black87,
    letterSpacing: 0.5,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: DsFontSize.xs,
    fontWeight: DsFontWeight.w700,
    color: Color(0xFF5F6368), // textMuted (AA)
    letterSpacing: 0.8,
  );

  static const TextStyle caption = TextStyle(
    fontSize: DsFontSize.xs,
    fontWeight: DsFontWeight.w500,
    color: Color(0xFF666666),
  );
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

  const DsCard({
    Key? key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.borderRadius,
    this.border,
    this.boxShadow,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(DsSpacing.lg),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(borderRadius ?? DsBorderRadius.xl),
        border: border ?? Border.all(color: Colors.grey.shade100),
        boxShadow: boxShadow ?? DsShadow.sm,
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BUTTON PRIMARY COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

class DsButtonPrimary extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final Color? color;
  final double? height;

  const DsButtonPrimary({
    Key? key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.height,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Altura mínima (no fija): con texto grande la etiqueta puede pasar a dos
    // líneas y el botón crece en vez de desbordarse.
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: double.infinity, minHeight: height ?? 56),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color ?? SaluteColors.primaryGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DsBorderRadius.lg),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: DsSpacing.lg),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: DsFontSize.lg,
                  fontWeight: DsFontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
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
  final VoidCallback onPressed;
  final IconData? icon;
  final Color? color;

  const DsButtonSecondary({
    Key? key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color ?? SaluteColors.primaryGreen),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DsBorderRadius.lg),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color ?? SaluteColors.primaryGreen, size: 20),
            const SizedBox(width: DsSpacing.md),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color ?? SaluteColors.primaryGreen,
                fontSize: DsFontSize.lg,
                fontWeight: DsFontWeight.w700,
              ),
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
    Key? key,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    this.size = 40,
    this.borderRadius = DsBorderRadius.md,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Icon(
          icon,
          color: iconColor,
          size: size * 0.55,
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
    Key? key,
    required this.label,
    required this.backgroundColor,
    required this.labelColor,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding ?? DsSpacing.md,
        vertical: DsSpacing.sm * 0.5,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(DsBorderRadius.lg),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: DsFontSize.xs,
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

  const DsDivider({
    Key? key,
    this.color,
    this.height,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Divider(
      color: color ?? Colors.grey.shade200,
      height: height ?? DsSpacing.lg,
      thickness: 1,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROGRESS BAR COMPONENT
// ─────────────────────────────────────────────────────────────────────────────

class DsProgressBar extends StatelessWidget {
  final double value;
  final Color? backgroundColor;
  final Color? valueColor;
  final double height;

  const DsProgressBar({
    Key? key,
    required this.value,
    this.backgroundColor,
    this.valueColor,
    this.height = 5,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DsBorderRadius.sm),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: backgroundColor ?? Colors.grey.shade200,
        valueColor: AlwaysStoppedAnimation<Color>(
          valueColor ?? SaluteColors.primaryGreen,
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
    Key? key,
    required this.activeSegments,
    required this.totalSegments,
    this.activeColor,
    this.inactiveColor,
    this.height = 6,
    this.spacing = 4,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSegments, (i) {
        final isActive = i < activeSegments;
        return Expanded(
          child: Container(
            height: height,
            margin: EdgeInsets.only(right: i < totalSegments - 1 ? spacing : 0),
            decoration: BoxDecoration(
              color: isActive
                  ? (activeColor ?? SaluteColors.primaryGreen)
                  : (inactiveColor ?? Colors.grey.shade200),
              borderRadius: BorderRadius.circular(DsBorderRadius.sm),
            ),
          ),
        );
      }),
    );
  }
}

