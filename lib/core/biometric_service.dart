import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Maneja el desbloqueo por huella/Face ID.
///
/// Se usa para dos cosas independientes:
/// 1. Login rápido: volver a entrar a la cuenta sin tipear email/contraseña
///    (ver [SecureCredentialsService], que guarda las credenciales).
/// 2. Proteger secciones sensibles ya adentro de la app (ej. el Diario),
///    pidiendo la huella cada vez que se entra, sin importar cómo se
///    inició sesión.
class BiometricService {
  BiometricService._();

  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  static String _prefKey(String feature, String uid) => 'biometric_${feature}_$uid';

  /// true si el hardware del equipo soporta biometría/Face ID Y el usuario
  /// tiene al menos una huella o rostro cargado en el sistema operativo.
  Future<bool> isDeviceSupported() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final deviceSupported = await _auth.isDeviceSupported();
      return canCheck && deviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Preferencia guardada por el usuario (por uid y por "feature", así
  /// login rápido y protección del Diario se activan/desactivan por
  /// separado). Ej: feature = 'quick_login' o feature = 'diario_lock'.
  Future<bool> isEnabledFor(String feature, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(feature, uid)) ?? false;
  }

  Future<void> setEnabledFor(String feature, String uid, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(feature, uid), enabled);
  }

  /// Dispara el prompt nativo de huella/Face ID.
  /// Devuelve true solo si el usuario se autenticó correctamente.
  Future<bool> authenticate({
    String reason = 'Confirmá tu identidad para continuar',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}