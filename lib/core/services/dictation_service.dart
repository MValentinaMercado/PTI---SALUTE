import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Por qué no se pudo dictar (para mostrar un mensaje claro).
enum DictationFailure { unavailable, permissionDenied, error }

/// Ingreso de texto por voz (dictado) con el reconocimiento del sistema.
///
/// OJO con la privacidad: en Android el reconocimiento por defecto lo hace
/// el servicio de voz de Google y el audio puede procesarse en la nube; en
/// iOS, Apple. Sirve para campos de salud, pero hay que decirlo en la
/// política de privacidad. [onDevice] fuerza el reconocimiento sin red
/// (solo funciona si el idioma está descargado en el teléfono).
class DictationService {
  DictationService._();
  static final DictationService instance = DictationService._();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  String? _localeId;

  /// `true` mientras se está escuchando.
  final ValueNotifier<bool> listening = ValueNotifier<bool>(false);

  /// Último error del reconocimiento (`null` si no hubo).
  DictationFailure? lastFailure;

  /// Prepara el reconocimiento y pide el permiso de micrófono la primera vez.
  Future<bool> _ensureReady() async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') listening.value = false;
        },
        onError: (e) {
          debugPrint('DictationService error: ${e.errorMsg}');
          listening.value = false;
          lastFailure = e.errorMsg.contains('permission')
              ? DictationFailure.permissionDenied
              : DictationFailure.error;
        },
      );
      if (_initialized) {
        final locales = await _speech.locales();
        _localeId = pickSpanishLocale(locales.map((l) => l.localeId).toList());
      } else {
        lastFailure = await _speech.hasPermission
            ? DictationFailure.unavailable
            : DictationFailure.permissionDenied;
      }
    } catch (e) {
      debugPrint('DictationService: no se pudo inicializar. $e');
      lastFailure = DictationFailure.unavailable;
      _initialized = false;
    }
    return _initialized;
  }

  /// Empieza a escuchar. [onText] recibe el texto reconocido hasta ahora
  /// (parcial mientras se habla, y el final al terminar). Devuelve `false`
  /// si no se pudo empezar (mirar [lastFailure]).
  Future<bool> start({
    required void Function(String text, bool isFinal) onText,
    bool onDevice = false,
  }) async {
    lastFailure = null;
    if (!await _ensureReady()) return false;
    if (_speech.isListening) await _speech.stop();
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) => onText(r.recognizedWords, r.finalResult),
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: true,
          onDevice: onDevice,
        ),
      );
      listening.value = true;
      return true;
    } catch (e) {
      debugPrint('DictationService: no se pudo escuchar. $e');
      lastFailure = DictationFailure.error;
      listening.value = false;
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
    listening.value = false;
  }

  /// Elige el locale en español más cercano al rioplatense.
  @visibleForTesting
  static String? pickSpanishLocale(List<String> ids) {
    String norm(String s) => s.replaceAll('-', '_').toLowerCase();
    for (final pref in const ['es_ar', 'es_us', 'es_mx', 'es_es']) {
      for (final id in ids) {
        if (norm(id) == pref) return id;
      }
    }
    for (final id in ids) {
      if (norm(id).startsWith('es')) return id;
    }
    return null; // el reconocimiento usa el idioma del sistema
  }

  /// Une el texto que ya había con lo dictado, sin pegar palabras.
  static String mergeDictation(String base, String dictated) {
    final d = dictated.trim();
    if (d.isEmpty) return base;
    if (base.isEmpty || base.endsWith(' ') || base.endsWith('\n')) return '$base$d';
    return '$base $d';
  }
}
