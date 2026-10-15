import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Borra los datos de un usuario en Firestore y en el dispositivo.
///
/// Sin Cloud Functions (plan gratuito), el borrado lo hace el propio
/// cliente, y Firestore NO borra subcolecciones en cascada, así que se
/// recorren a mano. El ORDEN importa por las reglas de seguridad:
///   1. invitaciones enviadas (mientras sigo en la familia)
///   2. agenda / vitals / botiquín / diario (las reglas de agenda y vitals
///      consultan el perfil, que todavía tiene que existir)
///   3. subcolecciones de cada perfil, y recién después el perfil
///   4. salir de la familia (o borrarla si soy la única persona)
///   5. documento `users/{uid}`
class AccountDeletionService {
  AccountDeletionService._();
  static final AccountDeletionService instance = AccountDeletionService._();

  final _db = FirebaseFirestore.instance;

  static const _profileSubcollections = ['historial', 'medicacion', 'tomas', 'vacunas', 'recetas', 'datos_clinicos'];

  /// Devuelve un mensaje si NO se puede eliminar la cuenta, o null si sí.
  /// Se llama antes de borrar nada.
  Future<String?> blockingReason(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final familyId = userDoc.data()?['familyId'] as String?;
    if (familyId == null) return null;

    final fam = await _db.collection('families').doc(familyId).get();
    if (!fam.exists) return null;
    final data = fam.data() ?? {};
    final members = List<String>.from(data['memberUids'] as List? ?? const []);
    final isOwner = data['ownerUid'] == uid;
    if (isOwner && members.any((m) => m != uid)) {
      return 'Sos quien administra la familia "${data['name'] ?? ''}" y todavía tiene '
          'otros integrantes. Pedile a cada uno que salga de la familia antes de eliminar tu cuenta.';
    }
    return null;
  }

  Future<void> deleteAllUserData(String uid) async {
    final userRef = _db.collection('users').doc(uid);
    final familyId = (await userRef.get()).data()?['familyId'] as String?;

    await _safe('invitaciones', () => _deleteQuery(_db.collection('familyInvites').where('invitedByUid', isEqualTo: uid)));

    // Pasos independientes entre sí: en paralelo (antes era uno por uno y
    // tardaba mucho con cuentas con varios perfiles).
    await Future.wait(['agenda', 'vitals', 'botiquin', 'diario'].map(
      (c) => _safe(c, () => _deleteQuery(_db.collection(c).where('uid', isEqualTo: uid))),
    ));

    final profiles = await _db.collection('profiles').where('uid', isEqualTo: uid).get();
    await Future.wait(profiles.docs.map((p) async {
      await Future.wait(_profileSubcollections.map(
        (sub) => _safe('profiles/${p.id}/$sub', () => _deleteQuery(p.reference.collection(sub))),
      ));
      // El perfil se borra recién cuando sus subcolecciones ya no están.
      await p.reference.delete();
    }));

    if (familyId != null) {
      await _safe('familia', () async {
        final famRef = _db.collection('families').doc(familyId);
        final fam = await famRef.get();
        if (!fam.exists) return;
        final members = List<String>.from(fam.data()?['memberUids'] as List? ?? const []);
        if (fam.data()?['ownerUid'] == uid && members.every((m) => m == uid)) {
          await famRef.delete();
        } else {
          await famRef.update({'memberUids': FieldValue.arrayRemove([uid])});
        }
      });
    }

    await userRef.delete();
  }

  /// Limpia lo que quedó en este dispositivo.
  Future<void> clearLocalData() async {
    await Future.wait([
      _safe('adjuntos', () async {
        final root = await getApplicationDocumentsDirectory();
        final dir = Directory('${root.path}/ordenes');
        if (await dir.exists()) await dir.delete(recursive: true);
      }),
      _safe('notificaciones', () => FlutterLocalNotificationsPlugin().cancelAll()),
      _safe('preferencias', () async => (await SharedPreferences.getInstance()).clear()),
      // Incluye las credenciales del login rápido y la clave de cifrado local.
      _safe('almacenamiento seguro', () => const FlutterSecureStorage().deleteAll()),
    ]);
  }

  Future<void> _deleteQuery(Query<Map<String, dynamic>> query) async {
    while (true) {
      final snap = await query.limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < 400) return;
    }
  }

  /// Un fallo parcial (ej. permiso denegado en un documento ajeno) no
  /// debe impedir que se borre el resto.
  Future<void> _safe(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('AccountDeletion: no se pudo limpiar $what. $e');
    }
  }
}