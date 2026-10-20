import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saluteapp/core/accessibility_controller.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('Contraste de la paleta (WCAG AA: 4,5:1 para texto normal)', () {
    final fondos = {
      'blanco': Colors.white,
      'bgColor': SaluteColors.bgColor,
      'lightGreen': SaluteColors.lightGreen,
      'cardBeige': SaluteColors.cardBeige,
    };
    final textos = {
      'textMuted': SaluteColors.textMuted,
      'primaryGreen': SaluteColors.primaryGreen,
      'terracotta': SaluteColors.terracotta,
      'negro 87%': Colors.black87,
    };
    for (final t in textos.entries) {
      for (final f in fondos.entries) {
        test('${t.key} sobre ${f.key}', () {
          expect(_contrast(t.value, f.value), greaterThanOrEqualTo(4.5));
        });
      }
    }
  });

  group('AccessibilityController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('escala efectiva = sistema × app, acotada entre 0,8 y 2,0', () {
      expect(AccessibilityController.effectiveScale(systemFactor: 1.0, appScale: 1.3), closeTo(1.3, 1e-9));
      expect(AccessibilityController.effectiveScale(systemFactor: 1.5, appScale: 1.5), 2.0);
      expect(AccessibilityController.effectiveScale(systemFactor: 0.5, appScale: 1.0), 0.8);
    });

    test('guarda y recupera las preferencias', () async {
      final c = AccessibilityController.instance;
      await c.setTextScale(1.3);
      await c.setHighContrast(true);
      await c.setVoiceButtons(false);
      await c.setSpeechSpeed(SpeechSpeed.fast);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('a11y_text_scale'), 1.3);
      expect(prefs.getBool('a11y_high_contrast'), isTrue);
      expect(prefs.getBool('a11y_voice_buttons'), isFalse);
      expect(prefs.getString('a11y_speech_speed'), 'fast');

      await c.reset();
      expect(c.textScale, 1.0);
      expect(c.highContrast, isFalse);
      expect(c.voiceButtons, isTrue);
      expect(c.speechSpeed, SpeechSpeed.slow);
    });

    test('ignora escalas que no son opciones válidas', () async {
      final c = AccessibilityController.instance;
      await c.reset();
      await c.setTextScale(3.0);
      expect(c.textScale, 1.0);
    });

    test('load ignora valores guardados inválidos', () async {
      SharedPreferences.setMockInitialValues({
        'a11y_text_scale': 9.9,
        'a11y_speech_speed': 'ultra',
      });
      final c = AccessibilityController.instance;
      await c.load();
      expect(c.textScale, 1.0);
      expect(c.speechSpeed, SpeechSpeed.slow);
    });
  });
}
