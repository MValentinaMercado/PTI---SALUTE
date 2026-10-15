import 'package:flutter/material.dart';
import 'package:saluteapp/core/models/dose_log.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/services/dose_log_service.dart';
import 'package:saluteapp/core/services/medication_check_service.dart';
import 'package:saluteapp/core/services/medication_reminder_service.dart';
import 'package:saluteapp/core/services/medication_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';

// Paleta de esta pantalla (menta + verde profundo), tomada del diseño.
const Color _bg = Color(0xFFDFFCEE);
const Color _ink = Color(0xFF0B6B40);
const Color _blob = Color(0xFFBFE6D0);

/// Pantalla completa que se abre al tocar una alerta de medicación.
///
/// Un solo gesto por acción, con botones grandes (pensada para usarse
/// con una mano, a cualquier hora):
///  - centro: "Tomada" (registra la toma y descuenta del botiquín);
///  - izquierda: "No tomada";
///  - derecha: "Posponer 15 min" (vuelve a avisar).
class MedicationAlarmScreen extends StatefulWidget {
  final String profileId;
  final String medicationId;
  final DateTime scheduledAt;

  /// Alerta de prueba: muestra la pantalla pero no registra nada.
  final bool isTest;

  const MedicationAlarmScreen({
    super.key,
    required this.profileId,
    required this.medicationId,
    required this.scheduledAt,
    this.isTest = false,
  });

  @override
  State<MedicationAlarmScreen> createState() => _MedicationAlarmScreenState();
}

class _MedicationAlarmScreenState extends State<MedicationAlarmScreen> {
  Medication? _medication;
  String _profileName = '';
  DoseStatus? _existing;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Medication? med;
    var profileName = '';
    DoseStatus? existing;
    try {
      med = await MedicationService.instance.getMedication(widget.profileId, widget.medicationId);
      profileName = (await ProfileService.instance.getProfile(widget.profileId))?.name ?? '';
      if (med != null && !widget.isTest) {
        final log = await DoseLogService.instance
            .get(widget.profileId, widget.medicationId, widget.scheduledAt)
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
        existing = log?.status;
      }
    } catch (_) {
      med = null;
    }
    if (!mounted) return;
    setState(() {
      _medication = med;
      _profileName = profileName;
      _existing = existing;
      _loading = false;
    });
  }

  String get _timeLabel {
    final t = widget.scheduledAt;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void _finish(String message) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _mark(DoseStatus status) async {
    final med = _medication;
    if (med == null || _busy) return;
    if (widget.isTest) {
      _finish('Así se ve la alerta. Todo listo.');
      return;
    }
    setState(() => _busy = true);
    try {
      final remaining = await MedicationCheckService.instance.mark(
        profileId: widget.profileId,
        medication: med,
        scheduledAt: widget.scheduledAt,
        status: status,
        previous: _existing,
      );
      var message = status == DoseStatus.taken ? 'Toma registrada.' : 'Marcada como no tomada.';
      if (status == DoseStatus.taken && remaining != null && remaining <= med.unitsPerDay * 3) {
        message += ' Quedan $remaining unidades en tu botiquín.';
      }
      _finish(message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar. Intentá de nuevo.')),
      );
    }
  }

  Future<void> _snooze() async {
    final med = _medication;
    if (med == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (!widget.isTest) {
        await MedicationReminderService.instance.snooze(
          profileId: widget.profileId,
          profileName: _profileName,
          medication: med,
          scheduledAt: widget.scheduledAt,
        );
      }
      _finish('Te volvemos a avisar en 15 minutos.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo posponer la alerta.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _BlobsPainter())),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      button: true,
                      label: 'Cerrar',
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.of(context).pop(),
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(Icons.close_rounded, color: _ink, size: 22),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _ink));
    }
    final med = _medication;
    if (med == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Esta medicación ya no existe o no se pudo cargar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    final details = [
      _timeLabel,
      if (med.dose.trim().isNotEmpty) med.dose.trim(),
      if (_profileName.isNotEmpty) 'Para $_profileName',
    ].join('  ·  ');

    return Column(
      children: [
        const Spacer(flex: 9),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Text(
                med.name,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                details,
                textAlign: TextAlign.center,
                style: TextStyle(color: _ink.withValues(alpha: 0.75), fontSize: 15, fontWeight: FontWeight.w500),
              ),
              if (_existing != null) ...[
                const SizedBox(height: 8),
                Text(
                  _existing == DoseStatus.taken
                      ? 'Esta toma ya está marcada como tomada.'
                      : 'Esta toma está marcada como no tomada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _ink.withValues(alpha: 0.6), fontSize: 13),
                ),
              ],
              if (widget.isTest) ...[
                const SizedBox(height: 8),
                Text(
                  'Alerta de prueba: no se guarda nada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _ink.withValues(alpha: 0.6), fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        const Spacer(flex: 7),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SideAction(
                label: 'No tomada',
                tooltip: 'Marcar como no tomada',
                onTap: _busy ? null : () => _mark(DoseStatus.notTaken),
                glyph: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _ink, width: 2)),
                  child: const Icon(Icons.close_rounded, color: _ink, size: 20),
                ),
              ),
              _MainAction(busy: _busy, onTap: _busy ? null : () => _mark(DoseStatus.taken)),
              _SideAction(
                label: 'Posponer',
                tooltip: 'Posponer 15 minutos',
                onTap: _busy ? null : _snooze,
                glyph: SizedBox(
                  width: 34,
                  height: 34,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.flip(flipX: true, child: const Icon(Icons.replay_rounded, color: _ink, size: 34)),
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text('15', style: TextStyle(color: _ink, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Spacer(flex: 6),
      ],
    );
  }
}

class _MainAction extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;
  const _MainAction({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          label: 'Marcar como tomada',
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 86,
              height: 86,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _ink.withValues(alpha: 0.18)),
              child: Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: _ink),
                child: busy
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, color: Colors.white, size: 38),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text('Tomada', style: TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _SideAction extends StatelessWidget {
  final String label;
  final String tooltip;
  final Widget glyph;
  final VoidCallback? onTap;
  const _SideAction({required this.label, required this.tooltip, required this.glyph, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 84,
            child: Column(
              children: [
                Opacity(opacity: onTap == null ? 0.4 : 1, child: glyph),
                const SizedBox(height: 10),
                Text(label, style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fondo orgánico de la pantalla: dos círculos con degradé en las
/// esquinas y dos manchas suaves, en tonos de menta.
class _BlobsPainter extends CustomPainter {
  const _BlobsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Círculo arriba a la izquierda.
    final c1 = Rect.fromCircle(center: Offset(w * 0.24, h * 0.09), radius: w * 0.33);
    canvas.drawCircle(
      c1.center,
      c1.width / 2,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: [_blob.withValues(alpha: 0.85), _bg.withValues(alpha: 0.0)],
        ).createShader(c1),
    );

    // Mancha grande, centro-derecha.
    final upper = Path()
      ..moveTo(w * 0.40, h * 0.42)
      ..cubicTo(w * 0.34, h * 0.33, w * 0.52, h * 0.27, w * 0.68, h * 0.25)
      ..cubicTo(w * 0.86, h * 0.22, w * 0.92, h * 0.10, w * 0.86, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.36)
      ..cubicTo(w * 0.96, h * 0.47, w * 0.78, h * 0.52, w * 0.62, h * 0.51)
      ..cubicTo(w * 0.48, h * 0.50, w * 0.42, h * 0.47, w * 0.40, h * 0.42)
      ..close();
    canvas.drawPath(upper, Paint()..color = _blob.withValues(alpha: 0.5));

    // Mancha abajo a la izquierda (detrás de los controles).
    final lower = Path()
      ..moveTo(0, h * 0.62)
      ..cubicTo(w * 0.15, h * 0.58, w * 0.42, h * 0.58, w * 0.53, h * 0.66)
      ..cubicTo(w * 0.62, h * 0.74, w * 0.42, h * 0.78, w * 0.25, h * 0.83)
      ..cubicTo(w * 0.12, h * 0.87, w * 0.16, h * 0.95, w * 0.18, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(lower, Paint()..color = _blob.withValues(alpha: 0.55));

    // Círculo abajo a la derecha.
    final c2 = Rect.fromCircle(center: Offset(w * 0.86, h * 0.89), radius: w * 0.28);
    canvas.drawCircle(
      c2.center,
      c2.width / 2,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bg.withValues(alpha: 0.0), _blob.withValues(alpha: 0.9)],
        ).createShader(c2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
