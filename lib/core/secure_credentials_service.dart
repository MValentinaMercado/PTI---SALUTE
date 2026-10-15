import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda el email y contraseña del último login exitoso, cifrados en el
/// almacenamiento seguro del sistema (Keychain en iOS, Keystore/
/// EncryptedSharedPreferences en Android). Se usan únicamente para poder
/// volver a iniciar sesión con la huella sin volver a tipear nada.
///
/// Nota de seguridad: esto vive protegido por el sistema operativo, pero
/// quien tenga el equipo desbloqueado y la huella registrada podrá
/// ingresar a la cuenta. Por eso el usuario tiene que activarlo a
/// propósito (checkbox en el login) y puede desactivarlo cuando quiera.
class SecureCredentialsService {
  SecureCredentialsService._();

  static final SecureCredentialsService instance = SecureCredentialsService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _uidKey = 'quick_login_uid';
  static const _emailKey = 'quick_login_email';
  static const _passwordKey = 'quick_login_password';

  /// Solo puede haber una cuenta con login rápido activo por equipo (así
  /// funciona el botón de huella en el login, que todavía no sabe qué
  /// usuario va a entrar). Por eso guardamos también el [uid] al que
  /// pertenecen estas credenciales: nos sirve para que Configuración
  /// pueda distinguir "mi cuenta tiene esto activado" de "hay OTRA
  /// cuenta con esto activado en este equipo", en vez de asumir que
  /// cualquier credencial guardada es siempre la de la cuenta actual.
  Future<void> save({required String uid, required String email, required String password}) async {
    await _storage.write(key: _uidKey, value: uid);
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
  }

  /// Devuelve null si no hay credenciales guardadas.
  Future<({String uid, String email, String password})?> read() async {
    final uid = await _storage.read(key: _uidKey);
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    if (uid == null || email == null || password == null || email.isEmpty || password.isEmpty) {
      return null;
    }
    return (uid: uid, email: email, password: password);
  }

  /// Para el botón "Ingresar con huella" del login: ahí todavía no hay
  /// sesión activa, así que no hay uid propio con el que comparar; solo
  /// nos interesa saber si hay *alguna* credencial guardada en el equipo.
  Future<bool> hasAnySavedCredentials() async {
    final email = await _storage.read(key: _emailKey);
    return email != null && email.isNotEmpty;
  }

  /// Para el switch de Configuración: true solo si lo guardado en este
  /// equipo pertenece a [uid] (la cuenta con la que estás logueado
  /// ahora). Antes esto miraba solo si había *algo* guardado, sin
  /// importar de qué cuenta era: si activabas login rápido con una
  /// cuenta y después entrabas con otra (ej. Google), el switch
  /// aparecía prendido igual, mostrando el estado de la cuenta vieja.
  Future<bool> hasSavedCredentialsFor(String uid) async {
    final saved = await read();
    return saved != null && saved.uid == uid;
  }

  Future<void> clear() async {
    await _storage.delete(key: _uidKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
  }
}