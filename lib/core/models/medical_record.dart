import 'package:cloud_firestore/cloud_firestore.dart';

/// Categorías del historial médico modular (consultas, odontología,
/// psicología, laboratorio, imágenes, etc. — ver análisis del proyecto).
enum RecordCategory {
  consulta,
  estudio,
  vacuna,
  odontologia,
  psicologia,
  cardiologia,
  laboratorio,
  triaje,
  animo,
  otro,
}

RecordCategory recordCategoryFromString(String value) {
  return RecordCategory.values.firstWhere(
    (c) => c.name == value,
    orElse: () => RecordCategory.otro,
  );
}

/// Estado de una orden/estudio: pedido pero sin resultado todavía, o ya
/// completado. Es metadato de consulta (no clínico en sí mismo), así que
/// —igual que `category`, `date` o `professional`— NO va cifrado (ver
/// "Qué se cifra y qué no" en la arquitectura del proyecto: "Estados" está
/// listado explícitamente como campo consultable sin cifrar).
enum RecordStatus { pendiente, completado }

RecordStatus recordStatusFromString(String value) {
  return RecordStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => RecordStatus.completado,
  );
}

/// Una entrada del historial médico, colgando de
/// `profiles/{profileId}/historial/{recordId}`.
///
/// - Los campos de arriba (category, date, professional) NO van cifrados:
///   son metadatos necesarios para poder listar/ordenar/filtrar.
/// - `details` SÍ va cifrado (diagnóstico, observaciones, resultados):
///   se guarda como un único string opaco (ver CryptoService).
class MedicalRecord {
  final String id;
  final RecordCategory category;
  final DateTime date;
  final String professional;
  final String title;

  /// Institución/lugar (laboratorio, clínica, etc.) donde se hizo o se
  /// va a hacer el estudio. Metadato consultable, no cifrado.
  final String institution;

  /// Pendiente (orden emitida, resultado todavía no cargado) o
  /// completado. Ver `RecordStatus`.
  final RecordStatus status;

  /// Contenido sensible ya DEScifrado, para uso en memoria/UI.
  /// Nunca se sube así a Firestore: pasa por CryptoService.encryptJson.
  final Map<String, dynamic> details;

  const MedicalRecord({
    required this.id,
    required this.category,
    required this.date,
    required this.title,
    this.professional = '',
    this.institution = '',
    this.status = RecordStatus.completado,
    this.details = const {},
  });

  /// Arma la instancia a partir del doc de Firestore + el contenido
  /// ya descifrado (el descifrado es async y lo resuelve el service,
  /// no el modelo).
  factory MedicalRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> decryptedDetails,
  ) {
    final data = doc.data() ?? {};
    return MedicalRecord(
      id: doc.id,
      category: recordCategoryFromString(data['category'] as String? ?? 'otro'),
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      title: data['title'] as String? ?? '',
      professional: data['professional'] as String? ?? '',
      institution: data['institution'] as String? ?? '',
      status: recordStatusFromString(data['status'] as String? ?? 'completado'),
      details: decryptedDetails,
    );
  }

  /// Campos NO sensibles, listos para guardar directo en Firestore.
  Map<String, dynamic> metadataToFirestore() {
    return {
      'category': category.name,
      'date': Timestamp.fromDate(date),
      'title': title,
      'professional': professional,
      'institution': institution,
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
