import 'package:flutter/material.dart';

import 'package:saluteapp/core/accessibility_controller.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/services/dictation_service.dart';
import 'package:saluteapp/core/services/tts_service.dart';

/// Botón "leer en voz alta": toca para escuchar el texto, toca de nuevo
/// para detener. Muestra el estado en el ícono, en el tooltip y para
/// lectores de pantalla.
class SpeakButton extends StatelessWidget {
  /// Identifica este texto (para saber si es el que se está leyendo).
  final String id;
  final String text;
  final Color color;
  final double size;

  const SpeakButton({
    super.key,
    required this.id,
    required this.text,
    this.color = SaluteColors.primaryGreen,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    // Se puede ocultar desde Configuración › Accesibilidad.
    return ListenableBuilder(
      listenable: AccessibilityController.instance,
      builder: (context, _) => AccessibilityController.instance.voiceButtons
          ? _button()
          : const SizedBox.shrink(),
    );
  }

  Widget _button() {
    return ValueListenableBuilder<String?>(
      valueListenable: TtsService.instance.speakingId,
      builder: (context, speaking, _) {
        final active = speaking == id;
        final label = active ? 'Detener lectura' : 'Leer en voz alta';
        return IconButton(
          onPressed: () => TtsService.instance.toggle(id, text),
          tooltip: label,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48), // objetivo táctil mínimo
          icon: Icon(
            active ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
            size: size,
            color: color,
            semanticLabel: label,
          ),
        );
      },
    );
  }
}

/// Botón de micrófono para dictar dentro de un [TextEditingController].
/// Lo dictado se agrega al final del texto que ya hubiera.
class DictationButton extends StatefulWidget {
  final TextEditingController controller;
  final Color color;

  const DictationButton({
    super.key,
    required this.controller,
    this.color = SaluteColors.primaryGreen,
  });

  @override
  State<DictationButton> createState() => _DictationButtonState();
}

class _DictationButtonState extends State<DictationButton> {
  bool _active = false; // ¿este botón es el que está dictando?
  String _base = '';

  /// ¿Este botón está dictando ahora? (el reconocimiento puede terminar
  /// solo por silencio o error, así que no alcanza con `_active`).
  bool get _running => _active && DictationService.instance.listening.value;

  @override
  void dispose() {
    if (_running) DictationService.instance.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    final service = DictationService.instance;
    if (_running) {
      await service.stop();
      if (mounted) setState(() => _active = false);
      return;
    }

    _base = widget.controller.text;
    setState(() => _active = true);
    final ok = await service.start(
      onText: (text, isFinal) {
        if (!mounted) return;
        final merged = DictationService.mergeDictation(_base, text);
        widget.controller.value = TextEditingValue(
          text: merged,
          selection: TextSelection.collapsed(offset: merged.length),
        );
        if (isFinal) setState(() => _active = false);
      },
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _active = false);
      final msg = switch (service.lastFailure) {
        DictationFailure.permissionDenied =>
          'Necesito permiso para usar el micrófono. Podés activarlo en los ajustes del teléfono.',
        DictationFailure.unavailable => 'El dictado por voz no está disponible en este teléfono.',
        _ => 'No pude escucharte. Probá de nuevo.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AccessibilityController.instance,
      builder: (context, _) => AccessibilityController.instance.voiceButtons
          ? _button()
          : const SizedBox.shrink(),
    );
  }

  Widget _button() {
    // El ícono se apaga solo cuando el reconocimiento termina (silencio,
    // tiempo o error), porque escucha el estado del servicio.
    return ValueListenableBuilder<bool>(
      valueListenable: DictationService.instance.listening,
      builder: (context, listening, _) {
        final on = _active && listening;
        final label = on ? 'Detener dictado' : 'Dictar por voz';
        return IconButton(
          onPressed: _toggle,
          tooltip: label,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(
            on ? Icons.mic : Icons.mic_none,
            color: on ? SaluteColors.danger : widget.color,
            semanticLabel: label,
          ),
        );
      },
    );
  }
}
