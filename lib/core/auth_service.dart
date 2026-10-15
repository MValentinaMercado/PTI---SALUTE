import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:saluteapp/core/password_policy.dart';
import 'package:saluteapp/core/secure_credentials_service.dart';
import 'package:saluteapp/core/services/account_deletion_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';

/// En qué parte del formulario debe mostrarse el error.
enum AuthField { general, email, password }

class AuthFailure implements Exception {
  /// Mensaje pensado para el usuario.
  final String message;

  /// Dónde mostrarlo (debajo del campo que corresponde, o como aviso general).
  final AuthField field;

  /// Detalle técnico que NO se le muestra al usuario: va al archivo de log.
  final String? technicalDetail;

  /// El usuario canceló a propósito (ej. cerró el selector de Google):
  /// no es un error y no se le muestra nada.
  final bool cancelled;

  AuthFailure(
    this.message, {
    this.field = AuthField.general,
    this.technicalDetail,
    this.cancelled = false,
  });

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _googleInitialized = false;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> _initializeGoogleSignIn() async {
    if (_googleInitialized) {
      return;
    }

    await _googleSignIn.initialize(
      serverClientId:
      '368446797278-oueuemkb8rq4bdrunmo03k5frv9ft9d9.apps.googleusercontent.com',
    );

    _googleInitialized = true;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _failureFor(e.code);
    }
  }

  Future<UserCredential> register({
    required String name,
    required String email,
    required String password,
    String lastName = '',
    String? termsVersion,
  }) async {
    final policyError = PasswordPolicy.validate(password);
    if (policyError != null) throw AuthFailure(policyError);
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw AuthFailure(
          'No pudimos crear tu cuenta. Intentá de nuevo.',
          technicalDetail: 'createUserWithEmailAndPassword devolvió user == null.',
        );
      }

      final cleanName = name.trim();
      final cleanLastName = lastName.trim();
      final cleanEmail = email.trim();
      // displayName de Firebase Auth se sigue completando para que el
      // nombre no quede vacío en pantallas que todavía no leen del
      // perfil (ej. la consola de Firebase); la fuente de verdad para
      // la UI de la app es el perfil propio en Firestore (ver
      // ProfileService.watchSelfProfile).
      final fullDisplayName = cleanLastName.isEmpty ? cleanName : '$cleanName $cleanLastName';

      await user.updateDisplayName(fullDisplayName);

      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': fullDisplayName,
        'email': cleanEmail,
        'createdAt': FieldValue.serverTimestamp(),
        if (termsVersion != null) ...{
          'termsAcceptedAt': FieldValue.serverTimestamp(),
          'termsVersion': termsVersion,
        },
      });

      await ProfileService.instance.ensureSelfProfile(
        uid: user.uid,
        name: cleanName,
        lastName: cleanLastName,
        username: cleanName,
      );

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _failureFor(e.code);
    }
  }

  /// true si la cuenta actual puede iniciar sesión con email+contraseña
  /// (se registró así, o ya vinculó una contraseña antes). Entrar con
  /// Google NO agrega esto por sí solo: Google nunca le da a Firebase
  /// una contraseña, así que una cuenta que solo entró con Google no
  /// tiene ninguna que verificar.
  bool get hasPasswordProvider {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.providerData.any((p) => p.providerId == 'password');
  }

  /// Para activar "Login rápido con huella" desde Configuración.
  ///
  /// - Si la cuenta ya tiene contraseña (se registró con email/contraseña,
  ///   o ya pasó por acá antes), la confirmamos reautenticando: así nos
  ///   aseguramos de que quien está activando esto sabe la contraseña real.
  /// - Si la cuenta entró con Google y todavía no tiene contraseña propia,
  ///   NO hay nada que verificar (Google nunca creó una), así que en vez
  ///   de intentar un signIn que va a fallar siempre, se la CREAMOS ahora
  ///   vinculándola a la cuenta. A partir de acá la cuenta puede entrar
  ///   tanto con Google como con email+contraseña (y con huella, usando
  ///   esa contraseña recién creada).
  Future<void> verifyOrSetPasswordForQuickLogin({
    required String email,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw AuthFailure('No hay una sesión activa.');
    }

    if (hasPasswordProvider) {
      try {
        await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      } on FirebaseAuthException catch (e) {
        throw _failureFor(e.code);
      }
      return;
    }

    final policyError = PasswordPolicy.validate(password);
    if (policyError != null) throw AuthFailure(policyError);

    try {
      final credential = EmailAuthProvider.credential(email: email.trim(), password: password);
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw AuthFailure(
          'Por seguridad, volvé a iniciar sesión con Google y probá de nuevo.',
        );
      }
      throw _failureFor(e.code);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(
        email: email.trim(),
      );
    } on FirebaseAuthException catch (e) {
      throw _failureFor(e.code);
    }
  }

  /// [isRegister] indica desde qué pantalla se llama:
  /// - `false` (Login): la cuenta de Google DEBE existir ya. Si es la
  ///   primera vez que ese email entra a la app, se deshace el alta
  ///   automática de Firebase y se avisa que no hay cuenta registrada.
  /// - `true` (Registro): la cuenta debe ser nueva. Si ese email ya
  ///   tiene cuenta, se avisa que inicie sesión en lugar de registrarse.
  /// Google manda el nombre y el apellido por separado en los claims
  /// `given_name`/`family_name` del ID token (JWT), pero el SDK de
  /// Firebase solo nos expone el `displayName` ya junto. Como el token
  /// ya fue validado por Firebase al crear la credencial, alcanza con
  /// leer su payload (no hace falta volver a verificarlo acá) para
  /// recuperar esos dos campos por separado.
  ({String? given, String? family}) _splitGoogleName(String idToken, String? displayName) {
    try {
      final parts = idToken.split('.');
      if (parts.length == 3) {
        final normalized = base64Url.normalize(parts[1]);
        final payload = jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
        final given = (payload['given_name'] as String?)?.trim();
        final family = (payload['family_name'] as String?)?.trim();
        if (given != null && given.isNotEmpty) {
          return (given: given, family: (family != null && family.isNotEmpty) ? family : null);
        }
      }
    } catch (_) {
      // Si el token no trae esos claims o no se puede parsear, caemos
      // al fallback de abajo.
    }

    // Fallback: partimos el displayName completo por el primer espacio.
    final full = displayName?.trim();
    if (full == null || full.isEmpty) return (given: null, family: null);
    final spaceIndex = full.indexOf(' ');
    if (spaceIndex == -1) return (given: full, family: null);
    return (given: full.substring(0, spaceIndex), family: full.substring(spaceIndex + 1).trim());
  }

  Future<UserCredential> signInWithGoogle({required bool isRegister, String? termsVersion}) async {
    try {
      await _initializeGoogleSignIn();

      final GoogleSignInAccount googleUser;

      try {
        googleUser = await _googleSignIn.authenticate();
      } on GoogleSignInException catch (e) {
        throw _googleFailure(e);
      }

      final GoogleSignInAuthentication googleAuth =
          googleUser.authentication;

      final idToken = googleAuth.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw AuthFailure(
          'No pudimos completar el acceso con Google. Intentá de nuevo.',
          technicalDetail: 'Google no devolvió un idToken válido.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      final userCredential = await _auth.signInWithCredential(
        credential,
      );

      final user = userCredential.user;

      if (user == null) {
        throw AuthFailure(
          'No pudimos completar el acceso con Google. Intentá de nuevo.',
          technicalDetail: 'signInWithCredential devolvió un UserCredential sin user.',
        );
      }

      final isNewUser =
          userCredential.additionalUserInfo?.isNewUser ?? false;

// Login con Google, pero no existía cuenta previa con ese email:
// Firebase ya la creó sola, así que la deshacemos y avisamos.
      if (!isRegister && isNewUser) {
        try {
          await user.delete();
        } catch (_) {}
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        throw AuthFailure(
          'No tenemos una cuenta registrada con ese email. '
              'Registrate primero con "Registrarse ahora".',
        );
      }

// Registro con Google, pero ese email ya tenía cuenta creada.
      if (isRegister && !isNewUser) {
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        throw AuthFailure(
          'Ya existe una cuenta con ese email. Iniciá sesión con Google '
              'en vez de registrarte.',
        );
      }

      final fullName = (user.displayName?.trim().isNotEmpty ?? false)
          ? user.displayName!.trim()
          : (user.email?.split('@').first ?? 'Usuario');

      final splitName = _splitGoogleName(idToken, user.displayName);
      final firstName = splitName.given ?? fullName;
      final lastNameFromGoogle = splitName.family ?? '';

      // Solo completamos estos datos la primera vez que se crea la
      // cuenta (isNewUser). En logins posteriores NO los volvemos a
      // escribir: así, si ya editaste tu nombre a mano desde "Perfil",
      // volver a entrar con Google no te lo pisa.
      //
      // Nota sobre la contraseña: este flujo de Google nunca la lee ni
      // la escribe —vive aparte, en Firebase Auth, y el SDK de Google
      // Sign-In no tiene acceso a ella—, así que la contraseña original
      // de la cuenta (si la creaste con email/contraseña) nunca se ve
      // afectada por iniciar sesión con Google.
      if (isNewUser) {
        await _db.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': fullName,
          'email': user.email ?? '',
          'photoUrl': user.photoURL,
          'createdAt': FieldValue.serverTimestamp(),
          if (termsVersion != null) ...{
            'termsAcceptedAt': FieldValue.serverTimestamp(),
            'termsVersion': termsVersion,
          },
        });

        // El nombre de usuario (cómo te llama el resto de la app) arranca
        // igual al nombre de pila que dio Google; se puede cambiar
        // después desde "Perfil" > "Editar perfil".
        await ProfileService.instance.ensureSelfProfile(
          uid: user.uid,
          name: firstName,
          lastName: lastNameFromGoogle,
          username: firstName,
        );
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _failureFor(e.code);
    } on AuthFailure {
      rethrow;
    } on GoogleSignInException catch (e) {
      throw _googleFailure(e);
    } catch (e) {
      throw AuthFailure(
        'No pudimos completar el acceso con Google. Intentá de nuevo.',
        technicalDetail: 'Error inesperado en signInWithGoogle: $e',
      );
    }
  }

  /// Traduce los códigos de [GoogleSignInException] (paquete
  /// google_sign_in v7). Lo que el usuario puede resolver se le explica;
  /// los problemas de configuración van solo al log.
  ///
  /// Si ves "canceled" apenas elegís la cuenta (sin llegar a cerrar el
  /// selector), casi siempre NO es un cancel real: revisá que el SHA-1
  /// (debug y release) esté cargado en Firebase Console y que el
  /// google-services.json / GoogleService-Info.plist estén actualizados.
  /// Por eso las cancelaciones también quedan anotadas en el log.
  AuthFailure _googleFailure(GoogleSignInException e) {
    const generic = 'No pudimos completar el acceso con Google. Intentá de nuevo.';
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return AuthFailure(
          'Cancelaste el inicio de sesión con Google.',
          cancelled: true,
          technicalDetail:
              'Google Sign-In cancelado ($e). Si ocurre apenas se elige la cuenta, revisar SHA-1 / google-services.json.',
        );
      case GoogleSignInExceptionCode.interrupted:
        return AuthFailure('Se interrumpió el acceso con Google. Probá de nuevo.');
      case GoogleSignInExceptionCode.clientConfigurationError:
        return AuthFailure(
          'Google no está disponible en este momento. Probá más tarde.',
          technicalDetail: 'Google Sign-In mal configurado (revisar SHA-1 / client ID): $e',
        );
      case GoogleSignInExceptionCode.providerConfigurationError:
        return AuthFailure(
          'Google no está disponible en este momento. Probá más tarde.',
          technicalDetail: 'Proveedor de Google Sign-In no disponible: $e',
        );
      case GoogleSignInExceptionCode.uiUnavailable:
        return AuthFailure('No se pudo abrir la ventana de Google. Probá de nuevo.');
      case GoogleSignInExceptionCode.userMismatch:
        return AuthFailure('Hubo un problema con la cuenta seleccionada. Volvé a intentar.');
      default:
        return AuthFailure(generic, technicalDetail: 'Google Sign-In: ${e.code.name} ($e)');
    }
  }

  // ── Métodos de acceso vinculados ──────────────────────────────────────────

  bool get hasGoogleProvider {
    final user = _auth.currentUser;
    return user != null && user.providerData.any((p) => p.providerId == 'google.com');
  }

  /// Stream que se actualiza al vincular/desvincular métodos de acceso.
  Stream<User?> get userChanges => _auth.userChanges();

  /// Confirma la identidad con la contraseña actual (operaciones sensibles).
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) throw AuthFailure('No hay una sesión activa.');
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw AuthFailure('La contraseña no es correcta.');
      }
      throw _failureFor(e.code);
    }
  }

  /// Confirma la identidad con Google (cuentas sin contraseña).
  Future<void> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw AuthFailure('No hay una sesión activa.');
    final credential = await _googleCredential();
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _failureFor(e.code);
    }
  }

  Future<AuthCredential> _googleCredential() async {
    await _initializeGoogleSignIn();
    final GoogleSignInAccount googleUser;
    try {
      googleUser = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      throw _googleFailure(e);
    }
    final idToken = googleUser.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw AuthFailure(
        'No pudimos completar el acceso con Google. Intentá de nuevo.',
        technicalDetail: 'Google no devolvió un idToken válido.',
      );
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  /// Cambia la contraseña. Si la cuenta todavía no tiene una (entró solo
  /// con Google) la CREA y la vincula, sin pedir contraseña actual.
  Future<void> changePassword({String? currentPassword, required String newPassword}) async {
    final user = _auth.currentUser;
    if (user == null) throw AuthFailure('No hay una sesión activa.');
    final policyError = PasswordPolicy.validate(newPassword);
    if (policyError != null) throw AuthFailure(policyError);

    if (hasPasswordProvider) {
      if (currentPassword == null || currentPassword.isEmpty) {
        throw AuthFailure('Ingresá tu contraseña actual.');
      }
      await reauthenticateWithPassword(currentPassword);
      try {
        await user.updatePassword(newPassword);
      } on FirebaseAuthException catch (e) {
        throw _failureFor(e.code);
      }
    } else {
      final email = user.email;
      if (email == null) throw AuthFailure('Tu cuenta no tiene un correo asociado.');
      try {
        await user.linkWithCredential(EmailAuthProvider.credential(email: email, password: newPassword));
      } on FirebaseAuthException catch (e) {
        throw _failureFor(e.code);
      }
    }

    // Si el login rápido con huella estaba activo para esta cuenta, la
    // contraseña guardada quedó vieja: se actualiza para que siga andando.
    try {
      final saved = await SecureCredentialsService.instance.read();
      if (saved != null && saved.uid == user.uid) {
        await SecureCredentialsService.instance.save(uid: user.uid, email: saved.email, password: newPassword);
      }
    } catch (_) {}
  }

  Future<void> linkGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw AuthFailure('No hay una sesión activa.');
    final credential = await _googleCredential();
    try {
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _failureFor(e.code);
    }
  }

  /// Solo se puede desvincular Google si queda otro método para entrar.
  Future<void> unlinkGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw AuthFailure('No hay una sesión activa.');
    if (user.providerData.length < 2) {
      throw AuthFailure('Es tu único método de acceso. Creá una contraseña antes de desvincularlo.');
    }
    try {
      await user.unlink('google.com');
    } on FirebaseAuthException catch (e) {
      throw _failureFor(e.code);
    }
  }

  /// true mientras se borra la cuenta. AuthGate lo escucha y, mientras está
  /// activo, muestra una pantalla "Eliminando tu cuenta…" en lugar de la
  /// app (así no quedan pantallas ni listeners leyendo datos que se están
  /// borrando) y, al terminar, cae directo en el login.
  final ValueNotifier<bool> deletingAccount = ValueNotifier<bool>(false);

  /// Paso 1 de eliminar la cuenta (rápido, con la pantalla a la vista):
  /// comprueba que se pueda y confirma la identidad (contraseña o Google).
  /// No borra nada. Si algo impide continuar, lanza [AuthFailure].
  Future<void> verifyBeforeDeletion({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) throw AuthFailure('No hay una sesión activa.');

    final blocked = await AccountDeletionService.instance.blockingReason(user.uid);
    if (blocked != null) throw AuthFailure(blocked);

    if (hasPasswordProvider) {
      await reauthenticateWithPassword(password ?? '');
    } else if (hasGoogleProvider) {
      await reauthenticateWithGoogle();
    }
  }

  /// Paso 2: borra los datos, la cuenta y lo guardado en el dispositivo, y
  /// cierra la sesión (Google + Firebase, igual que "Cerrar sesión").
  /// Llamar después de [verifyBeforeDeletion]; no depende de ninguna pantalla.
  Future<void> deleteAccountNow() async {
    final user = _auth.currentUser;
    if (user == null) throw AuthFailure('No hay una sesión activa.');

    await AccountDeletionService.instance.deleteAllUserData(user.uid);

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw _failureFor(e.code);
    }

    // `user.delete()` no siempre hace que `authStateChanges` emita null, por
    // eso se cierra la sesión explícitamente. En paralelo con la limpieza
    // local para no sumar esperas. Si falla porque el usuario ya no existe,
    // da igual.
    await Future.wait([
      AccountDeletionService.instance.clearLocalData(),
      signOut().catchError((_) {}),
    ]);
  }

  /// Todo junto (verificación + borrado), para quien no necesite pantalla
  /// intermedia.
  Future<void> deleteAccount({String? password}) async {
    await verifyBeforeDeletion(password: password);
    await deleteAccountNow();
  }

  Future<void> signOut() async {
    try {
      await _initializeGoogleSignIn();
      await _googleSignIn.signOut();
    } catch (_) {}

    await _auth.signOut();
  }

  /// Convierte un código de FirebaseAuthException en un [AuthFailure]:
  /// mensaje claro para el usuario, indicando en qué campo mostrarlo.
  /// Los códigos que el usuario no puede resolver se anotan en el log.
  AuthFailure _failureFor(String code) {
    switch (code) {
      case 'invalid-email':
        return AuthFailure('El email no tiene un formato válido.', field: AuthField.email);
      case 'user-disabled':
        return AuthFailure('Esta cuenta fue deshabilitada.');
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return AuthFailure('Email o contraseña incorrectos.');
      case 'email-already-in-use':
        return AuthFailure('Ya existe una cuenta con ese email.', field: AuthField.email);
      case 'weak-password':
        return AuthFailure(
          'La contraseña es demasiado débil. ${PasswordPolicy.hint}',
          field: AuthField.password,
        );
      case 'requires-recent-login':
        return AuthFailure('Por seguridad, volvé a iniciar sesión y probá de nuevo.');
      case 'credential-already-in-use':
        return AuthFailure('Esa cuenta de Google ya está vinculada a otro usuario de SALUTE.');
      case 'provider-already-linked':
        return AuthFailure('Ese método de acceso ya está vinculado.');
      case 'network-request-failed':
        return AuthFailure('Sin conexión. Revisá tu internet e intentá de nuevo.');
      case 'too-many-requests':
        return AuthFailure('Demasiados intentos. Probá de nuevo en unos minutos.');
      default:
        return AuthFailure(
          'Ocurrió un error inesperado. Intentá de nuevo.',
          technicalDetail: 'FirebaseAuthException: $code',
        );
    }
  }
}
