import 'package:flutter/material.dart';

import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/accessibility_controller.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/services/tts_service.dart';

/// Configuración › Accesibilidad: tamaño de texto, alto contraste y voz.
/// Los cambios se ven al instante (la app entera escucha al controlador).
class AccessibilityScreen extends StatelessWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a11y = AccessibilityController.instance;
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(title: 'Accesibilidad', onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: ListenableBuilder(
                listenable: a11y,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  children: [
                    const _SectionTitle('Texto'),
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tamaño del texto', style: _titleStyle),
                          const SizedBox(height: 4),
                          const Text(
                            'Se suma al tamaño que ya elegiste en los ajustes del teléfono.',
                            style: _subtitleStyle,
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in AccessibilityController.textScaleOptions)
                                ChoiceChip(
                                  label: Text('${(s * 100).round()} %'),
                                  selected: a11y.textScale == s,
                                  onSelected: (_) => a11y.setTextScale(s),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: SaluteColors.lightGreen.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Así se va a ver el texto en toda la app: recordá tomar tu medicación '
                              'y cargar tus controles.',
                              style: TextStyle(fontSize: 15, height: 1.4, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _SectionTitle('Contraste'),
                    const SizedBox(height: 12),
                    _SwitchCard(
                      title: 'Alto contraste',
                      subtitle: 'Bordes, botones y textos más marcados.',
                      value: a11y.highContrast,
                      onChanged: a11y.setHighContrast,
                    ),
                    const SizedBox(height: 28),
                    const _SectionTitle('Voz'),
                    const SizedBox(height: 12),
                    _SwitchCard(
                      title: 'Botones de dictado y lectura',
                      subtitle: 'Muestra el micrófono para dictar y el parlante para escuchar las respuestas.',
                      value: a11y.voiceButtons,
                      onChanged: a11y.setVoiceButtons,
                    ),
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Velocidad de lectura', style: _titleStyle),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in SpeechSpeed.values)
                                ChoiceChip(
                                  label: Text(s.label),
                                  selected: a11y.speechSpeed == s,
                                  onSelected: (_) => a11y.setSpeechSpeed(s),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const _VoiceTestButton(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _SectionTitle('Restablecer'),
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Volver a los valores originales', style: _titleStyle),
                          const SizedBox(height: 4),
                          const Text(
                            'El texto, el contraste y la voz vuelven a como venían al instalar la app.',
                            style: _subtitleStyle,
                          ),
                          const SizedBox(height: 14),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 52),
                            child: OutlinedButton.icon(
                              onPressed: () => _confirmReset(context),
                              icon: const Icon(Icons.restart_alt),
                              label: const Text(
                                'Restablecer valores',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: SaluteColors.primaryGreen,
                                side: const BorderSide(color: SaluteColors.primaryGreen, width: 1.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmReset(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Restablecer valores?'),
      content: const Text(
        'Se vuelven a poner el tamaño de texto, el contraste y la voz como al empezar.',
        style: TextStyle(fontSize: 16, height: 1.4),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 48),
          child: FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: SaluteColors.primaryGreen),
            child: const Text('Sí, restablecer', style: TextStyle(fontSize: 16)),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 48),
          child: TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await AccessibilityController.instance.reset();
  await TtsService.instance.stop();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Valores restablecidos.')),
    );
  }
}

/// Botón grande "Probar voz": cambia a "Detener" mientras suena.
class _VoiceTestButton extends StatelessWidget {
  const _VoiceTestButton();

  static const _id = 'a11y-test';
  static const _sample = 'Hola, así suena la lectura en voz alta de Salute.';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: TtsService.instance.speakingId,
      builder: (context, speaking, _) {
        final playing = speaking == _id;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SaluteColors.lightGreen.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.record_voice_over_outlined, color: SaluteColors.primaryGreen),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '“$_sample”',
                      style: TextStyle(fontSize: 15, height: 1.4, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: FilledButton.icon(
                onPressed: () => TtsService.instance.toggle(_id, _sample),
                icon: Icon(playing ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                label: Text(
                  playing ? 'Detener' : 'Probar voz',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: SaluteColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

const _titleStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87);
const _subtitleStyle = TextStyle(fontSize: 13, color: SaluteColors.textMuted, height: 1.35);

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: SaluteColors.primaryGreen),
        ),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: child,
      );
}

class _SwitchCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _titleStyle),
                  const SizedBox(height: 2),
                  Text(subtitle, style: _subtitleStyle),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged, activeThumbColor: SaluteColors.primaryGreen),
          ],
        ),
      ),
    );
  }
}
