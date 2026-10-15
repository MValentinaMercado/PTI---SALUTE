import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:saluteapp/core/models/family.dart';

/// Excepción propia para mostrar mensajes en español en la UI.
class FamilyFailure implements Exception {
  final String message;
  FamilyFailure(this.message);
}

/// FEAT-001/002: crear un grupo familiar y unirse a uno existente por
/// código. BUG-002: es quien sella `familyId` (visibilidad compartida)
/// en los perfiles del usuario, lo que permite distinguir después
/// "miembro independiente" (tiene su propia cuenta y su propio
/// `linkedUid`) de "dependiente" (sin cuenta propia).
class FamilyService {
  FamilyService._();
  static final FamilyService instance = FamilyService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _families => _db.collection('families');
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _profiles => _db.collection('profiles');
  CollectionReference<Map<String, dynamic>> get _invites => _db.collection('familyInvites');
  // Colección que consume la extensión oficial de Firebase "Trigger
  // Email" (firebase/firestore-send-email): basta con escribir acá para
  // que la extensión mande el mail. Si el proyecto no tiene la
  // extensión instalada, el documento queda sin efecto (no rompe nada,
  // pero tampoco sale el mail).
  CollectionReference<Map<String, dynamic>> get _mail => _db.collection('mail');

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('No hay usuario logueado.');
    }
    return uid;
  }

  /// Stream de la familia del usuario actual, o `null` si todavía no
  /// pertenece a ninguna.
  Stream<Family?> watchMyFamily() {
    return _users.doc(_uid).snapshots().asyncExpand((userDoc) {
      final familyId = userDoc.data()?['familyId'] as String?;
      if (familyId == null) return Stream.value(null);
      return _families.doc(familyId).snapshots().map(
            (d) => d.exists ? Family.fromFirestore(d) : null,
          );
    });
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sin 0/O/1/I, se confunden al dictarlos
    final rand = Random.secure();
    final suffix = List.generate(5, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'SALUTE-$suffix';
  }

  /// Crea una familia nueva con un código único y deja al usuario actual
  /// como su primer miembro. Marca `familyId` en su perfil propio y en
  /// todos los dependientes que ya tenía cargados.
  Future<Family> createFamily(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw FamilyFailure('Ponele un nombre a tu familia.');
    }

    // Reintenta si por casualidad el código generado ya existe (muy
    // improbable con 5 caracteres de un alfabeto de 32, pero es gratis
    // chequear).
    String code = _generateCode();
    for (var attempt = 0; attempt < 5; attempt++) {
      final clash = await _families.where('code', isEqualTo: code).limit(1).get();
      if (clash.docs.isEmpty) break;
      code = _generateCode();
    }

    final ref = await _families.add({
      'name': trimmed,
      'code': code,
      'ownerUid': _uid,
      'memberUids': [_uid],
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _linkCurrentUserToFamily(ref.id);

    return Family(id: ref.id, name: trimmed, code: code, ownerUid: _uid, memberUids: [_uid]);
  }

  /// Se une a una familia existente a partir de su código.
  Future<Family> joinFamily(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw FamilyFailure('Ingresá un código de familia.');
    }

    final match = await _families.where('code', isEqualTo: normalized).limit(1).get();
    if (match.docs.isEmpty) {
      throw FamilyFailure('No encontramos ninguna familia con ese código.');
    }
    final familyDoc = match.docs.first;
    final familyId = familyDoc.id;

    await familyDoc.reference.update({
      'memberUids': FieldValue.arrayUnion([_uid]),
    });
    await _linkCurrentUserToFamily(familyId);

    final refreshed = await familyDoc.reference.get();
    return Family.fromFirestore(refreshed);
  }

  /// Sella `familyId` en el documento de usuario y en todos los
  /// perfiles que administra (su perfil propio + sus dependientes), y
  /// marca su perfil propio con `linkedUid` (por si viniera de una
  /// cuenta vieja creada antes de que existiera ese campo).
  Future<void> _linkCurrentUserToFamily(String familyId) async {
    await _users.doc(_uid).set({'familyId': familyId}, SetOptions(merge: true));

    final mine = await _profiles.where('uid', isEqualTo: _uid).get();
    if (mine.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in mine.docs) {
      final isSelf = doc.data()['isSelf'] as bool? ?? false;
      batch.update(doc.reference, {
        'familyId': familyId,
        if (isSelf) 'linkedUid': _uid,
      });
    }
    await batch.commit();
  }

  /// FEAT-003: invita por email a alguien a la familia. No es una vía
  /// de unión alternativa al código —el que recibe el mail igual tiene
  /// que usar `joinFamily` con el código que viene adentro—; esto solo
  /// automatiza mandárselo y deja un registro de "invitados pendientes".
  Future<void> inviteByEmail(Family family, String email) async {
    final normalized = email.trim().toLowerCase();
    if (!_emailRegex.hasMatch(normalized)) {
      throw FamilyFailure('Ingresá un email válido.');
    }

    final inviterName = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final displayInviter = (inviterName == null || inviterName.isEmpty) ? 'Alguien de tu familia' : inviterName;

    await _invites.add({
      'familyId': family.id,
      'familyName': family.name,
      'email': normalized,
      'invitedByUid': _uid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Ver el comentario de `_mail` más arriba: esto solo manda el email
    // de verdad si el proyecto tiene instalada la extensión "Trigger
    // Email" de Firebase.
    await _mail.add({
      'to': [normalized],
      'message': {
        'subject': '$displayInviter te invitó a "${family.name}" en Salute',
        'text': 'Te invitaron a unirte a la familia "${family.name}" en Salute.\n\n'
            'Para unirte, abrí la app, andá a "Mi familia" y usá este código:\n\n'
            '${family.code}\n\n'
            'Si no esperabas esta invitación, podés ignorar este mensaje.',
      },
    });
  }

  /// Invitaciones por email pendientes de una familia, para mostrarlas
  /// en la pantalla de familia ("Invitados: fulano@mail.com...").
  Stream<List<FamilyInvite>> watchPendingInvites(String familyId) {
    return _invites
        .where('familyId', isEqualTo: familyId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map(FamilyInvite.fromFirestore).toList());
  }
}
