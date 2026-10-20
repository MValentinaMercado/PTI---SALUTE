import 'package:flutter_test/flutter_test.dart';
import 'package:saluteapp/core/services/dictation_service.dart';
import 'package:saluteapp/core/services/tts_service.dart';

void main() {
  group('TtsService.cleanForSpeech', () {
    test('saca marcas de markdown y viñetas', () {
      expect(
        TtsService.cleanForSpeech('**Importante:** tomá agua\n- reposo\n- ibuprofeno'),
        'Importante: tomá agua. reposo. ibuprofeno',
      );
    });
    test('reemplaza links y deja el texto del enlace', () {
      expect(TtsService.cleanForSpeech('Mirá [esta guía](https://x.com/a) hoy'), 'Mirá esta guía hoy');
      expect(TtsService.cleanForSpeech('Entrá a https://x.com/largo/largo'), 'Entrá a enlace');
    });
    test('saca emojis', () {
      expect(TtsService.cleanForSpeech('Cuidate 🙂💊 mucho'), 'Cuidate mucho');
    });
    test('texto vacío queda vacío', () {
      expect(TtsService.cleanForSpeech('  \n  '), '');
    });
  });

  group('DictationService', () {
    test('elige es_AR, luego otras variantes en español', () {
      expect(DictationService.pickSpanishLocale(['en_US', 'es_ES', 'es_AR']), 'es_AR');
      expect(DictationService.pickSpanishLocale(['en-US', 'es-MX']), 'es-MX');
      expect(DictationService.pickSpanishLocale(['en_US', 'es_CL']), 'es_CL');
      expect(DictationService.pickSpanishLocale(['en_US', 'fr_FR']), isNull);
    });
    test('mergeDictation no pega palabras ni agrega espacios de más', () {
      expect(DictationService.mergeDictation('', 'hola'), 'hola');
      expect(DictationService.mergeDictation('Tengo', 'dolor de cabeza'), 'Tengo dolor de cabeza');
      expect(DictationService.mergeDictation('Tengo ', 'fiebre'), 'Tengo fiebre');
      expect(DictationService.mergeDictation('Nota', '  '), 'Nota');
    });
  });
}
