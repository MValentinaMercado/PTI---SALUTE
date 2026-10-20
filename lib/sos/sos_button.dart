import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:saluteapp/core/app_navigator.dart';
import 'package:saluteapp/core/services/app_settings_service.dart';
import 'package:saluteapp/sos/sos_controller.dart';

/// Color de emergencia (blanco sobre este rojo: contraste ~6,5:1).
const kSosRed = Color(0xFFB3261E);

/// Botón SOS global. Se monta UNA vez en `MaterialApp.builder`, por lo que
/// está en el mismo lugar (abajo a la izquierda) en todas las pantallas de la
/// app mientras haya sesión iniciada.
///
/// Activación deliberada, para evitar toques accidentales:
///  - mantener presionado 1,5 s (con anillo de progreso), o
///  - tocar una vez y confirmar en el diálogo (para quien no puede mantener
///    el dedo apretado o usa un lector de pantalla).
class SosOverlay extends StatelessWidget {
  final Widget child;
  const SosOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snap) {
            if (snap.data == null) return const SizedBox.shrink();
            return ListenableBuilder(
              listenable: Listenable.merge([SosController.instance, AppSettingsService.instance]),
              builder: (context, _) {
                final mq = MediaQuery.of(context);
                // Con "SOS fijo en el Inicio" el botón ya no es global: lo
                // dibuja SosDashboardSlot dentro del Inicio.
                if (AppSettingsService.instance.sosPinnedToDashboard) {
                  return const SizedBox.shrink();
                }
                // Se oculta con el teclado abierto y durante la emergencia
                // (ahí ya está la pantalla de emergencia).
                if (SosController.instance.isActive || mq.viewInsets.bottom > 0) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  left: 12,
                  bottom: mq.padding.bottom + 88,
                  child: const Material(
                    type: MaterialType.transparency,
                    child: SosButton(),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

/// Botón SOS fijo dentro del Inicio (dashboard). Solo se muestra si la
/// persona activó "SOS fijo en el Inicio" en Configuración; en ese caso el
/// botón global ([SosOverlay]) se oculta en el resto de las pantallas.
/// Va dentro de un Stack: no se mueve al hacer scroll.
class SosDashboardSlot extends StatelessWidget {
  const SosDashboardSlot({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([SosController.instance, AppSettingsService.instance]),
      builder: (context, _) {
        if (!AppSettingsService.instance.sosPinnedToDashboard ||
            SosController.instance.isActive) {
          return const SizedBox.shrink();
        }
        return const Positioned(
          left: 12,
          bottom: 16,
          child: Material(type: MaterialType.transparency, child: SosButton()),
        );
      },
    );
  }
}

class SosButton extends StatefulWidget {
  const SosButton({super.key});

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 1500);
  late final AnimationController _hold =
      AnimationController(vsync: this, duration: _holdDuration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) {
            _hold.value = 0;
            SosController.instance.activate();
          }
        });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  Future<void> _confirmAndActivate() async {
    final overlayContext = appNavigatorKey.currentState?.overlay?.context;
    if (overlayContext == null) return;
    final ok = await showDialog<bool>(
      context: overlayContext,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Pedir ayuda ahora?'),
        content: const Text(
          'Vamos a avisar a tu contacto de emergencia por mensaje, con tu '
          'ubicación, y vas a poder llamarlo.',
          style: TextStyle(fontSize: 18, height: 1.4),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 56), child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kSosRed),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sí, pedir ayuda',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ),
          ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 56), child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No, cancelar', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
    if (ok == true) SosController.instance.activate();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: 'S O S. Pedir ayuda de emergencia',
      hint: 'Tocá dos veces para confirmar, o mantené presionado para activar directamente',
      onTap: _confirmAndActivate,
      onLongPress: () => SosController.instance.activate(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _confirmAndActivate,
        onLongPressStart: (_) => _hold.forward(from: 0),
        onLongPressEnd: (_) {
          if (_hold.status != AnimationStatus.completed) _hold.reverse();
        },
        onLongPressCancel: () => _hold.reverse(),
        child: SizedBox(
          width: 68,
          height: 68,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: kSosRed,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x44000000), blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text(
                  'SOS',
                  maxLines: 1,
                  textScaler: TextScaler.noScaling, // el círculo es fijo
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _hold,
                builder: (_, __) => SizedBox(
                  width: 68,
                  height: 68,
                  child: CircularProgressIndicator(
                    value: _hold.value,
                    strokeWidth: 5,
                    color: Colors.white,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
