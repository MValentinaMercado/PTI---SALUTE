import 'package:cloud_firestore/cloud_firestore.dart';

/// Nivel de estrés autopercibido (carga manual — no hay sensor real).
enum StressLevel { bajo, medio, alto }

StressLevel? stressLevelFromString(String? value) {
  if (value == null) return null;
  for (final s in StressLevel.values) {
    if (s.name == value) return s;
  }
  return null;
}

/// Un registro puntual de signos vitales / métricas de bienestar de un
/// perfil: `vitals/{entryId}`, top-level y filtrado por `uid` (mismo
/// patrón que `AgendaEvent` o `MedicineItem`). No es historia clínica
/// (no hay diagnóstico ni observación médica acá, solo números), así
/// que no pasa por `CryptoService` — coincide con el criterio de la
/// arquitectura del proyecto ("Estados"/metadatos consultables sin cifrar).
///
/// Todos los campos numéricos son opcionales: un registro puede cargar
/// solo lo que el usuario tenga a mano ese día (ej: solo el peso).
class VitalEntry {
  final String id;
  final String ownerUid;
  final String profileId;
  final DateTime date;
  final int? heartRate; // BPM
  final double? bloodOxygen; // porcentaje
  final double? sleepHours;
  final double? weightKg;
  final int? steps;
  final int? calories;
  final StressLevel? stressLevel;

  const VitalEntry({
    required this.id,
    required this.ownerUid,
    required this.profileId,
    required this.date,
    this.heartRate,
    this.bloodOxygen,
    this.sleepHours,
    this.weightKg,
    this.steps,
    this.calories,
    this.stressLevel,
  });

  factory VitalEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return VitalEntry(
      id: doc.id,
      ownerUid: data['uid'] as String? ?? '',
      profileId: data['profileId'] as String? ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      heartRate: (data['heartRate'] as num?)?.toInt(),
      bloodOxygen: (data['bloodOxygen'] as num?)?.toDouble(),
      sleepHours: (data['sleepHours'] as num?)?.toDouble(),
      weightKg: (data['weightKg'] as num?)?.toDouble(),
      steps: (data['steps'] as num?)?.toInt(),
      calories: (data['calories'] as num?)?.toInt(),
      stressLevel: stressLevelFromString(data['stressLevel'] as String?),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': ownerUid,
      'profileId': profileId,
      'date': Timestamp.fromDate(date),
      if (heartRate != null) 'heartRate': heartRate,
      if (bloodOxygen != null) 'bloodOxygen': bloodOxygen,
      if (sleepHours != null) 'sleepHours': sleepHours,
      if (weightKg != null) 'weightKg': weightKg,
      if (steps != null) 'steps': steps,
      if (calories != null) 'calories': calories,
      if (stressLevel != null) 'stressLevel': stressLevel!.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
