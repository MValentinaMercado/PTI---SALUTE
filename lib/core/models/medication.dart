import 'package:cloud_firestore/cloud_firestore.dart';

/// Una medicación activa o histórica de un perfil, colgando de
/// `profiles/{profileId}/medicacion/{medId}`.
///
/// - name, dose, timesOfDay, startDate, durationDays, active: NO van
///   cifrados. Son necesarios para armar recordatorios (notificaciones
///   locales/push) y para calcular el progreso del tratamiento sin
///   tener que descifrar nada — igual que category/date en
///   MedicalRecord.
/// - `notes` (indicaciones del médico, motivo del tratamiento) SÍ va
///   cifrado, porque es el tipo de dato clínico sensible que definimos
///   en la arquitectura ("medicación detallada").
///
/// Checklist / alertas / botiquín (campos nuevos, todos con default para
/// que los documentos viejos sigan funcionando):
/// - `remindersEnabled`: si `false`, no se programan alarmas locales.
/// - `unitsPerDose`: cuántas unidades del botiquín se gastan por toma.
/// - `botiquinItemId`: ítem de `botiquin/{id}` vinculado (o null).
class Medication {
  final String id;
  final String name;
  final String dose; // ej: "1 comprimido", "10 ml"
  final List<String> timesOfDay; // ej: ["09:00", "21:00"]
  final DateTime startDate;
  final int? durationDays; // null = tratamiento crónico/indefinido
  final bool active;

  /// Contenido sensible ya DEScifrado (indicaciones, motivo).
  final String notes;

  final bool remindersEnabled;
  final int unitsPerDose;
  final String? botiquinItemId;

  const Medication({
    required this.id,
    required this.name,
    required this.dose,
    required this.startDate,
    this.timesOfDay = const [],
    this.durationDays,
    this.active = true,
    this.notes = '',
    this.remindersEnabled = true,
    this.unitsPerDose = 1,
    this.botiquinItemId,
  });

  /// Tratamiento crónico = sin duración definida.
  bool get isChronic => durationDays == null;

  /// Fecha de inicio sin hora (medianoche local).
  DateTime get startDay => DateTime(startDate.year, startDate.month, startDate.day);

  /// Primer instante en que el tratamiento YA no aplica (medianoche del
  /// día siguiente al último día). null si es crónico.
  DateTime? get endDate => durationDays != null
      ? DateTime(startDay.year, startDay.month, startDay.day + durationDays!)
      : null;

  /// Último día (inclusive) del tratamiento. null si es crónico.
  DateTime? get lastDay => durationDays != null
      ? DateTime(startDay.year, startDay.month, startDay.day + durationDays! - 1)
      : null;

  /// Progreso 0.0–1.0 del tratamiento. Para tratamientos crónicos
  /// (sin duración) siempre devuelve 1.0 (no aplica barra de "fin").
  double get progress {
    if (durationDays == null || durationDays == 0) return 1.0;
    final elapsed = DateTime.now().difference(startDay).inHours / 24.0;
    return (elapsed / durationDays!).clamp(0.0, 1.0);
  }

  /// Días restantes de tratamiento (null si es crónico, 0 si ya terminó).
  int? get daysRemaining {
    final end = endDate;
    if (end == null) return null;
    final remaining = end.difference(DateTime.now()).inHours / 24.0;
    return remaining < 0 ? 0 : remaining.ceil();
  }

  bool get isEndingSoon => (daysRemaining ?? 99) <= 3 && (daysRemaining ?? 99) > 0;
  bool get hasEnded => daysRemaining == 0;

  /// ¿Este tratamiento tiene tomas el día [day]? (solo mira fechas, no
  /// horarios; ignora `active`).
  bool coversDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(startDay)) return false;
    final last = lastDay;
    return last == null || !d.isAfter(last);
  }

  /// Horarios concretos (fecha + hora) de las tomas del día [day], ya
  /// ordenados. Vacío si la medicación está pausada, el día queda fuera
  /// del tratamiento o no tiene horarios cargados.
  List<DateTime> dosesOn(DateTime day) {
    if (!active || !coversDay(day)) return const [];
    final out = <DateTime>[];
    for (final t in timesOfDay) {
      final hm = parseTimeOfDay(t);
      if (hm == null) continue;
      out.add(DateTime(day.year, day.month, day.day, hm.$1, hm.$2));
    }
    out.sort();
    return out;
  }

  /// Unidades que se gastan por día si se cumplen todas las tomas.
  int get unitsPerDay => unitsPerDose * timesOfDay.length;

  Medication copyWith({String? id, bool? active, String? botiquinItemId}) {
    return Medication(
      id: id ?? this.id,
      name: name,
      dose: dose,
      startDate: startDate,
      timesOfDay: timesOfDay,
      durationDays: durationDays,
      active: active ?? this.active,
      notes: notes,
      remindersEnabled: remindersEnabled,
      unitsPerDose: unitsPerDose,
      botiquinItemId: botiquinItemId ?? this.botiquinItemId,
    );
  }

  factory Medication.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String decryptedNotes,
  ) {
    final data = doc.data() ?? {};
    final linked = data['botiquinItemId'] as String?;
    return Medication(
      id: doc.id,
      name: data['name'] as String? ?? '',
      dose: data['dose'] as String? ?? '',
      timesOfDay: (data['timesOfDay'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      durationDays: (data['durationDays'] as num?)?.toInt(),
      active: data['active'] as bool? ?? true,
      notes: decryptedNotes,
      remindersEnabled: data['remindersEnabled'] as bool? ?? true,
      unitsPerDose: ((data['unitsPerDose'] as num?)?.toInt() ?? 1).clamp(1, 99),
      botiquinItemId: (linked == null || linked.isEmpty) ? null : linked,
    );
  }

  Map<String, dynamic> metadataToFirestore() {
    return {
      'name': name,
      'dose': dose,
      'timesOfDay': timesOfDay,
      'startDate': Timestamp.fromDate(startDate),
      'durationDays': durationDays,
      'active': active,
      'remindersEnabled': remindersEnabled,
      'unitsPerDose': unitsPerDose,
      'botiquinItemId': botiquinItemId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

/// "21:30" → (21, 30). null si el formato no es válido.
(int, int)? parseTimeOfDay(String raw) {
  final parts = raw.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return (h, m);
}
