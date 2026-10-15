import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:saluteapp/core/models/sos_contact.dart';

/// Contacto de emergencia del usuario logueado.
///
/// Se guarda como el campo `sosContact` dentro de `users/{uid}` (mismo
/// documento que ya escriben `AuthService`/`ProfileService`), así que
/// no hace falta agregar nada a `firestore.rules`: ese documento ya es
/// legible/escribible solo por su dueño.
class SosContactService {
  SosContactService._();
  static final SosContactService instance = SosContactService._();

  final _db = FirebaseFirestore.instance;

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('No hay usuario logueado.');
    }
    return uid;
  }

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _db.collection('users').doc(_uid);

  /// Stream en tiempo real del contacto SOS configurado (`null` si
  /// todavía no configuró ninguno, o si el documento de usuario no
  /// existe). Al ser un stream, si el usuario lo cambia desde otro
  /// dispositivo, esta pantalla se actualiza sola.
  Stream<SosContact?> watchSosContact() {
    return _userDoc.snapshots().map((doc) {
      final raw = doc.data()?['sosContact'] as Map<String, dynamic>?;
      if (raw == null) return null;
      return SosContact.fromMap(raw);
    });
  }

  Future<SosContact?> getSosContact() async {
    final doc = await _userDoc.get();
    final raw = doc.data()?['sosContact'] as Map<String, dynamic>?;
    if (raw == null) return null;
    return SosContact.fromMap(raw);
  }

  /// `merge: true` porque este documento también tiene `name`, `email`,
  /// etc. escritos por `AuthService`; no queremos pisarlos.
  Future<void> saveSosContact(SosContact contacto) async {
    await _userDoc.set(
      {'sosContact': contacto.toMap()},
      SetOptions(merge: true),
    );
  }

  Future<void> clearSosContact() async {
    await _userDoc.update({'sosContact': FieldValue.delete()});
  }
}