import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:saluteapp/core/accessibility_controller.dart';

/// Lectura de texto en voz alta (TTS) con las voces del sistema.
///
/// Corre en el dispositivo (no manda el texto a ningún servidor propio).
/// Una sola lectura a la vez: si se pide otra, corta la anterior.
/// [speakingId] dice qué texto se está leyendo, para que cada botón
/// muestre "leer" o "detener" según corresponda.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  /// Id del texto que se está leyendo ahora (`null` = nada).
  final ValueNotifier<String?> speakingId = ValueNotifier<String?>(null);

  Future<void> _init() async {
    if (_ready) return;
    try {
      // Español rioplatense si está instalado; si no, otras variantes.
      for (final lang in const ['es-AR', 'es-US', 'es-MX', 'es-ES']) {
        final available = await _tts.isLanguageAvailable(lang);
        if (available == true || available == 1) {
          await _tts.setLanguage(lang);
          break;
        }
      }
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(() => speakingId.value = null);
      _tts.setCancelHandler(() => speakingId.value = null);
      _tts.setErrorHandler((_) => speakingId.value = null);
      _ready = true;
    } catch (e) {
      debugPrint('TtsService: no se pudo inicializar. $e');
    }
  }

  /// Lee [text]. Si ya se estaba leyendo ese mismo [id], lo detiene
  /// (el botón funciona como play/stop).
  Future<void> toggle(String id, String text) async {
    if (speakingId.value == id) {
      await stop();
      return;
    }
    await speak(id, text);
  }

  Future<void> speak(String id, String text) async {
    final clean = cleanForSpeech(text);
    if (clean.isEmpty) return;
    await _init();
    try {
      await _tts.stop();
      // La velocidad se lee en cada lectura: se cambia desde Accesibilidad.
      await _tts.setSpeechRate(AccessibilityController.instance.speechSpeed.rate);
      speakingId.value = id;
      await _tts.speak(clean);
    } catch (e) {
      speakingId.value = null;
      debugPrint('TtsService: no se pudo leer en voz alta. $e');
    }
  }

  Future<void> stop() async {
    speakingId.value = null;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Saca lo que suena mal leído en voz alta: marcas de markdown, links
  /// largos y emojis.
  @visibleForTesting
  static String cleanForSpeech(String input) {
    var s = input;
    s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\((?:[^)]+)\)'), (m) => m[1]!); // [texto](url)
    s = s.replaceAll(RegExp(r'https?://\S+'), 'enlace');
    s = s.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    s = s.replaceAll(RegExp(r'[*_`#>~]+'), '');
    s = s.replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '');
    s = s.replaceAll(
      RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]', unicode: true),
      '',
    );
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r'\n{2,}'), '. ');
    s = s.replaceAll('\n', '. ');
    s = s.trim();
    s = s.replaceAll(RegExp(r'^(?:\.\s*)+'), '');
    s = s.replaceAll(RegExp(r'(?:\s*\.)+$'), '');
    if (RegExp(r'^[\.\s]*$').hasMatch(s)) return '';
    return s.trim();
  }
}
