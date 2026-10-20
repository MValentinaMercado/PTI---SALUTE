import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de la app que se editan en Configuración y que el resto del
/// código tiene que respetar (no son variables locales de la pantalla).
///
///  - [notificationsEnabled]: habilita/deshabilita TODAS las notificaciones
///    locales de la app (medicación, vacunas/controles, agenda).
///  - [locationEnabled]: permite que la app use la ubicación (SOS, mapa).
///    Es independiente del permiso del sistema: ver [LocationAccess].
class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  static const _kNotifications = 'settings_notifications_enabled';
  static const _kLocation = 'settings_location_enabled';
  static const _kSosPinned = 'settings_sos_pinned_dashboard';

  bool _notificationsEnabled = true;
  bool _locationEnabled = true;
  bool _sosPinnedToDashboard = false;
  bool _loaded = false;

  bool get notificationsEnabled => _notificationsEnabled;
  bool get locationEnabled => _locationEnabled;

  /// `true`: el botón SOS deja de ser global y queda fijo solo en el Inicio.
  bool get sosPinnedToDashboard => _sosPinnedToDashboard;

  /// Se llama una vez en `main()` antes de `runApp`.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _notificationsEnabled = p.getBool(_kNotifications) ?? true;
      _locationEnabled = p.getBool(_kLocation) ?? true;
      _sosPinnedToDashboard = p.getBool(_kSosPinned) ?? false;
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('AppSettingsService: no se pudieron leer los ajustes. $e');
    }
  }

  Future<void> setNotificationsEnabled(bool value) async {
    if (value == _notificationsEnabled) return;
    _notificationsEnabled = value;
    notifyListeners();
    await _save((p) => p.setBool(_kNotifications, value));
  }

  Future<void> setLocationEnabled(bool value) async {
    if (value == _locationEnabled) return;
    _locationEnabled = value;
    notifyListeners();
    await _save((p) => p.setBool(_kLocation, value));
  }

  Future<void> setSosPinnedToDashboard(bool value) async {
    if (value == _sosPinnedToDashboard) return;
    _sosPinnedToDashboard = value;
    notifyListeners();
    await _save((p) => p.setBool(_kSosPinned, value));
  }

  Future<void> _save(Future<bool> Function(SharedPreferences p) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (e) {
      debugPrint('AppSettingsService: no se pudo guardar. $e');
    }
  }
}
