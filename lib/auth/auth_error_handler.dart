import 'package:saluteapp/core/auth_service.dart';
import 'package:saluteapp/core/services/error_log_service.dart';

/// Mensaje para errores inesperados: el detalle va al log, no al usuario.
const kGenericErrorMessage = 'Algo salió mal de nuestro lado. Intentá de nuevo en unos minutos.';

/// Dónde mostrar un error en una pantalla de acceso.
class AuthUiError {
  final String? general;
  final String? email;
  final String? password;
  const AuthUiError({this.general, this.email, this.password});
}

/// Decide qué ve el usuario y qué queda solo en el log:
///  - [AuthFailure] con mensaje claro → se muestra en el lugar que corresponde.
///  - Si además trae `technicalDetail` → ese detalle se anota en el log.
///  - Cancelación voluntaria → no se muestra nada.
///  - Cualquier otro error → mensaje genérico amable + detalle al log.
AuthUiError handleAuthError(Object error, StackTrace stack, {required String window}) {
  final log = ErrorLog.instance;
  if (error is AuthFailure) {
    final detail = error.technicalDetail;
    if (detail != null) log.record(window: window, error: detail, stack: stack);
    if (error.cancelled) return const AuthUiError();
    switch (error.field) {
      case AuthField.email:
        return AuthUiError(email: error.message);
      case AuthField.password:
        return AuthUiError(password: error.message);
      case AuthField.general:
        return AuthUiError(general: error.message);
    }
  }
  log.record(window: window, error: error, stack: stack);
  return const AuthUiError(general: kGenericErrorMessage);
}

/// Versión corta para pantallas que muestran el error como un solo texto
/// (SnackBar o diálogo): devuelve el mensaje para el usuario y manda el
/// detalle técnico al log.
String userMessageFor(
  Object error,
  StackTrace stack, {
  required String window,
  String fallback = kGenericErrorMessage,
}) {
  if (error is AuthFailure) {
    final detail = error.technicalDetail;
    if (detail != null) ErrorLog.instance.record(window: window, error: detail, stack: stack);
    return error.message;
  }
  ErrorLog.instance.record(window: window, error: error, stack: stack);
  return fallback;
}
