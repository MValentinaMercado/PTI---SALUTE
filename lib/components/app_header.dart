import 'package:saluteapp/components/a11y_tap.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/components/design_system.dart';

/// Header reutilizable para toda la app.
/// - `dashboard`: estilo propio del dashboard principal.
/// - `secondary`: estilo de Diario para ventanas secundarias.
class AppHeader extends StatelessWidget {
  final String? title;
  final VoidCallback? onBack;
  final VoidCallback? onLogoTap;
  final VoidCallback? onSettings;
  final VoidCallback? onNotifications;
  final bool showNotificationBadge;
  final bool _isDashboard;

  const AppHeader.dashboard({
    super.key,
    this.onLogoTap,
    this.onNotifications,
    this.showNotificationBadge = false,
  })  : _isDashboard = true,
        title = null,
        onBack = null,
        onSettings = null;

  const AppHeader.secondary({
    super.key,
    required String this.title,
    this.onBack,
    this.onSettings,
  })  : _isDashboard = false,
        onLogoTap = null,
        onNotifications = null,
        showNotificationBadge = false;

  @override
  Widget build(BuildContext context) {
    return _isDashboard ? _buildDashboardHeader() : _buildSecondaryHeader(context);
  }

  Widget _buildDashboardHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          A11yTap(
            label: 'Salute, ir al inicio',
            onTap: onLogoTap,
            child: const Text(
              'Salute',
              style: TextStyle(
                color: SaluteColors.primaryGreen,
                fontSize: DsFontSize.h4,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              A11yTap(
                label: showNotificationBadge
                    ? 'Notificaciones, hay avisos nuevos'
                    : 'Notificaciones',
                onTap: onNotifications,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: SaluteColors.primaryGreen,
                    size: 24,
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 5,
                child: showNotificationBadge
                    ? Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: SaluteColors.primaryGreen,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: SaluteColors.primaryGreen.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          A11yTap(
            label: 'Volver',
            onTap: onBack ?? () => Navigator.maybePop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SaluteColors.primaryGreen.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: SaluteColors.primaryGreen,
                size: 22,
              ),
            ),
          ),
          Expanded(
            child: Text(
              title ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SaluteColors.primaryGreen,
                fontSize: DsFontSize.h4,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (onSettings != null)
            A11yTap(
              label: 'Configuración',
              onTap: onSettings,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SaluteColors.primaryGreen.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SaluteColors.primaryGreen.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.settings_outlined,
                  color: SaluteColors.primaryGreen,
                  size: 20,
                ),
              ),
            )
          else
            const SizedBox(width: 48, height: 48), // mismo ancho que el botón: el título queda centrado
        ],
      ),
    );
  }
}