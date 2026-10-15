import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/services/crypto_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';

/// Una medicación junto con el perfil al que pertenece (para pantallas
/// que mezclan tratamientos de varios perfiles, ej. Mi Botiquín).
class ProfileMedication {
  final FamilyProfile profile;
  final Medication medication;
  const ProfileMedication(this.profile, this.medication);
}

/// CRUD de `profiles/{profileId}/medicacion`.
/// Cifra `notes` antes de escribir y lo descifra al leer.
///
/// A diferencia de MedicalRecordService (que expone Future por entrada),
/// acá exponemos un Stream: la pantalla de perfil necesita reflejar en
/// vivo altas/bajas de medicación (ej. al agregar una desde el form).
/// Como el descifrado es async, usamos `asyncMap` sobre el snapshot.
class MedicationService {
  MedicationService._();
  static final MedicationService instance = MedicationService._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String profileId) =>
      _db.collection('profiles').doc(profileId).collection('medicacion');

  /// [decryptNotes]: poné `false` cuando no necesites las indicaciones
  /// (ej. el generador de notificaciones solo mira nombre, dosis y fecha
  /// de fin). Así ni se toca la clave de cifrado y un registro
  /// indescifrable no puede romper esa pantalla.
  Stream<List<Medication>> watchMedications(
      String profileId, {
        bool onlyActive = true,
        bool decryptNotes = true,
      }) {
    var query = _col(profileId).orderBy('startDate', descending: true);
    return query.snapshots().asyncMap((snap) async {
      final meds = <Medication>[];
      for (final doc in snap.docs) {
        var notes = '';
        final encrypted = doc.data()['encryptedNotes'] as String?;
        if (decryptNotes && encrypted != null && encrypted.isNotEmpty) {
          try {
            final m = await CryptoService.instance.decryptJson(encrypted);
            notes = m['notes'] as String? ?? '';
          } catch (e) {
            // Nota cifrada con una clave que ya no existe (ver BUG-008):
            // se muestra vacía en vez de tirar abajo toda la lista.
            debugPrint('MedicationService: no se pudo descifrar ${doc.id}. $e');
          }
        }
        meds.add(Medication.fromFirestore(doc, notes));
      }
      if (onlyActive) {
        meds.removeWhere((m) => !m.active || m.hasEnded);
      }
      return meds;
    });
  }

  Future<String> addMedication(String profileId, Medication medication) async {
    final data = medication.metadataToFirestore();
    data['encryptedNotes'] = await CryptoService.instance.encryptJson({'notes': medication.notes});
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _col(profileId).add(data);
    return ref.id;
  }

  Future<void> updateMedication(String profileId, Medication medication) async {
    final data = medication.metadataToFirestore();
    data['encryptedNotes'] = await CryptoService.instance.encryptJson({'notes': medication.notes});
    await _col(profileId).doc(medication.id).update(data);
  }

  /// Lee una medicación puntual (sin descifrar las indicaciones por
  /// defecto: las pantallas de alerta no las necesitan).
  Future<Medication?> getMedication(
    String profileId,
    String medicationId, {
    bool decryptNotes = false,
  }) async {
    final doc = await _col(profileId).doc(medicationId).get();
    if (!doc.exists) return null;
    var notes = '';
    final encrypted = doc.data()?['encryptedNotes'] as String?;
    if (decryptNotes && encrypted != null && encrypted.isNotEmpty) {
      try {
        final m = await CryptoService.instance.decryptJson(encrypted);
        notes = m['notes'] as String? ?? '';
      } catch (e) {
        debugPrint('MedicationService: no se pudo descifrar $medicationId. $e');
      }
    }
    return Medication.fromFirestore(doc, notes);
  }

  /// Vincula (o desvincula, con null) una medicación a un ítem de Mi
  /// Botiquín sin tocar el resto de sus campos.
  Future<void> linkBotiquin(String profileId, String medicationId, String? botiquinItemId) async {
    await _col(profileId).doc(medicationId).update({
      'botiquinItemId': botiquinItemId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Tratamientos activos de TODOS los perfiles que administra el usuario
  /// logueado (los perfiles de otros miembros de la familia no se
  /// incluyen: no son sus tomas ni su botiquín). Un perfil que falla al
  /// leerse se omite en vez de tirar abajo el resto.
  Future<List<ProfileMedication>> loadAllManagedByMe() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return const [];
    final profiles = await ProfileService.instance.watchProfiles().first;
    final out = <ProfileMedication>[];
    for (final p in profiles.where((p) => p.ownerUid == myUid)) {
      try {
        final meds = await watchMedications(p.id, onlyActive: true, decryptNotes: false).first;
        out.addAll(meds.map((m) => ProfileMedication(p, m)));
      } catch (e) {
        debugPrint('MedicationService: no se pudo leer medicación de ${p.id}. $e');
      }
    }
    return out;
  }

  Future<void> setActive(String profileId, String medicationId, bool active) async {
    await _col(profileId).doc(medicationId).update({'active': active});
  }

  Future<void> deleteMedication(String profileId, String medicationId) async {
    await _col(profileId).doc(medicationId).delete();
  }
}