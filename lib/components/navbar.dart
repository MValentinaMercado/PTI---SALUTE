import 'package:saluteapp/components/a11y_tap.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/components/design_system.dart';

/// Navbar de 5 ítems con soporte para [selectedIndex] == -1,
/// que indica que ningún ítem está activo (estamos en el Dashboard).
class SaluteNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const SaluteNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[100]!, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              _NavItem(
                icon:       Icons.calendar_today_outlined,
                activeIcon: Icons.calendar_today,
                label: 'DIARIO',
                index: 0,
                selectedIndex: selectedIndex,
                onTap: onDestinationSelected,
              ),
              _NavItem(
                icon:       Icons.assignment_outlined,
                activeIcon: Icons.assignment,
                label: 'ORDENES',
                index: 1,
                selectedIndex: selectedIndex,
                onTap: onDestinationSelected,
              ),
              _MapButton(
                isActive: selectedIndex == 2,
                onTap: () => onDestinationSelected(2),
              ),
              _NavItem(
                icon:       Icons.chat_bubble_outline,
                activeIcon: Icons.chat_bubble,
                label: 'CHAT',
                index: 3,
                selectedIndex: selectedIndex,
                onTap: onDestinationSelected,
              ),
              _NavItem(
                icon:       Icons.person_outline,
                activeIcon: Icons.person,
                label: 'PERFIL',
                index: 4,
                selectedIndex: selectedIndex,
                onTap: onDestinationSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Ítem genérico ─────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = selectedIndex == index;

    return Expanded(
      child: A11yTap(
        label: label.substring(0, 1) + label.substring(1).toLowerCase(),
        selected: active,
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: active ? 52 : 44,
              height: 36,
              decoration: BoxDecoration(
                color: active
                    ? SaluteColors.primaryGreen
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: SaluteColors.primaryGreen.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                active ? activeIcon : icon,
                size: 22,
                color: active ? Colors.white : SaluteColors.textMuted,
              ),
            ),
            const SizedBox(height: 5),
             Text(
               label,
               style: TextStyle(
                 fontSize: DsFontSize.xs,
                 fontWeight: FontWeight.w700,
                 letterSpacing: 0.4,
                 color: active
                     ? SaluteColors.primaryGreen
                     : SaluteColors.textMuted,
               ),
             ),
          ],
        ),
      ),
    );
  }
}

// ── Botón central del mapa ────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _MapButton({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: A11yTap(
        label: 'Mapa de servicios de salud',
        selected: isActive,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: SaluteColors.primaryGreen,
              shape: BoxShape.circle,
              border: isActive
                  ? Border.all(
                      color: SaluteColors.primaryGreen,
                      width: 3,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: SaluteColors.primaryGreen.withValues(
                    alpha: isActive ? 0.35 : 0.25,
                  ),
                  blurRadius: isActive ? 12 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              isActive ? Icons.map : Icons.map_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}