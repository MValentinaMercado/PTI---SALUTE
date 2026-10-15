import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipo de evento de agenda médica.
enum AgendaEventType { turno, estudio, vacuna, control, medicacion, otro }

AgendaEventType agendaEventTypeFromString(String value) {
  return AgendaEventType.values.firstWhere(
        (t) => t.name == value,
    orElse: () => AgendaEventType.otro,
  );
}

enum AgendaEventStatus { pendiente, completado, cancelado }

AgendaEventStatus agendaEventStatusFromString(String value) {
  return AgendaEventStatus.values.firstWhere(
        (s) => s.name == value,
    orElse: () => AgendaEventStatus.pendiente,
  );
}

/// Turnos, estudios, vacunas y controles, colgando de la colección
/// top-level `agenda/{eventId}` (ver firestore.rules), ligados a un
/// perfil vía `profileId`. No es sensible (no hay diagnóstico ni
/// resultado acá, solo el "qué y cuándo"), así que no se cifra.
class AgendaEvent {
  final String id;
  final String ownerUid;
  final String profileId;
  final String profileName; // denormalizado, para no tener que joinear al listar
  final AgendaEventType type;
  final AgendaEventStatus status;
  final String title;
  final String location;
  final DateTime date;
  /// Minutos antes del evento en que se debe disparar la alarma local.
  /// `null` = sin recordatorio configurado.
  final int? reminderMinutesBefore;

  const AgendaEvent({
    required this.id,
    required this.ownerUid,
    required this.profileId,
    required this.profileName,
    required this.title,
    required this.date,
    this.type = AgendaEventType.turno,
    this.status = AgendaEventStatus.pendiente,
    this.location = '',
    this.reminderMinutesBefore,
  });

  /// Momento en que debería sonar la alarma, o `null` si no hay recordatorio
  /// configurado o si ya pasó.
  DateTime? get reminderTime {
    if (reminderMinutesBefore == null) return null;
    final t = date.subtract(Duration(minutes: reminderMinutesBefore!));
    return t.isAfter(DateTime.now()) ? t : null;
  }

  bool get isUpcoming => status == AgendaEventStatus.pendiente && date.isAfter(DateTime.now());
  bool get isOverdue => status == AgendaEventStatus.pendiente && date.isBefore(DateTime.now());

  factory AgendaEvent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AgendaEvent(
      id: doc.id,
      ownerUid: data['uid'] as String? ?? '',
      profileId: data['profileId'] as String? ?? '',
      profileName: data['profileName'] as String? ?? '',
      type: agendaEventTypeFromString(data['type'] as String? ?? 'turno'),
      status: agendaEventStatusFromString(data['status'] as String? ?? 'pendiente'),
      title: data['title'] as String? ?? '',
      location: data['location'] as String? ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reminderMinutesBefore: (data['reminderMinutesBefore'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': ownerUid,
      'profileId': profileId,
      'profileName': profileName,
      'type': type.name,
      'status': status.name,
      'title': title,
      'location': location,
      'date': Timestamp.fromDate(date),
      'reminderMinutesBefore': reminderMinutesBefore,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}