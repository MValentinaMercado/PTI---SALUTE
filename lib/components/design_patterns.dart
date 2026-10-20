import 'package:saluteapp/components/a11y_tap.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'design_system.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN HEADER PATTERN
// Encabezado único para todas las pantallas secundarias. Usa siempre
// AppHeader.secondary (flecha atrás + título) y, opcionalmente, un subtítulo
// (ej: nombre del perfil) con el mismo estilo en todas las pantallas.
// ─────────────────────────────────────────────────────────────────────────────

class DsScreenHeader extends StatelessWidget {
  final String title;

  /// Línea secundaria bajo el título (ej: nombre del perfil activo).
  final String? subtitle;
  final VoidCallback? onBack;

  const DsScreenHeader({
    Key? key,
    required this.title,
    this.subtitle,
    this.onBack,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppHeader.secondary(title: title, onBack: onBack),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: DsSpacing.sm),
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: SaluteColors.textMuted,
                fontSize: DsFontSize.xs,
                fontWeight: DsFontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN LAYOUT PATTERN
// ─────────────────────────────────────────────────────────────────────────────

class DsScreenLayout extends StatelessWidget {
  final Widget header;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final bool scrollable;

  const DsScreenLayout({
    Key? key,
    required this.header,
    required this.children,
    this.padding,
    this.backgroundColor,
    this.scrollable = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );

    return Scaffold(
      backgroundColor: backgroundColor ?? SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            header,
            Expanded(
              child: scrollable
                  ? SingleChildScrollView(
                padding: padding ??
                    const EdgeInsets.fromLTRB(
                      DsSpacing.lg,
                      DsSpacing.lg,
                      DsSpacing.lg,
                      DsSpacing.xl,
                    ),
                child: content,
              )
                  : Padding(
                padding: padding ??
                    const EdgeInsets.fromLTRB(
                      DsSpacing.lg,
                      DsSpacing.lg,
                      DsSpacing.lg,
                      DsSpacing.xl,
                    ),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION HEADER PATTERN
// ─────────────────────────────────────────────────────────────────────────────

class DsSectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;
  final bool showDivider;

  const DsSectionHeader({
    Key? key,
    required this.title,
    this.trailing,
    this.onTrailingTap,
    this.showDivider = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: DsTextStyles.heading3,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: DsSpacing.sm),
              A11yTap(
                onTap: onTrailingTap,
                label: trailing!,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        trailing!,
                        style: TextStyle(
                          fontSize: DsFontSize.xs,
                          fontWeight: DsFontWeight.w700,
                          color: SaluteColors.primaryGreen,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: DsSpacing.sm),
                    Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: SaluteColors.primaryGreen,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        if (showDivider) ...[
          const SizedBox(height: DsSpacing.lg),
          const DsDivider(),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// METRIC CARD PATTERN
// ─────────────────────────────────────────────────────────────────────────────

class DsMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? unit;
  final Color? iconColor;
  final Color? backgroundColor;
  final Widget? trailing;

  const DsMetricCard({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.iconColor,
    this.backgroundColor,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Row(
        children: [
          DsIconContainer(
            icon: icon,
            iconColor: iconColor ?? SaluteColors.primaryGreen,
            backgroundColor:
            backgroundColor ?? SaluteColors.lightGreen.withValues(alpha: 0.3),
          ),
          const SizedBox(width: DsSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: DsTextStyles.labelSmall),
                const SizedBox(height: DsSpacing.sm),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style: const TextStyle(
                          fontSize: DsFontSize.display,
                          fontWeight: DsFontWeight.w900,
                          color: Colors.black87,
                        ),
                      ),
                      if (unit != null)
                        TextSpan(
                          text: ' $unit',
                          style: TextStyle(
                            fontSize: DsFontSize.md,
                            fontWeight: DsFontWeight.w500,
                            color: SaluteColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: DsSpacing.lg),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INFO ROW PATTERN
// ─────────────────────────────────────────────────────────────────────────────

class DsInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? labelColor;
  final Color? valueColor;
  final IconData? icon;
  final Color? iconColor;

  const DsInfoRow({
    Key? key,
    required this.label,
    required this.value,
    this.labelColor,
    this.valueColor,
    this.icon,
    this.iconColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: iconColor ?? SaluteColors.primaryGreen,
                    size: 18,
                  ),
                  const SizedBox(width: DsSpacing.md),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: DsTextStyles.bodyMedium.copyWith(
                      color: labelColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DsSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: DsTextStyles.bodyMedium.copyWith(
                color: valueColor ?? Colors.black87,
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
// EMPTY STATE PATTERN
// ─────────────────────────────────────────────────────────────────────────────

class DsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;

  const DsEmptyState({
    Key? key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.iconColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: iconColor ?? SaluteColors.primaryGreen.withValues(alpha: 0.5),
          ),
          const SizedBox(height: DsSpacing.xl),
          Text(
            title,
            style: DsTextStyles.heading3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DsSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DsSpacing.xl),
            child: Text(
              description,
              style: DsTextStyles.bodyMedium.copyWith(
                color: SaluteColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: DsSpacing.xl),
            DsButtonPrimary(
              label: actionLabel!,
              onPressed: onAction!,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIST TILE PATTERN
// ─────────────────────────────────────────────────────────────────────────────

class DsListTile extends StatelessWidget {
  final IconData? leadingIcon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? tileColor;

  const DsListTile({
    Key? key,
    this.leadingIcon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tileColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DsCard(
        backgroundColor: tileColor ?? Colors.white,
        child: Row(
          children: [
            if (leadingIcon != null) ...[
              DsIconContainer(
                icon: leadingIcon!,
                iconColor: SaluteColors.primaryGreen,
                backgroundColor: SaluteColors.lightGreen.withValues(alpha: 0.3),
                size: 44,
              ),
              const SizedBox(width: DsSpacing.lg),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: DsTextStyles.bodyLarge),
                  if (subtitle != null) ...[
                    const SizedBox(height: DsSpacing.sm),
                    Text(
                      subtitle!,
                      style: DsTextStyles.bodySmall.copyWith(
                        color: SaluteColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: DsSpacing.lg),
              trailing!,
            ] else
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: SaluteColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS BADGE PATTERN
// ─────────────────────────────────────────────────────────────────────────────

enum DsStatusType {
  success,
  warning,
  error,
  info,
  neutral,
}

extension DsStatusTypeExtension on DsStatusType {
  Color get backgroundColor {
    switch (this) {
      case DsStatusType.success:
        return SaluteColors.lightGreen.withValues(alpha: 0.2);
      case DsStatusType.warning:
        return SaluteColors.lightBrown.withValues(alpha: 0.2);
      case DsStatusType.error:
        return const Color(0xFFFFEBEE);
      case DsStatusType.info:
        return SaluteColors.lightGreen.withValues(alpha: 0.1);
      case DsStatusType.neutral:
        return Colors.grey.withValues(alpha: 0.1);
    }
  }

  Color get textColor {
    switch (this) {
      case DsStatusType.success:
        return SaluteColors.darkGreen;
      case DsStatusType.warning:
        return SaluteColors.brownOrange;
      case DsStatusType.error:
        return const Color(0xFFC62828);
      case DsStatusType.info:
        return SaluteColors.primaryGreen;
      case DsStatusType.neutral:
        return Colors.grey.shade700;
    }
  }

  IconData get icon {
    switch (this) {
      case DsStatusType.success:
        return Icons.check_circle_outline;
      case DsStatusType.warning:
        return Icons.warning_outlined;
      case DsStatusType.error:
        return Icons.error_outline;
      case DsStatusType.info:
        return Icons.info_outline;
      case DsStatusType.neutral:
        return Icons.radio_button_unchecked;
    }
  }
}

class DsStatusBadge extends StatelessWidget {
  final DsStatusType type;
  final String label;
  final bool showIcon;

  const DsStatusBadge({
    Key? key,
    required this.type,
    required this.label,
    this.showIcon = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.lg,
        vertical: DsSpacing.md,
      ),
      decoration: BoxDecoration(
        color: type.backgroundColor,
        borderRadius: BorderRadius.circular(DsBorderRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(type.icon, color: type.textColor, size: 16),
            const SizedBox(width: DsSpacing.sm),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: DsFontSize.sm,
              fontWeight: DsFontWeight.w600,
              color: type.textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO SECTION PATTERN
// ─────────────────────────────────────────────────────────────────────────────

class DsHeroSection extends StatelessWidget {
  final Color backgroundColor;
  final String mainTitle;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget>? actions;
  final double height;

  const DsHeroSection({
    Key? key,
    required this.backgroundColor,
    required this.mainTitle,
    this.subtitle,
    this.trailing,
    this.actions,
    this.height = 240,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(DsBorderRadius.full),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          if (trailing != null)
            Positioned(
              right: -20,
              top: -10,
              child: trailing!,
            ),
          Padding(
            padding: const EdgeInsets.all(DsSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mainTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: DsFontSize.display,
                    fontWeight: DsFontWeight.w900,
                    height: DsLineHeight.tight,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: DsSpacing.lg),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: DsFontSize.lg,
                      height: DsLineHeight.normal,
                    ),
                  ),
                ],
                if (actions != null) ...[
                  const Spacer(),
                  Row(
                    children: actions!,
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}