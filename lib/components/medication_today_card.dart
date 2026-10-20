import 'package:flutter/material.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:saluteapp/core/active_profile_controller.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/dose_log.dart';
import 'package:saluteapp/core/models/dose_slot.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/services/dose_log_service.dart';
import 'package:saluteapp/core/services/medication_service.dart';
import 'package:saluteapp/profile/medication_checklist_screen.dart';

/// Resumen de las tomas de hoy del perfil activo, para el dashboard.
/// Si el perfil no tiene tomas programadas hoy (o no se puede leer su
/// medicación) no ocupa lugar. Tocarlo abre el checklist completo.
class MedicationTodayCard extends StatelessWidget {
  const MedicationTodayCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ActiveProfileController.instance,
      builder: (context, _) {
        final profile = ActiveProfileController.instance.active;
        if (profile == null) return const SizedBox.shrink();
        return _TodayBody(key: ValueKey(profile.id), profile: profile);
      },
    );
  }
}

class _TodayBody extends StatefulWidget {
  final FamilyProfile profile;
  const _TodayBody({super.key, required this.profile});

  @override
  State<_TodayBody> createState() => _TodayBodyState();
}

class _TodayBodyState extends State<_TodayBody> {
  late final Stream<List<Medication>> _medsStream;
  late final Stream<List<DoseLog>> _logsStream;

  @override
  void initState() {
    super.initState();
    _medsStream = MedicationService.instance.watchMedications(
      widget.profile.id,
      onlyActive: true,
      decryptNotes: false,
    );
    _logsStream = DoseLogService.instance.watchDay(widget.profile.id, DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Medication>>(
      stream: _medsStream,
      builder: (context, medSnap) {
        return StreamBuilder<List<DoseLog>>(
          stream: _logsStream,
          builder: (context, logSnap) {
            // Sin permiso de lectura (perfil ajeno sin consentimiento) o
            // sin datos todavía: no mostramos nada en el dashboard.
            if (medSnap.hasError || logSnap.hasError || !medSnap.hasData) {
              return const SizedBox.shrink();
            }
            final now = DateTime.now();
            final slots = DoseSlot.buildForDay(
              profileId: widget.profile.id,
              profileName: widget.profile.name,
              medications: medSnap.data!,
              logs: logSnap.data ?? const [],
              day: now,
            );
            if (slots.isEmpty) return const SizedBox.shrink();

            final taken = slots.where((s) => s.status == DoseStatus.taken).length;
            final overdue = slots.where((s) => s.stateAt(now) == DoseState.late).length;
            final next = slots.where((s) => s.status == null).toList();
            final nextSlot = next.isEmpty ? null : next.first;

            String subtitle;
            if (overdue > 0) {
              subtitle = '$overdue toma${overdue == 1 ? '' : 's'} atrasada${overdue == 1 ? '' : 's'}';
            } else if (nextSlot != null) {
              final t = nextSlot.scheduledAt;
              subtitle = 'Próxima: ${nextSlot.medication.name} a las '
                  '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
            } else {
              subtitle = 'Ya registraste todas las tomas de hoy';
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Medicación de hoy',
                    style: TextStyle(fontSize: DsFontSize.h4, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => MedicationChecklistScreen(profile: widget.profile)),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            height: 52,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: taken / slots.length,
                                  strokeWidth: 5,
                                  backgroundColor: SaluteColors.lightGreen,
                                  color: SaluteColors.primaryGreen,
                                ),
                                Text(
                                  '$taken/${slots.length}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.profile.name,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: overdue > 0 ? SaluteColors.warning : SaluteColors.textMuted,
                                    fontWeight: overdue > 0 ? FontWeight.w700 : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: SaluteColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
