import 'package:saluteapp/core/models/dose_log.dart';
import 'package:saluteapp/core/models/medication.dart';

/// Estado visible de una toma en el checklist.
enum DoseState { pending, late, taken, notTaken }

/// Una toma programada de un día (medicación + horario) junto con su
/// registro, si el usuario ya la marcó. Es una vista calculada: no se
/// guarda en Firestore (lo que se guarda es el [DoseLog]).
class DoseSlot {
  /// Pasado este tiempo desde el horario sin marcarse, la toma se
  /// considera atrasada.
  static const Duration lateAfter = Duration(minutes: 30);

  final String profileId;
  final String profileName;
  final Medication medication;
  final DateTime scheduledAt;
  final DoseLog? log;

  const DoseSlot({
    required this.profileId,
    required this.profileName,
    required this.medication,
    required this.scheduledAt,
    this.log,
  });

  DoseStatus? get status => log?.status;

  String get logId => DoseLog.idFor(medication.id, scheduledAt);

  DoseState stateAt(DateTime now) {
    switch (log?.status) {
      case DoseStatus.taken:
        return DoseState.taken;
      case DoseStatus.notTaken:
        return DoseState.notTaken;
      case null:
        return now.isAfter(scheduledAt.add(lateAfter)) ? DoseState.late : DoseState.pending;
    }
  }

  /// Arma las tomas del día [day] para [medications], cruzándolas con los
  /// [logs] de ese día. Ordenadas por horario y, a igual horario, por nombre.
  static List<DoseSlot> buildForDay({
    required String profileId,
    required String profileName,
    required List<Medication> medications,
    required List<DoseLog> logs,
    required DateTime day,
  }) {
    final byId = {for (final l in logs) l.id: l};
    final slots = <DoseSlot>[];
    for (final m in medications) {
      for (final at in m.dosesOn(day)) {
        slots.add(DoseSlot(
          profileId: profileId,
          profileName: profileName,
          medication: m,
          scheduledAt: at,
          log: byId[DoseLog.idFor(m.id, at)],
        ));
      }
    }
    slots.sort((a, b) {
      final byTime = a.scheduledAt.compareTo(b.scheduledAt);
      if (byTime != 0) return byTime;
      return a.medication.name.toLowerCase().compareTo(b.medication.name.toLowerCase());
    });
    return slots;
  }
}
