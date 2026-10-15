import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:saluteapp/core/models/dose_log.dart';

/// CRUD de `profiles/{profileId}/tomas` (registro de tomas de medicación).
///
/// Las queries por día filtran por rango sobre UN solo campo
/// (`scheduledAt`), así que no necesitan índice compuesto.
class DoseLogService {
  DoseLogService._();
  static final DoseLogService instance = DoseLogService._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String profileId) =>
      _db.collection('profiles').doc(profileId).collection('tomas');

  Query<Map<String, dynamic>> _dayQuery(String profileId, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    return _col(profileId)
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(end));
  }

  Stream<List<DoseLog>> watchDay(String profileId, DateTime day) {
    return _dayQuery(profileId, day).snapshots().map(
          (snap) => snap.docs.map(DoseLog.fromFirestore).toList(),
        );
  }

  Future<List<DoseLog>> fetchDay(String profileId, DateTime day) async {
    final snap = await _dayQuery(profileId, day).get();
    return snap.docs.map(DoseLog.fromFirestore).toList();
  }

  Future<DoseLog?> get(String profileId, String medicationId, DateTime scheduledAt) async {
    final doc = await _col(profileId).doc(DoseLog.idFor(medicationId, scheduledAt)).get();
    return doc.exists ? DoseLog.fromFirestore(doc) : null;
  }

  Future<void> save(String profileId, DoseLog log) {
    return _settle(_col(profileId).doc(DoseLog.idFor(log.medicationId, log.scheduledAt)).set(log.toFirestore()));
  }

  Future<void> clear(String profileId, String medicationId, DateTime scheduledAt) {
    return _settle(_col(profileId).doc(DoseLog.idFor(medicationId, scheduledAt)).delete());
  }

  /// Sin conexión, Firestore encola la escritura pero el Future no
  /// completa hasta que vuelve internet. Para que la UI no quede
  /// colgada (el listener local igual refleja el cambio al instante),
  /// esperamos como máximo unos segundos; un error real (permisos, etc.)
  /// sí se propaga.
  Future<void> _settle(Future<void> write) async {
    try {
      await write.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Queda encolada; se sincroniza sola al reconectar.
    }
  }
}
