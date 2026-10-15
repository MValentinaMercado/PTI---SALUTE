import 'dart:async';

import 'package:flutter/material.dart';
import 'package:saluteapp/profile/ai.dart';
import 'package:saluteapp/components/navbar.dart';
import 'package:saluteapp/profile/diario.dart';
import 'package:saluteapp/home_screen.dart';
import 'package:saluteapp/map_screen.dart';
import 'package:saluteapp/profile/my_profile_screen.dart';
import 'package:saluteapp/profile/orden.dart';
import 'package:saluteapp/core/active_profile_controller.dart';
import 'package:saluteapp/core/app_navigator.dart';
import 'package:saluteapp/core/auth_service.dart';
import 'package:saluteapp/core/biometric_service.dart';
import 'package:saluteapp/auth/biometric_lock_screen.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/services/medication_reminder_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';

/// Shell que contiene todas las pantallas principales de la app.
/// Usa [IndexedStack] para mantener el estado de cada pestaña.
class SaluteShell extends StatefulWidget {
  const SaluteShell({super.key});

  @override
  State<SaluteShell> createState() => _SaluteShellState();
}

class _SaluteShellState extends State<SaluteShell> with WidgetsBindingObserver {
  int? _selectedIndex;
  StreamSubscription<List<FamilyProfile>>? _profilesSub;

  // Protección del Diario: null mientras se carga la preferencia,
  // true/false según si el usuario activó "Proteger el Diario con huella"
  // en Configuración. _diarioUnlocked se resetea cada vez que se sale de
  // la pestaña, así vuelve a pedir la huella en la próxima entrada.
  bool? _diarioLockEnabled;
  bool _diarioUnlocked = false;

  @override
  void initState() {
    super.initState();
    // BUG-006: mantenemos el perfil activo sincronizado con la lista real
    // de perfiles mientras el Shell esté vivo (o sea, mientras haya
    // sesión). Así, si el perfil activo se borra, o es la primera vez
    // que entra el usuario, `ActiveProfileController` cae automáticamente
    // al perfil propio en vez de dejar a la app sin ningún destinatario.
    _profilesSub = ProfileService.instance.watchProfiles().listen(
          (profiles) => ActiveProfileController.instance.ensureValid(profiles),
    );
    _loadDiarioLockPreference();

    // Alertas de medicación: al tocar una notificación se abre la
    // pantalla de toma, y cada vez que se entra a la app se vuelven a
    // armar las alarmas (así la ventana de tratamientos con duración
    // siempre queda cubierta y se recogen cambios hechos desde otro
    // dispositivo).
    WidgetsBinding.instance.addObserver(this);
    MedicationReminderService.instance.attach(appNavigatorKey);
    MedicationReminderService.instance.rescheduleAll(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MedicationReminderService.instance.rescheduleAll();
    }
  }

  Future<void> _loadDiarioLockPreference() async {
    final uid = AuthService.instance.currentUser?.uid;
    final supported = uid == null ? false : await BiometricService.instance.isDeviceSupported();
    final enabled = (uid == null || !supported)
        ? false
        : await BiometricService.instance.isEnabledFor('diario_lock', uid);
    if (!mounted) return;
    setState(() => _diarioLockEnabled = enabled);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MedicationReminderService.instance.detach();
    _profilesSub?.cancel();
    super.dispose();
  }

  // Agregar pantallas adicionales (Agenda, Órdenes, Mapa, Chat) aquí
  // cuando estén implementadas.
  //
  // BUG-007: antes, cuando el Diario estaba bloqueado, este índice 0
  // devolvía directamente un BiometricLockScreen. Como IndexedStack
  // mantiene TODOS los widgets de _pages montados aunque no se estén
  // mostrando, ese BiometricLockScreen se montaba (y disparaba el prompt
  // de huella solo, ver su initState) apenas el usuario tocaba CUALQUIER
  // pestaña, no solo Diario. Acá dejamos un placeholder inofensivo
  // mientras esté bloqueado, y el candado real solo se agrega al árbol
  // en build() cuando la pestaña Diario está efectivamente seleccionada
  // (ver el Stack más abajo).
  List<Widget> get _pages => [
    (_diarioLockEnabled == true && !_diarioUnlocked)
        ? const SizedBox.shrink()
        : DiarioScreen(onBackToDashboard: _goHome),      // 0 – DIARIO
    OrdenScreen(onBackToDashboard: _goHome),           // 1 - ORDENES
    SaluteMapScreen(onBackToDashboard: _goHome),        // 2 - MAPA (central)
    SaluteAIScreen(onBackToDashboard: _goHome),         // 3 - CHAT
    MyProfileScreen(onBackToDashboard: _goHome),        // 4 - PERFIL (perfil propio)
  ];

  void _onNavTap(int index) {
    setState(() {
      if (_selectedIndex == 0 && index != 0) {
        // Al salir del Diario, se vuelve a pedir la huella la próxima vez.
        _diarioUnlocked = false;
      }
      _selectedIndex = index;
    });
  }

  void _goHome() {
    setState(() {
      if (_selectedIndex == 0) {
        _diarioUnlocked = false;
      }
      _selectedIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showDashboard = _selectedIndex == null;

    return Scaffold(
      body: showDashboard
          ? SaluteHomeScreen(onLogoTap: _goHome)
          : Stack(
        children: [
          IndexedStack(
            index: _selectedIndex!,
            children: _pages,
          ),
          // Solo se monta (y solo entonces dispara el prompt de huella)
          // cuando la pestaña Diario está realmente seleccionada.
          if (_selectedIndex == 0 && _diarioLockEnabled == true && !_diarioUnlocked)
            BiometricLockScreen(
              title: 'Diario protegido',
              subtitle: 'Confirmá tu huella para ver tus datos',
              authReason: 'Confirmá tu huella para entrar al Diario',
              cancelLabel: 'Volver al inicio',
              onCancel: _goHome,
              onUnlocked: () => setState(() => _diarioUnlocked = true),
            ),
        ],
      ),
      bottomNavigationBar: SaluteNavBar(
        // -1 cuando estamos en el dashboard: ningún ítem activo
        selectedIndex: _selectedIndex ?? -1,
        onDestinationSelected: _onNavTap,
      ),
    );
  }
}