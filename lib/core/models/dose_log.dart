import 'package:cloud_firestore/cloud_firestore.dart';

/// Resultado que el usuario marcó para una toma. "Pendiente" no existe
/// como valor: es la ausencia de registro.
enum DoseStatus { taken, notTaken }

DoseStatus doseStatusFromString(String? value) {
  return DoseStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => DoseStatus.notTaken,
  );
}

/// Registro de UNA toma concreta (medicación + fecha/hora programada),
/// colgando de `profiles/{profileId}/tomas/{doseId}`.
///
/// El id es determinístico ([idFor]): marcar dos veces la misma toma
/// pisa el mismo documento en vez de duplicarlo, y se puede leer/borrar
/// sin hacer una query.
///
/// No va cifrado: es "qué toma y cuándo" (mismo criterio que `agenda` y
/// que los metadatos de `medicacion`), no un diagnóstico.
class DoseLog {
  final String id;
  final String medicationId;
  final String medicationName; // denormalizado, por si después se borra la medicación
  final DateTime scheduledAt;
  final DoseStatus status;
  final DateTime? loggedAt;

  const DoseLog({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.scheduledAt,
    required this.status,
    this.loggedAt,
  });

  static String idFor(String medicationId, DateTime scheduledAt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${medicationId}_${scheduledAt.year}${two(scheduledAt.month)}${two(scheduledAt.day)}'
        '${two(scheduledAt.hour)}${two(scheduledAt.minute)}';
  }

  factory DoseLog.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return DoseLog(
      id: doc.id,
      medicationId: data['medicationId'] as String? ?? '',
      medicationName: data['medicationName'] as String? ?? '',
      scheduledAt: (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: doseStatusFromString(data['status'] as String?),
      loggedAt: (data['loggedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'medicationId': medicationId,
      'medicationName': medicationName,
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'status': status.name,
      'loggedAt': FieldValue.serverTimestamp(),
    };
  }
}
