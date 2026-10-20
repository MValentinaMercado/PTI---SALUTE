import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/services/ai_insight_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Números de emergencia que se muestran en el aviso. Ajustalos según el país.
const String kEmergencyNumbers = '107 / 911';

const Color _kUrgent = Color(0xFFB03A3A);

// ─────────────────────────────────────────────────────────────────────────────
// CONSENTIMIENTO
// ─────────────────────────────────────────────────────────────────────────────

/// Consentimiento (por dispositivo) para enviar los datos de una pantalla a
/// un servicio de IA. Se pide una sola vez, antes del primer análisis.
abstract final class AiConsent {
  static const _key = 'salute_ai_consent_v1';

  static Future<bool> has() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> grant() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {
      // Si no se puede guardar, se vuelve a pedir la próxima vez.
    }
  }

  /// Para una opción "Revocar consentimiento" en ajustes.
  static Future<void> revoke() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  /// `true` si ya había consentimiento o el usuario lo acepta ahora.
  static Future<bool> ensure(BuildContext context) async {
    if (await has()) return true;
    if (!context.mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Orientación con IA'),
        content: const SingleChildScrollView(
          child: Text(
            'Para generar la orientación, Salute envía a un servicio de '
                'inteligencia artificial los datos que cargaste en esta '
                'pantalla. No se envía el nombre del perfil.\n\n'
                'Es una orientación informativa: no es un diagnóstico y no '
                'reemplaza la consulta con un profesional de la salud.\n\n'
                'Ante una emergencia, llamá al $kEmergencyNumbers.',
            style: TextStyle(height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: SaluteColors.primaryGreen,
            ),
            child: const Text('Acepto'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      await grant();
      return true;
    }
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTROLADOR
// ─────────────────────────────────────────────────────────────────────────────

/// Permite que la pantalla dispare el análisis desde afuera (ej. justo
/// después de guardar). Si faltan datos o no hay consentimiento, no hace nada.
class AiInsightController {
  Future<void> Function()? _runner;

  Future<void> run() async {
    final runner = _runner;
    if (runner != null) await runner();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA
// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { idle, loading, done, error }

/// Tarjeta reutilizable de orientación con IA. Cada pantalla le pasa sus
/// datos con [buildData]; la tarjeta se ocupa del consentimiento, la carga,
/// los errores y el resultado.
///
/// Las [redFlags] (reglas fijas) se muestran SIEMPRE arriba, con o sin IA.
class AiInsightCard extends StatefulWidget {
  /// 'triaje' | 'emocional' | 'metricas'.
  final String kind;
  final String title;
  final String profileId;

  /// Contexto mínimo, sin nombre. Ej: `{'tipo': 'persona'}`.
  final Map<String, dynamic> subject;

  /// Se llama al momento de analizar, así siempre toma los datos actuales.
  final Map<String, dynamic> Function() buildData;

  final List<String> redFlags;

  /// `false` mientras falten datos para que el análisis tenga sentido.
  final bool ready;
  final String notReadyHint;

  final AiInsightController? controller;

  /// Se llama cuando cambia la fase (cargando / resultado / error). Útil para
  /// hacer scroll hasta la tarjeta.
  final VoidCallback? onStateChanged;

  const AiInsightCard({
    super.key,
    required this.kind,
    required this.profileId,
    required this.buildData,
    this.title = 'ORIENTACIÓN DE SALUTE AI',
    this.subject = const {'tipo': 'persona'},
    this.redFlags = const [],
    this.ready = true,
    this.notReadyHint = 'Completá más datos para poder analizar.',
    this.controller,
    this.onStateChanged,
  });

  @override
  State<AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends State<AiInsightCard> {
  _Phase _phase = _Phase.idle;
  AiInsight? _insight;
  String _error = '';

  @override
  void initState() {
    super.initState();
    widget.controller?._runner = _run;
  }

  @override
  void didUpdateWidget(covariant AiInsightCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._runner = null;
      widget.controller?._runner = _run;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._runner == _run) {
      widget.controller?._runner = null;
    }
    super.dispose();
  }

  Future<void> _run() async {
    if (_phase == _Phase.loading || !widget.ready) return;
    if (!await AiConsent.ensure(context)) return;
    if (!mounted) return;

    setState(() {
      _phase = _Phase.loading;
      _error = '';
    });
    widget.onStateChanged?.call();

    try {
      final insight = await AiInsightService.instance.analyze(
        kind: widget.kind,
        profileId: widget.profileId,
        subject: widget.subject,
        data: widget.buildData(),
        redFlags: widget.redFlags,
      );
      if (!mounted) return;
      setState(() {
        _insight = insight;
        _phase = _Phase.done;
      });
    } on AiInsightException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _phase = _Phase.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo generar la orientación. Probá de nuevo.';
        _phase = _Phase.error;
      });
    }
    if (mounted) widget.onStateChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.redFlags.isNotEmpty) ...[
          _RedFlagBanner(flags: widget.redFlags),
          const SizedBox(height: 12),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: SaluteColors.primaryGreen.withValues(alpha: 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 14),
              ..._buildBody(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final insight = _insight;
    return Row(
      children: [
        const Icon(
          Icons.auto_awesome,
          size: 16,
          color: SaluteColors.primaryGreen,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: SaluteColors.darkGreen,
            ),
          ),
        ),
        if (_phase == _Phase.done && insight != null)
          _LevelChip(level: insight.nivel),
      ],
    );
  }

  List<Widget> _buildBody() {
    switch (_phase) {
      case _Phase.idle:
        return [
          Text(
            'Analiza los datos que cargaste y te da una orientación general. '
                'No es un diagnóstico ni reemplaza a un profesional de la salud.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 14),
          if (!widget.ready) ...[
            Text(
              widget.notReadyHint,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
          ],
          _AnalyzeButton(
            label: 'ANALIZAR CON SALUTE AI',
            onPressed: widget.ready ? _run : null,
          ),
        ];

      case _Phase.loading:
        return [
          Semantics(
            liveRegion: true,
            label: 'Analizando tus datos',
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: SaluteColors.primaryGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Analizando tus datos…',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ];

      case _Phase.error:
        return [
          Text(
            _error,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 14),
          _AnalyzeButton(
            label: 'REINTENTAR',
            icon: Icons.refresh,
            onPressed: widget.ready ? _run : null,
          ),
        ];

      case _Phase.done:
        final insight = _insight!;
        return [
          if (insight.resumen.isNotEmpty)
            Text(
              insight.resumen,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          _Section(
            icon: Icons.visibility_outlined,
            title: 'LO QUE SE OBSERVA',
            items: insight.hallazgos,
            color: SaluteColors.primaryGreen,
          ),
          _Section(
            icon: Icons.lightbulb_outline,
            title: 'QUÉ PODÉS HACER',
            items: insight.recomendaciones,
            color: SaluteColors.primaryGreen,
          ),
          _Section(
            icon: Icons.medical_services_outlined,
            title: 'CUÁNDO CONSULTAR',
            items: insight.cuandoConsultar,
            color: SaluteColors.terracotta,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.ready ? _run : null,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Volver a analizar'),
              style: TextButton.styleFrom(
                foregroundColor: SaluteColors.primaryGreen,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Orientación generada por IA. No es un diagnóstico ni reemplaza a un '
                'profesional de la salud. Ante una emergencia llamá al '
                '$kEmergencyNumbers.',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: Colors.grey.shade500,
            ),
          ),
        ];
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PIEZAS
// ─────────────────────────────────────────────────────────────────────────────

class _AnalyzeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _AnalyzeButton({
    required this.label,
    required this.onPressed,
    this.icon = Icons.auto_awesome,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: SaluteColors.primaryGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: SaluteColors.primaryGreen.withValues(
            alpha: 0.3,
          ),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  final String level;
  const _LevelChip({required this.level});

  Color get _color => switch (level) {
    'urgente' => _kUrgent,
    'consultar' => SaluteColors.terracotta,
    'vigilar' => SaluteColors.brownOrange,
    _ => SaluteColors.primaryGreen,
  };

  String get _label => switch (level) {
    'urgente' => 'Atención urgente',
    'consultar' => 'Conviene consultar',
    'vigilar' => 'Para vigilar',
    _ => 'Informativo',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: _color,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;
  final Color color;

  const _Section({
    required this.icon,
    required this.title,
    required this.items,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RedFlagBanner extends StatelessWidget {
  final List<String> flags;
  const _RedFlagBanner({required this.flags});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kUrgent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kUrgent.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: _kUrgent, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Señales de alarma',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _kUrgent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final f in flags)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $f',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Si esto está pasando ahora, buscá atención médica de urgencia o '
                  'llamá al $kEmergencyNumbers. No esperes el análisis de la IA.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: _kUrgent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}