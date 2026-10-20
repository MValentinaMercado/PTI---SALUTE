import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Velocidad de la lectura en voz alta.
enum SpeechSpeed {
  slow('Lenta', 0.38),
  normal('Normal', 0.5),
  fast('Rápida', 0.62);

  final String label;
  final double rate; // valor para flutter_tts
  const SpeechSpeed(this.label, this.rate);
}

/// Preferencias de accesibilidad de la persona, guardadas en el teléfono
/// (`shared_preferences`). Se carga una vez en `main()` y la app entera se
/// reconstruye cuando algo cambia (ver `MyApp`).
///
///  - [textScale]: multiplica el tamaño de TODOS los textos, además del
///    tamaño de fuente que ya configuró el sistema operativo.
///  - [highContrast]: tema de alto contraste (bordes y textos más marcados).
///  - [voiceButtons]: muestra u oculta los botones de dictado y lectura.
///  - [speechSpeed]: velocidad de la voz.
class AccessibilityController extends ChangeNotifier {
  AccessibilityController._();
  static final AccessibilityController instance = AccessibilityController._();

  static const _kTextScale = 'a11y_text_scale';
  static const _kHighContrast = 'a11y_high_contrast';
  static const _kVoiceButtons = 'a11y_voice_buttons';
  static const _kSpeechSpeed = 'a11y_speech_speed';

  /// Escalas que ofrece la pantalla (100 %, 115 %, 130 %, 150 %).
  static const List<double> textScaleOptions = [1.0, 1.15, 1.3, 1.5];

  /// Tope del tamaño final (sistema × app). WCAG 1.4.4 pide que la app
  /// funcione hasta 200 %; pasar de ahí rompe casi cualquier layout.
  static const double maxEffectiveScale = 2.0;
  static const double minEffectiveScale = 0.8;

  double _textScale = 1.0;
  bool _highContrast = false;
  bool _voiceButtons = true;
  SpeechSpeed _speechSpeed = SpeechSpeed.slow;

  double get textScale => _textScale;
  bool get highContrast => _highContrast;
  bool get voiceButtons => _voiceButtons;
  SpeechSpeed get speechSpeed => _speechSpeed;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scale = prefs.getDouble(_kTextScale) ?? 1.0;
      _textScale = textScaleOptions.contains(scale) ? scale : 1.0;
      _highContrast = prefs.getBool(_kHighContrast) ?? false;
      _voiceButtons = prefs.getBool(_kVoiceButtons) ?? true;
      final speed = prefs.getString(_kSpeechSpeed);
      _speechSpeed = SpeechSpeed.values.firstWhere(
        (s) => s.name == speed,
        orElse: () => SpeechSpeed.slow,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('AccessibilityController: no se pudieron leer las preferencias. $e');
    }
  }

  Future<void> setTextScale(double value) async {
    if (!textScaleOptions.contains(value) || value == _textScale) return;
    _textScale = value;
    notifyListeners();
    await _save((p) => p.setDouble(_kTextScale, value));
  }

  Future<void> setHighContrast(bool value) async {
    if (value == _highContrast) return;
    _highContrast = value;
    notifyListeners();
    await _save((p) => p.setBool(_kHighContrast, value));
  }

  Future<void> setVoiceButtons(bool value) async {
    if (value == _voiceButtons) return;
    _voiceButtons = value;
    notifyListeners();
    await _save((p) => p.setBool(_kVoiceButtons, value));
  }

  Future<void> setSpeechSpeed(SpeechSpeed value) async {
    if (value == _speechSpeed) return;
    _speechSpeed = value;
    notifyListeners();
    await _save((p) => p.setString(_kSpeechSpeed, value.name));
  }

  Future<void> reset() async {
    _textScale = 1.0;
    _highContrast = false;
    _voiceButtons = true;
    _speechSpeed = SpeechSpeed.slow;
    notifyListeners();
    await _save((p) async {
      await p.remove(_kTextScale);
      await p.remove(_kHighContrast);
      await p.remove(_kVoiceButtons);
      await p.remove(_kSpeechSpeed);
    });
  }

  Future<void> _save(Future<void> Function(SharedPreferences p) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (e) {
      debugPrint('AccessibilityController: no se pudo guardar. $e');
    }
  }

  /// Escala final: la del sistema operativo × la de la app, acotada.
  /// El sistema puede escalar de forma no lineal (Android 14+): se mide
  /// con una fuente de referencia grande y se usa un factor lineal.
  @visibleForTesting
  static double effectiveScale({required double systemFactor, required double appScale}) {
    return (systemFactor * appScale).clamp(minEffectiveScale, maxEffectiveScale);
  }

  /// `MediaQuery` con la escala de texto combinada, para envolver la app.
  MediaQueryData applyTo(MediaQueryData data) {
    final system = data.textScaler.scale(100) / 100;
    final factor = effectiveScale(systemFactor: system, appScale: _textScale);
    return data.copyWith(textScaler: TextScaler.linear(factor));
  }
}
