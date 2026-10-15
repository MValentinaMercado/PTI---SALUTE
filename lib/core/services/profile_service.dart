import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:saluteapp/core/models/family_profile.dart';

/// CRUD de `profiles` (personas y mascotas del grupo familiar).
/// Todo queda filtrado por `uid` del usuario logueado; las reglas de
/// Firestore (ver firestore.rules) impiden leer perfiles ajenos aunque
/// se conozca el id.
class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('profiles');

  /// Datos clínicos del perfil (grupo sanguíneo, alergias, contacto de
  /// emergencia, obra social, último chequeo, peso). Es una subcolección
  /// aparte, con reglas más estrictas que el documento raíz: ver
  /// `datos_clinicos` en firestore.rules.
  DocumentReference<Map<String, dynamic>> _fichaRef(String profileId) =>
      _col.doc(profileId).collection('datos_clinicos').doc('ficha');

  /// Misma regla que `canSeeClinicalData` en firestore.rules.
  bool _canSeeClinical(FamilyProfile p) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && (p.ownerUid == uid || p.sharedWithUids.contains(uid));
  }

  /// Completa [p] con su ficha clínica si el usuario tiene permiso; si
  /// no, devuelve el perfil con los campos clínicos vacíos (aunque el
  /// documento raíz todavía tenga valores viejos sin migrar).
  Future<FamilyProfile> _withClinical(FamilyProfile p) async {
    if (!_canSeeClinical(p)) return p.withoutClinical();
    try {
      final doc = await _fichaRef(p.id).get();
      return p.withClinical(doc.data());
    } catch (e) {
      debugPrint('ProfileService: no se pudo leer la ficha de ${p.id}. $e');
      return p;
    }
  }

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('No hay usuario logueado.');
    }
    return uid;
  }

  /// Stream en tiempo real de todos los perfiles visibles para el
  /// usuario actual.
  ///
  /// BUG-002/FEAT-001: si el usuario todavía no pertenece a ninguna
  /// familia (`users/{uid}.familyId` es null), se comporta como antes:
  /// solo sus propios perfiles (`uid == _uid`). Si ya pertenece a una
  /// familia, se ven TODOS los perfiles de esa familia —miembros
  /// independientes y dependientes de cualquiera de ellos—, filtrando
  /// por `familyId` en vez de por `uid`. `FamilyService` es quien se
  /// encarga de sellar `familyId` en cada perfil al crear/unirse a una
  /// familia.
  ///
  /// Nota de diseño: seguimos sin `orderBy` en la query (ver nota
  /// anterior) para no depender de un índice compuesto que no existe
  /// en el proyecto; el orden se aplica en memoria.
  Stream<List<FamilyProfile>> watchProfiles() {
    return _db.collection('users').doc(_uid).snapshots().asyncExpand((userDoc) {
      final familyId = userDoc.data()?['familyId'] as String?;
      final query = familyId != null
          ? _col.where('familyId', isEqualTo: familyId)
          : _col.where('uid', isEqualTo: _uid);
      // Cuando cambia el documento raíz (incluido el `updatedAt` que se
      // toca al guardar la ficha, o un cambio en `sharedWithUids`), se
      // vuelve a leer la ficha de cada perfil permitido.
      return query.snapshots().asyncMap((snap) async {
        final base = snap.docs.map(FamilyProfile.fromFirestore).toList();
        final profiles = (await Future.wait(base.map(_withClinical))).toList();
        profiles.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return profiles;
      });
    });
  }

  Future<FamilyProfile?> getProfile(String profileId) async {
    final doc = await _col.doc(profileId).get();
    if (!doc.exists) return null;
    return _withClinical(FamilyProfile.fromFirestore(doc));
  }

  /// Stream del perfil propio (isSelf) del usuario logueado, derivado de
  /// [watchProfiles]. Es la única fuente de verdad para "cómo se llama
  /// el usuario actual" en el resto de la app (saludo del dashboard,
  /// etc.) — a diferencia de antes, que algunas pantallas usaban
  /// `FirebaseAuth.currentUser.displayName` directo (el nombre de
  /// Google, sin pasar por Firestore) y otras usaban este perfil, y
  /// terminaban desincronizadas entre sí.
  Stream<FamilyProfile?> watchSelfProfile() {
    return watchProfiles().map(
      (profiles) => selfOf(profiles, FirebaseAuth.instance.currentUser?.uid),
    );
  }

  /// El perfil propio de [uid] dentro de [profiles].
  ///
  /// OJO: `isSelf` NO alcanza. `watchProfiles()` devuelve los perfiles de
  /// TODA la familia, y cada integrante tiene el suyo con `isSelf == true`;
  /// quedarse con el primer `isSelf` agarraba el de cualquier integrante
  /// (según el orden alfabético) y no el de quien está logueado. El perfil
  /// propio es el que es `isSelf` Y lo administra este usuario.
  static FamilyProfile? selfOf(List<FamilyProfile> profiles, String? uid) {
    if (uid == null) return null;
    for (final p in profiles) {
      if (p.isSelf && p.ownerUid == uid) return p;
    }
    return null;
  }

  /// Garantiza que el usuario logueado tenga su propio perfil
  /// (`isSelf: true`) en `profiles`. Se llama una vez por sesión desde
  /// `AuthGate` (y también al registrarse), así que cubre tanto cuentas
  /// nuevas como cuentas viejas que se crearon antes de que existiera
  /// este concepto (ej: Valentina).
  ///
  /// Devuelve el id del perfil propio (existente o recién creado).
  /// No usa `createProfile` porque necesita el `uid` explícito antes de
  /// escribir, para no depender del usuario logueado en el momento del
  /// registro (justo después de crear la cuenta, `currentUser` puede no
  /// estar propagado todavía en algunos flujos).
  Future<String> ensureSelfProfile({
    required String uid,
    required String name,
    String lastName = '',
    String? username,
  }) async {
    // Mueve a la subcolección protegida los datos clínicos que los perfiles
    // viejos todavía tienen en el documento raíz. En segundo plano: si
    // falla, se reintenta en la próxima sesión.
    unawaited(migrateLegacyClinicalFields(uid).catchError((Object e) {
      debugPrint('ProfileService: migración de datos clínicos pendiente. $e');
    }));

    final existing = await _col
        .where('uid', isEqualTo: uid)
        .where('isSelf', isEqualTo: true)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      return existing.docs.first.id;
    }

    final data = FamilyProfile(
      id: '',
      ownerUid: uid,
      type: ProfileType.persona,
      name: name,
      lastName: lastName,
      username: username,
      relation: 'Yo',
      isSelf: true,
      // El dueño de la cuenta siempre es "independiente" de sí mismo:
      // administra su propio perfil porque tiene su propio login.
      linkedUid: uid,
    ).toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _col.add(data);
    return ref.id;
  }

  /// Crea un perfil nuevo (dependiente: hijo, mascota, etc.) para el
  /// usuario logueado. Si ya pertenece a una familia, el perfil nuevo
  /// queda visible para toda la familia desde el vamos (mismo
  /// `familyId`); si no, queda privado hasta que el usuario cree o se
  /// una a una familia.
  Future<String> createProfile(FamilyProfile profile) async {
    final data = profile.copyWith().toFirestore();
    data['uid'] = _uid;
    data['createdAt'] = FieldValue.serverTimestamp();
    final userDoc = await _db.collection('users').doc(_uid).get();
    final familyId = userDoc.data()?['familyId'] as String?;
    if (familyId != null) {
      data['familyId'] = familyId;
    }
    final ref = await _col.add(data);
    if (profile.hasClinicalData) {
      // Va después del alta del perfil: la regla de la ficha consulta el
      // documento raíz para saber quién lo administra.
      try {
        await _fichaRef(ref.id).set(profile.clinicalToFirestore());
      } catch (_) {
        await ref.delete();
        rethrow;
      }
    }
    return ref.id;
  }

  Future<void> updateProfile(FamilyProfile profile) async {
    final batch = _db.batch();
    // Además de guardar lo básico, borra del documento raíz cualquier
    // dato clínico viejo: así editar un perfil también lo migra.
    final root = <String, dynamic>{
      ...profile.toFirestore(),
      for (final k in FamilyProfile.clinicalKeys) k: FieldValue.delete(),
    };
    batch.update(_col.doc(profile.id), root);
    batch.set(_fichaRef(profile.id), profile.clinicalToFirestore(), SetOptions(merge: true));
    await batch.commit();
  }

  /// Guarda solo la foto de perfil (`''` = quitar). Update puntual en el
  /// documento raíz, igual que `setInsurance`: no pisa el resto del perfil
  /// con una copia que puede estar desactualizada. [avatarUrl] es una URL
  /// http(s) o una imagen `data:image/jpeg;base64,...` (ver `AvatarPhoto`).
  Future<void> setAvatar(String profileId, String avatarUrl) async {
    await _col.doc(profileId).update({
      'avatarUrl': avatarUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Migración única: pasa de `profiles/{id}` a `profiles/{id}/datos_clinicos/ficha`
  /// los datos clínicos que quedaron en el documento raíz y los borra de
  /// ahí. Solo toca los perfiles que administra [uid] (las reglas no
  /// dejan más); los dependientes se migran cuando entra su tutor.
  /// Es idempotente: si no hay nada que mover, no escribe.
  Future<void> migrateLegacyClinicalFields(String uid) async {
    final snap = await _col.where('uid', isEqualTo: uid).get();
    for (final doc in snap.docs) {
      final data = doc.data();
      final legacy = <String, dynamic>{
        for (final k in FamilyProfile.clinicalKeys)
          if (data.containsKey(k)) k: data[k],
      };
      if (legacy.isEmpty) continue;
      final batch = _db.batch();
      batch.set(
        _fichaRef(doc.id),
        {...legacy, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      batch.update(doc.reference, {
        for (final k in legacy.keys) k: FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    }
  }

  /// Actualiza con quién se comparten los datos clínicos de este perfil
  /// (agenda, métricas, historial, vacunas, medicación, recetas). Es un
  /// campo aparte de `updateProfile` a propósito, para que la UI de
  /// "compartir" pueda tocarlo sin tener que pasar por el formulario
  /// completo de edición del perfil.
  Future<void> setSharedWithUids(String profileId, List<String> uids) async {
    await _col.doc(profileId).update({'sharedWithUids': uids});
  }

  /// Guarda solo la obra social de un perfil (`''` = sin obra social). Es un
  /// update puntual a propósito, en vez de pasar por `updateProfile`, para
  /// que el selector de Configuración no pise el resto de los campos del
  /// perfil con una copia que puede estar desactualizada.
  Future<void> setInsurance(String profileId, String insurance) async {
    final batch = _db.batch();
    batch.set(
      _fichaRef(profileId),
      {'insurance': insurance, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    // Se toca el documento raíz para que los streams vuelvan a leer la
    // ficha, y se borra el valor viejo si todavía estaba ahí.
    batch.update(_col.doc(profileId), {
      'insurance': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Guarda solo el peso (usado por el historial de peso de mascotas). Mismo
  /// criterio que `setInsurance`: update puntual en la ficha, sin pisar el
  /// resto del perfil, y se toca el documento raíz para que los streams
  /// vuelvan a leer la ficha.
  Future<void> setWeightKg(String profileId, double weightKg) async {
    final batch = _db.batch();
    batch.set(
      _fichaRef(profileId),
      {'weightKg': weightKg, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    batch.update(_col.doc(profileId), {
      'weightKg': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> deleteProfile(String profileId) async {
    // Antes del perfil: la regla de la ficha necesita que exista.
    try {
      await _fichaRef(profileId).delete();
    } catch (e) {
      debugPrint('ProfileService: no se pudo borrar la ficha de $profileId. $e');
    }
    await _col.doc(profileId).delete();
  }
}