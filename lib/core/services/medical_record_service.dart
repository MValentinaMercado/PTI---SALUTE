import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:saluteapp/core/models/medical_record.dart';
import 'package:saluteapp/core/services/crypto_service.dart';

/// CRUD de `profiles/{profileId}/historial`.
/// Cifra `details` antes de escribir y lo descifra al leer, para que
/// el resto de la app (pantallas) nunca tenga que pensar en criptografía.
class MedicalRecordService {
  MedicalRecordService._();
  static final MedicalRecordService instance = MedicalRecordService._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String profileId) =>
      _db.collection('profiles').doc(profileId).collection('historial');

  /// Nota: a diferencia de watchProfiles, acá no exponemos un Stream
  /// directo porque el descifrado es asíncrono por entrada. Se resuelve
  /// como Future<List<...>>; para listas grandes conviene paginar
  /// (ver `.limit()` / `startAfter`) en vez de traer todo de una vez.
  Future<List<MedicalRecord>> fetchRecords(String profileId, {int limit = 50}) async {
    final snap = await _col(profileId)
        .orderBy('date', descending: true)
        .limit(limit)
        .get();

    final records = <MedicalRecord>[];
    for (final doc in snap.docs) {
      final encrypted = doc.data()['encryptedDetails'] as String?;
      Map<String, dynamic> details;
      try {
        details = encrypted != null
            ? await CryptoService.instance.decryptJson(encrypted)
            : <String, dynamic>{};
      } catch (e) {
        // Si un único registro quedó indescifrable (ej: se generó una
        // clave nueva porque la vieja se invalidó, ver BUG-008), no
        // dejamos que arruine toda la lista de órdenes/historial: ese
        // registro se muestra vacío en vez de tirar abajo el fetch entero.
        debugPrint('MedicalRecordService: no se pudo descifrar ${doc.id}. $e');
        details = <String, dynamic>{};
      }
      records.add(MedicalRecord.fromFirestore(doc, details));
    }
    return records;
  }

  Future<String> addRecord(String profileId, MedicalRecord record) async {
    final data = record.metadataToFirestore();
    data['encryptedDetails'] = await CryptoService.instance.encryptJson(record.details);
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _col(profileId).add(data);
    return ref.id;
  }

  Future<void> updateRecord(String profileId, MedicalRecord record) async {
    final data = record.metadataToFirestore();
    data['encryptedDetails'] = await CryptoService.instance.encryptJson(record.details);
    await _col(profileId).doc(record.id).update(data);
  }

  Future<void> deleteRecord(String profileId, String recordId) async {
    await _col(profileId).doc(recordId).delete();
  }

  /// Cambia solo `status` (pendiente ⇄ completado) sin tocar
  /// `encryptedDetails` — no hace falta re-cifrar/re-descifrar para
  /// alternar un flag que ya vive sin cifrar (mismo patrón que
  /// `AgendaService.setStatus`).
  Future<void> setStatus(String profileId, String recordId, RecordStatus status) async {
    await _col(profileId).doc(recordId).update({'status': status.name});
  }
}