import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda si una cuenta ya vio (o salteó) el recorrido guiado inicial en
/// este teléfono. Se guarda por cuenta (uid): si en el mismo teléfono entra
/// otra persona, ve el recorrido la primera vez.
///
/// El recorrido se puede volver a abrir a mano desde Configuración; eso no
/// pasa por acá (siempre se muestra).
class OnboardingService {
  OnboardingService._();
  static final OnboardingService instance = OnboardingService._();

  static const _prefix = 'onboarding_done_';

  /// Solo las cuentas creadas hace menos de esto ven el recorrido solas;
  /// las más antiguas lo tienen disponible en Configuración.
  static const Duration newAccountWindow = Duration(days: 7);

  // Evita abrirlo dos veces en la misma sesión si el Shell se reconstruye.
  bool _autoShownThisSession = false;

  /// ¿Hay que mostrarlo solo, ahora? Es `true` una única vez por cuenta, y
  /// solo si la cuenta es reciente ([accountCreatedAt] dentro de
  /// [newAccountWindow]). Si no se conoce la fecha de creación, no se muestra.
  Future<bool> shouldAutoShow(String uid, {required DateTime? accountCreatedAt}) async {
    if (_autoShownThisSession) return false;
    if (accountCreatedAt == null) return false;
    if (DateTime.now().difference(accountCreatedAt) > newAccountWindow) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('$_prefix$uid') ?? false;
      if (!done) _autoShownThisSession = true;
      return !done;
    } catch (e) {
      // Si no se puede leer, mejor no interrumpir a la persona.
      debugPrint('OnboardingService: no se pudo leer el estado. $e');
      return false;
    }
  }

  /// Marca el recorrido como visto (terminado u omitido).
  Future<void> markDone(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefix$uid', true);
    } catch (e) {
      debugPrint('OnboardingService: no se pudo guardar. $e');
    }
  }
}
