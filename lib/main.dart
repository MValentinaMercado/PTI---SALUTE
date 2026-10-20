import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'core/auth_service.dart';
import 'core/services/profile_service.dart';
import 'core/active_profile_controller.dart';
import 'core/app_navigator.dart';
import 'core/accessibility_controller.dart';
import 'core/services/app_settings_service.dart';
import 'sos/sos_button.dart';
import 'core/services/local_alarm_service.dart';
import 'core/services/error_log_service.dart';
import 'auth/login.dart';
import 'core/shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Errores no capturados -> archivo de log (ver ErrorLog).
  ErrorLog.installGlobalHandlers();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Permite probar el flujo UI sin bloquear la app si Firebase no esta listo.
    debugPrint('Firebase init skipped for local UI testing: $e');
    ErrorLog.instance.record(
      window: 'Arranque',
      error: 'Firebase.initializeApp falló: $e',
    );
  }
  try {
    await LocalAlarmService.instance.init();
  } catch (e) {
    // No bloqueamos el arranque de la app si falla (ej: permisos
    // denegados). Las alarmas simplemente no se van a programar hasta
    // que el usuario las habilite y se reintente en el próximo uso.
    debugPrint('LocalAlarmService init falló: $e');
    ErrorLog.instance.record(
      window: 'Arranque',
      error: 'LocalAlarmService.init falló: $e',
    );
  }
  // Preferencias de accesibilidad (tamaño de texto, contraste, voz) antes del
  // primer frame, así la app no "salta" de tamaño al abrirse.
  await AccessibilityController.instance.load();
  // Ajustes de Configuración (notificaciones, ubicación).
  await AppSettingsService.instance.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const _seed = Color(0xFF1A5C3A);

  /// Tema base. En alto contraste: esquema con `contrastLevel` máximo,
  /// texto negro, bordes de campos más gruesos y botones con borde.
  static ThemeData _buildTheme({required bool highContrast}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
      contrastLevel: highContrast ? 1.0 : 0.0,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      textTheme: highContrast
          ? ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              fontFamily: 'Roboto',
            ).textTheme.apply(
              bodyColor: Colors.black,
              displayColor: Colors.black,
            )
          : null,
      dividerTheme: DividerThemeData(
        color: highContrast ? Colors.black54 : null,
      ),
      inputDecorationTheme: highContrast
          ? InputDecorationTheme(
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black87, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black, width: 2.5),
              ),
            )
          : null,
      // Todos los avisos (SnackBar) de la app: flotantes, redondeados y
      // con el mismo estilo.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: highContrast ? Colors.black : const Color(0xFF2B2F2D),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          height: 1.35,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a11y = AccessibilityController.instance;
    // La app entera se reconstruye cuando cambia una preferencia de
    // accesibilidad (tamaño de texto, contraste).
    return ListenableBuilder(
      listenable: a11y,
      builder: (context, _) => MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'Salute',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(highContrast: a11y.highContrast),
        // Si el teléfono tiene activado "alto contraste", se respeta aunque
        // la preferencia de la app esté apagada.
        highContrastTheme: _buildTheme(highContrast: true),
        // Texto: escala del sistema × escala de la app, con tope de 200 %.
        builder: (context, child) => MediaQuery(
          data: a11y.applyTo(MediaQuery.of(context)),
          // Botón SOS global: mismo lugar en todas las pantallas.
          child: SosOverlay(child: child ?? const SizedBox.shrink()),
        ),
        // AuthGate decide si mostrar Login o el Shell según haya sesión activa.
        home: const AuthGate(),
        routes: {'/home': (context) => const SaluteShell()},
      ),
    );
  }
}

/// Escucha el estado de autenticación de Firebase y navega
/// automáticamente entre LoginPage y SaluteShell.
/// Esto permite que la sesión persista entre aperturas de la app.
///
/// BUG-001: además de navegar, garantiza que el usuario logueado tenga
/// su propio perfil (`isSelf: true`) en `profiles` antes de mostrar el
/// Shell. `AuthService.register` ya lo crea para cuentas nuevas, pero
/// este chequeo es el que cubre cuentas que se crearon antes de que
/// existiera este concepto (ej: Valentina) — sin este paso, esas cuentas
/// seguirían sin aparecer en "Mi familia".
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _ensuredForUid;
  Future<void>? _ensureFuture;

  Future<void> _ensureSelfProfile(User user) {
    if (_ensuredForUid == user.uid && _ensureFuture != null) {
      return _ensureFuture!;
    }
    _ensuredForUid = user.uid;
    _ensureFuture = ProfileService.instance.ensureSelfProfile(
      uid: user.uid,
      name: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : 'Yo',
    );
    return _ensureFuture!;
  }

  @override
  Widget build(BuildContext context) {
    // Mientras se elimina la cuenta se muestra una pantalla de espera en vez
    // de la app (ver AuthService.deletingAccount).
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.instance.deletingAccount,
      builder: (context, deleting, _) =>
          deleting ? const _DeletingAccountScreen() : _buildAuthStream(),
    );
  }

  Widget _buildAuthStream() {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          _ensuredForUid = null;
          _ensureFuture = null;
          // Sin esto, si Valentina cierra sesión y Juan entra con su
          // cuenta en el mismo proceso, Juan podría arrancar viendo el
          // perfil activo que había quedado seteado para Valentina.
          ActiveProfileController.instance.clear();
          return const LoginPage();
        }
        return FutureBuilder<void>(
          future: _ensureSelfProfile(user),
          builder: (context, ensureSnap) {
            if (ensureSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            // Si falló la verificación (ej: sin conexión), no bloqueamos
            // el acceso a la app; el usuario puede seguir usándola y el
            // chequeo se reintenta en la próxima apertura.
            return const SaluteShell();
          },
        );
      },
    );
  }
}

/// Pantalla de espera mientras se borra la cuenta.
class _DeletingAccountScreen extends StatelessWidget {
  const _DeletingAccountScreen();

  @override
  Widget build(BuildContext context) {
    return const PopScope(
      canPop: false,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 24),
                Text(
                  'Eliminando tu cuenta…',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 8),
                Text(
                  'Estamos borrando tus datos. Puede tardar unos segundos; no cierres la app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
