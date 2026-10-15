import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'design_system.dart';

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
    super.key,
    required this.header,
    required this.children,
    this.padding,
    this.backgroundColor,
    this.scrollable = true,
  });

  static const EdgeInsets _defaultPadding = EdgeInsets.fromLTRB(
    DsSpacing.lg,
    DsSpacing.lg,
    DsSpacing.lg,
    DsSpacing.xxxl,
  );

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );

    final body = scrollable
        ? SingleChildScrollView(
            padding: padding ?? _defaultPadding,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: content,
          )
        : Padding(padding: padding ?? _defaultPadding, child: content);

    return Scaffold(
      backgroundColor: backgroundColor ?? SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            header,
            Expanded(
              // Centra y limita el ancho en tablets / web.
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: DsSizes.maxContentWidth,
                  ),
                  child: body,
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
// SECTION HEADER PATTERN
// ─────────────────────────────────────────────────────────────────────────────

class DsSectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;
  final bool showDivider;

  const DsSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onTrailingTap,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: DsTextStyles.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (trailing != null)
              InkWell(
                onTap: onTrailingTap,
                borderRadius: BorderRadius.circular(DsBorderRadius.sm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: DsSizes.tapTarget,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DsSpacing.sm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          trailing!,
                          style: TextStyle(
                            fontSize: DsFontSize.base,
                            fontWeight: DsFontWeight.w700,
                            color: SaluteColors.primaryGreen,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: DsSpacing.xs),
                        Icon(
                          Icons.arrow_forward,
                          size: DsSizes.iconSm,
                          color: SaluteColors.primaryGreen,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (showDivider) ...[
          const SizedBox(height: DsSpacing.sm),
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
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.iconColor,
    this.backgroundColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label: $value${unit != null ? ' $unit' : ''}',
      child: ExcludeSemantics(
        child: DsCard(
          child: Row(
            children: [
              DsIconContainer(
                icon: icon,
                iconColor: iconColor ?? SaluteColors.primaryGreen,
                backgroundColor:
                    backgroundColor ??
                    SaluteColors.lightGreen.withValues(alpha: 0.3),
                size: 48,
              ),
              const SizedBox(width: DsSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: DsTextStyles.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: DsSpacing.xs),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: value, style: DsTextStyles.display),
                          if (unit != null)
                            TextSpan(
                              text: ' $unit',
                              style: const TextStyle(
                                fontSize: DsFontSize.lg,
                                fontWeight: DsFontWeight.w600,
                                color: DsColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
        ),
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
    super.key,
    required this.label,
    required this.value,
    this.labelColor,
    this.valueColor,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: iconColor ?? SaluteColors.primaryGreen,
              size: DsSizes.iconMd,
            ),
            const SizedBox(width: DsSpacing.md),
          ],
          Expanded(
            child: Text(
              label,
              style: DsTextStyles.bodyMedium.copyWith(
                color: labelColor ?? DsColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: DsSpacing.lg),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: DsTextStyles.bodyMedium.copyWith(
                color: valueColor ?? DsColors.textPrimary,
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
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? SaluteColors.primaryGreen;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DsSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 52, color: color.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: DsSpacing.xxl),
            Text(
              title,
              style: DsTextStyles.heading3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DsSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DsSpacing.lg),
              child: Text(
                description,
                style: DsTextStyles.bodyMedium.copyWith(
                  color: DsColors.textSecondary,
                  height: DsLineHeight.relaxed,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: DsSpacing.xxl),
              DsButtonPrimary(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
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
    super.key,
    this.leadingIcon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tileColor,
  });

  @override
  Widget build(BuildContext context) {
    return DsCard(
      backgroundColor: tileColor,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
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
                  Text(
                    title,
                    style: DsTextStyles.bodyLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: DsSpacing.xs),
                    Text(
                      subtitle!,
                      style: DsTextStyles.bodySmall.copyWith(
                        color: DsColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: DsSpacing.lg),
              trailing!,
            ] else if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                size: DsSizes.iconLg,
                color: DsColors.textTertiary,
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

enum DsStatusType { success, warning, error, info, neutral }

extension DsStatusTypeExtension on DsStatusType {
  Color get backgroundColor {
    switch (this) {
      case DsStatusType.success:
        return SaluteColors.lightGreen.withValues(alpha: 0.2);
      case DsStatusType.warning:
        return SaluteColors.lightBrown.withValues(alpha: 0.2);
      case DsStatusType.error:
        return SaluteColors.alert.withValues(alpha: 0.1);
      case DsStatusType.info:
        return SaluteColors.lightGreen.withValues(alpha: 0.1);
      case DsStatusType.neutral:
        return Colors.grey.withValues(alpha: 0.12);
    }
  }

  Color get textColor {
    switch (this) {
      case DsStatusType.success:
        return SaluteColors.darkGreen;
      case DsStatusType.warning:
        return SaluteColors.brownOrange;
      case DsStatusType.error:
        return SaluteColors.alert;
      case DsStatusType.info:
        return SaluteColors.primaryGreen;
      case DsStatusType.neutral:
        return DsColors.textSecondary;
    }
  }

  IconData get icon {
    switch (this) {
      case DsStatusType.success:
        return Icons.check_circle_outline;
      case DsStatusType.warning:
        return Icons.warning_amber_rounded;
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
    super.key,
    required this.type,
    required this.label,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.md,
        vertical: DsSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: type.backgroundColor,
        borderRadius: BorderRadius.circular(DsBorderRadius.circle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(type.icon, color: type.textColor, size: DsSizes.iconSm),
            const SizedBox(width: DsSpacing.xs + 2),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DsFontSize.base,
                fontWeight: DsFontWeight.w700,
                color: type.textColor,
              ),
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

  /// Altura mínima. Crece si el contenido (o el tamaño de fuente del sistema)
  /// lo necesita, en lugar de desbordar.
  final double height;

  const DsHeroSection({
    super.key,
    required this.backgroundColor,
    required this.mainTitle,
    this.subtitle,
    this.trailing,
    this.actions,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: height),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(DsBorderRadius.full),
        boxShadow: DsShadow.md,
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          if (trailing != null)
            Positioned(
              right: -20,
              top: -10,
              child: ExcludeSemantics(child: trailing!),
            ),
          Padding(
            padding: const EdgeInsets.all(DsSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mainTitle,
                  style: DsTextStyles.display.copyWith(color: DsColors.onBrand),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: DsSpacing.md),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: DsFontSize.xl,
                      height: DsLineHeight.normal,
                    ),
                  ),
                ],
                if (actions != null) ...[
                  const SizedBox(height: DsSpacing.xxl),
                  Wrap(
                    spacing: DsSpacing.md,
                    runSpacing: DsSpacing.md,
                    children: actions!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
