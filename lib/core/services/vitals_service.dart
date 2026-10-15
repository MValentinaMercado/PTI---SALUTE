import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:saluteapp/core/models/vital_entry.dart';

/// CRUD de `vitals` (registros de signos vitales / bienestar).
/// Colección top-level con `uid` (quien lo cargó) y `profileId` (de
/// quién es el dato). La query filtra por `profileId`, no por `uid`:
/// así, si el dueño del perfil habilitó a otro miembro de la familia
/// para ver sus datos clínicos (`FamilyProfile.sharedWithUids`), la
/// regla de Firestore (`canSeeClinicalData`) es quien decide si ese
/// pedido se puede leer o no —si filtráramos por `uid` acá, ese
/// miembro nunca vería nada aunque la regla se lo permitiera, porque
/// ni siquiera pediríamos esos documentos—.
class VitalsService {
  VitalsService._();
  static final VitalsService instance = VitalsService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('vitals');

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('No hay usuario logueado.');
    }
    return uid;
  }

  /// Stream en tiempo real de los registros de un perfil, más recientes
  /// primero. Si quien pregunta no administra el perfil ni tiene acceso
  /// compartido, Firestore rechaza la consulta entera (permission-denied)
  /// en vez de devolver una lista vacía silenciosa.
  Stream<List<VitalEntry>> watchForProfile(String profileId) {
    return _col.where('profileId', isEqualTo: profileId).snapshots().map((snap) {
      final entries = snap.docs.map(VitalEntry.fromFirestore).toList();
      entries.sort((a, b) => b.date.compareTo(a.date));
      return entries;
    });
  }

  Future<String> addEntry(VitalEntry entry) async {
    final data = entry.toFirestore();
    data['uid'] = _uid;
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _col.add(data);
    return ref.id;
  }

  Future<void> deleteEntry(String entryId) async {
    await _col.doc(entryId).delete();
  }
}
