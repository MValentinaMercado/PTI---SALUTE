import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Obras sociales y prepagas más comunes, para el selector. No pretende ser
/// un padrón oficial: si la del usuario no está, la agrega con "Agregar otra
/// obra social" (queda guardada en su cuenta, ver [InsuranceService]).
const List<String> kCommonInsurances = [
  'OSDE',
  'Swiss Medical',
  'Galeno',
  'Medifé',
  'Omint',
  'Sancor Salud',
  'Accord Salud',
  'Avalian',
  'Jerárquicos Salud',
  'Medicus',
  'Hospital Italiano',
  'PAMI',
  'APROSS',
  'IOMA',
  'OSECAC',
  'OSPRERA',
  'OSDEPYM',
];

const int kInsuranceNameMaxLength = 60;

/// Limpia el nombre que tipeó el usuario: sin espacios de más y con un
/// largo razonable.
String normalizeInsuranceName(String raw) {
  final clean = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  return clean.length > kInsuranceNameMaxLength
      ? clean.substring(0, kInsuranceNameMaxLength).trim()
      : clean;
}

/// Obras sociales que el usuario agregó a mano (las que no están en
/// [kCommonInsurances]). Se guardan en su documento `users/{uid}`, campo
/// `customInsurances`, así le vuelven a aparecer en el selector (también
/// para los perfiles de su familia) sin tener que tipearlas de nuevo.
///
/// `users/{uid}` ya es de lectura/escritura solo para su dueño (ver
/// firestore.rules), no hace falta tocar las reglas.
class InsuranceService {
  InsuranceService._();
  static final InsuranceService instance = InsuranceService._();

  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>>? get _userDoc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid);
  }

  Future<List<String>> fetchCustom() async {
    final doc = _userDoc;
    if (doc == null) return const [];
    final snap = await doc.get();
    final raw = snap.data()?['customInsurances'] as List<dynamic>?;
    return raw?.whereType<String>().toList() ?? const [];
  }

  /// `merge: true` porque este documento también tiene `name`, `email`,
  /// `familyId`, etc. escritos por otros servicios; no queremos pisarlos.
  /// `arrayUnion` evita duplicados exactos.
  Future<void> addCustom(String name) async {
    final doc = _userDoc;
    if (doc == null) {
      throw StateError('No hay usuario logueado.');
    }
    await doc.set(
      {'customInsurances': FieldValue.arrayUnion([name])},
      SetOptions(merge: true),
    );
  }
}