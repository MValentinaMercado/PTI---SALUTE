/// Política de contraseñas ÚNICA de la app. Registro, cambio de contraseña
/// y creación de contraseña para cuentas de Google usan estas reglas.
///
/// Nota: Firebase solo exige 6 caracteres del lado del servidor; estas
/// reglas más estrictas se aplican en la app. Las cuentas que ya tenían
/// una contraseña más corta siguen pudiendo entrar con normalidad.
class PasswordPolicy {
  PasswordPolicy._();

  static const int minLength = 8;

  static bool hasMinLength(String p) => p.length >= minLength;
  static bool hasUppercase(String p) => RegExp(r'[A-Z]').hasMatch(p);
  static bool hasNumber(String p) => RegExp(r'\d').hasMatch(p);

  static bool isValid(String p) => hasMinLength(p) && hasUppercase(p) && hasNumber(p);

  /// Texto corto para mostrar bajo los campos de contraseña.
  static const String hint = 'Mínimo 8 caracteres, una mayúscula y un número.';

  /// Devuelve el mensaje de error, o null si la contraseña es válida.
  static String? validate(String p) {
    if (!hasMinLength(p)) return 'La contraseña debe tener al menos $minLength caracteres.';
    if (!hasUppercase(p)) return 'La contraseña debe incluir al menos una letra mayúscula.';
    if (!hasNumber(p)) return 'La contraseña debe incluir al menos un número.';
    return null;
  }
}