import 'package:flutter/material.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/dose_log.dart';
import 'package:saluteapp/core/models/dose_slot.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/services/dose_log_service.dart';
import 'package:saluteapp/core/services/local_alarm_service.dart';
import 'package:saluteapp/core/services/medication_check_service.dart';
import 'package:saluteapp/core/services/medication_reminder_service.dart';
import 'package:saluteapp/core/services/medication_service.dart';

const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _lateColor = Color(0xFFE67E22);
const _missedColor = Color(0xFFC62828);

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Checklist de tomas de un perfil: qué medicación toca cada día, con
/// "Tomada" / "No tomada" por toma. Se puede navegar a días anteriores
/// para corregir un olvido; los días futuros solo se pueden mirar.
class MedicationChecklistScreen extends StatefulWidget {
  final FamilyProfile profile;
  const MedicationChecklistScreen({super.key, required this.profile});

  @override
  State<MedicationChecklistScreen> createState() => _MedicationChecklistScreenState();
}

class _MedicationChecklistScreenState extends State<MedicationChecklistScreen> {
  late final Stream<List<Medication>> _medsStream;
  late Stream<List<DoseLog>> _logsStream;
  DateTime _day = _dayOf(DateTime.now());
  bool _notificationsOk = true;
  List<Medication> _meds = const [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    // onlyActive: false → un tratamiento ya terminado sigue apareciendo
    // en los días en que estaba vigente (dosesOn filtra por fechas).
    _medsStream = MedicationService.instance.watchMedications(
      widget.profile.id,
      onlyActive: false,
      decryptNotes: false,
    );
    _logsStream = DoseLogService.instance.watchDay(widget.profile.id, _day);
    _checkNotifications();
  }

  Future<void> _checkNotifications() async {
    final ok = await LocalAlarmService.instance.notificationsAllowed();
    if (mounted) setState(() => _notificationsOk = ok);
  }

  void _changeDay(int delta) {
    final next = DateTime(_day.year, _day.month, _day.day + delta);
    final limit = DateTime.now().add(const Duration(days: 1));
    if (next.isAfter(_dayOf(limit))) return;
    setState(() {
      _day = next;
      _logsStream = DoseLogService.instance.watchDay(widget.profile.id, _day);
    });
  }

  bool get _canMark => !_day.isAfter(_dayOf(DateTime.now()));

  String get _dayLabel {
    final today = _dayOf(DateTime.now());
    final diff = _day.difference(today).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == -1) return 'Ayer';
    if (diff == 1) return 'Mañana';
    return '${_weekdays[_day.weekday - 1]} ${_day.day} ${_months[_day.month - 1]}';
  }

  Future<void> _set(DoseSlot slot, DoseStatus? status) async {
    final key = slot.logId;
    setState(() => _busy.add(key));
    try {
      final remaining = await MedicationCheckService.instance.mark(
        profileId: slot.profileId,
        medication: slot.medication,
        scheduledAt: slot.scheduledAt,
        status: status,
        previous: slot.status,
      );
      if (!mounted) return;
      if (status == DoseStatus.taken && remaining != null && remaining <= slot.medication.unitsPerDay * 3) {
        _snack('Quedan $remaining unidades de ${slot.medication.name} en tu botiquín.');
      }
    } catch (_) {
      if (mounted) _snack('No se pudo guardar. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _sendTest() async {
    if (_meds.isEmpty) {
      _snack('Primero agregá una medicación para probar la alerta.');
      return;
    }
    try {
      await MedicationReminderService.instance.sendTest(
        profileId: widget.profile.id,
        profileName: widget.profile.name,
        medication: _meds.first,
      );
      _snack('Te mandamos una alerta de prueba en 5 segundos. Tocala para ver la pantalla de toma.');
    } catch (e) {
      _snack('No se pudo programar la alerta de prueba: $e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(
              title: 'Medicación de ${widget.profile.name}',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: StreamBuilder<List<Medication>>(
                stream: _medsStream,
                builder: (context, medSnap) {
                  if (medSnap.hasError) return _message('No se pudo cargar la medicación.\n${medSnap.error}');
                  if (!medSnap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: SaluteColors.primaryGreen));
                  }
                  _meds = medSnap.data!.where((m) => m.active).toList();
                  return StreamBuilder<List<DoseLog>>(
                    stream: _logsStream,
                    builder: (context, logSnap) {
                      if (logSnap.hasError) return _message('No se pudieron cargar las tomas.\n${logSnap.error}');
                      final slots = DoseSlot.buildForDay(
                        profileId: widget.profile.id,
                        profileName: widget.profile.name,
                        medications: _meds,
                        logs: logSnap.data ?? const [],
                        day: _day,
                      );
                      final noSchedule = _meds
                          .where((m) => m.coversDay(_day) && m.timesOfDay.isEmpty)
                          .toList();
                      return _buildList(slots, noSchedule);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
        ),
      );

  Widget _buildList(List<DoseSlot> slots, List<Medication> noSchedule) {
    final now = DateTime.now();
    final taken = slots.where((s) => s.status == DoseStatus.taken).length;
    final notTaken = slots.where((s) => s.status == DoseStatus.notTaken).length;
    final lateCount = slots.where((s) => s.stateAt(now) == DoseState.late).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _DaySelector(
          label: _dayLabel,
          onPrev: () => _changeDay(-1),
          onNext: _dayOf(_day).isBefore(_dayOf(now.add(const Duration(days: 1)))) ? () => _changeDay(1) : null,
        ),
        if (!_notificationsOk) ...[
          const SizedBox(height: 8),
          const _WarningBanner(
            text: 'Las notificaciones de Salute están desactivadas en el teléfono, así que no vas a '
                'recibir las alertas de medicación. Activalas desde los ajustes del sistema.',
          ),
        ],
        const SizedBox(height: 12),
        if (slots.isNotEmpty) _ProgressCard(total: slots.length, taken: taken, notTaken: notTaken, lateCount: lateCount),
        if (slots.isNotEmpty) const SizedBox(height: 16),
        if (slots.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              _meds.isEmpty
                  ? 'Todavía no hay medicación cargada para ${widget.profile.name}.'
                  : 'No hay tomas programadas para este día.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500),
            ),
          )
        else
          ...slots.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DoseTile(
                  slot: s,
                  state: s.stateAt(now),
                  canMark: _canMark,
                  busy: _busy.contains(s.logId),
                  onSet: (status) => _set(s, status),
                ),
              )),
        if (noSchedule.isNotEmpty) ...[
          const SizedBox(height: 8),
          _NoScheduleCard(medications: noSchedule),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _sendTest,
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Probar alerta'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SaluteColors.primaryGreen,
                  side: const BorderSide(color: SaluteColors.primaryGreen),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DaySelector extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  const _DaySelector({required this.label, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left), tooltip: 'Día anterior'),
        Expanded(
          child: Text(
            label[0].toUpperCase() + label.substring(1),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: SaluteColors.primaryGreen),
          ),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right), tooltip: 'Día siguiente'),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int total;
  final int taken;
  final int notTaken;
  final int lateCount;
  const _ProgressCard({required this.total, required this.taken, required this.notTaken, required this.lateCount});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (notTaken > 0) '$notTaken no tomada${notTaken == 1 ? '' : 's'}',
      if (lateCount > 0) '$lateCount atrasada${lateCount == 1 ? '' : 's'}',
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SaluteColors.primaryGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$taken de $total tomas',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : taken / total,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              color: Colors.white,
            ),
          ),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(parts.join('  ·  '), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _DoseTile extends StatelessWidget {
  final DoseSlot slot;
  final DoseState state;
  final bool canMark;
  final bool busy;
  final ValueChanged<DoseStatus?> onSet;

  const _DoseTile({
    required this.slot,
    required this.state,
    required this.canMark,
    required this.busy,
    required this.onSet,
  });

  String get _time {
    final t = slot.scheduledAt;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final med = slot.medication;
    final isTaken = state == DoseState.taken;
    final isNotTaken = state == DoseState.notTaken;
    final remainingDays = med.daysRemaining;

    final subtitle = [
      if (med.dose.trim().isNotEmpty) med.dose.trim(),
      if (med.isChronic) 'Crónico' else if (remainingDays != null) 'Faltan $remainingDays día${remainingDays == 1 ? '' : 's'}',
    ].join('  ·  ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: state == DoseState.late ? _lateColor.withValues(alpha: 0.6) : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _time,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: SaluteColors.primaryGreen),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        decoration: isTaken ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              if (state == DoseState.late)
                const Text('Atrasada', style: TextStyle(color: _lateColor, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ChoiceButton(
                  label: 'Tomada',
                  icon: Icons.check_rounded,
                  color: SaluteColors.primaryGreen,
                  selected: isTaken,
                  enabled: canMark && !busy,
                  onTap: () => onSet(isTaken ? null : DoseStatus.taken),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ChoiceButton(
                  label: 'No tomada',
                  icon: Icons.close_rounded,
                  color: _missedColor,
                  selected: isNotTaken,
                  enabled: canMark && !busy,
                  onTap: () => onSet(isNotTaken ? null : DoseStatus.notTaken),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : color;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: selected ? color : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color, width: 1.4),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String text;
  const _WarningBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _lateColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notifications_off_outlined, color: _lateColor, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.black87))),
        ],
      ),
    );
  }
}

class _NoScheduleCard extends StatelessWidget {
  final List<Medication> medications;
  const _NoScheduleCard({required this.medications});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sin horarios cargados', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            '${medications.map((m) => m.name).join(', ')} no tiene${medications.length == 1 ? '' : 'n'} horarios, '
            'por eso no aparece${medications.length == 1 ? '' : 'n'} en el checklist ni genera${medications.length == 1 ? '' : 'n'} alertas. '
            'Editá la medicación para agregar horarios.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
