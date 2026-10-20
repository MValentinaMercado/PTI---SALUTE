import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:saluteapp/core/models/sos_contact.dart';

/// Contacto de emergencia del usuario logueado (UNO solo).
///
/// - Fuente de verdad en la nube: campo `sosContact` de `users/{uid}`.
/// - Copia local en almacenamiento seguro (Keychain / Keystore), por usuario,
///   para que el SOS funcione sin conexión aunque la app se haya reiniciado.
/// - Si se edita sin conexión, se guarda primero local y se marca como
///   pendiente; se vuelve a subir en [syncPending] (al abrir la app / volver
///   la conexión). Firestore además reintenta solo su cola de escrituras.
class SosContactService {
  SosContactService._();
  static final SosContactService instance = SosContactService._();

  final _db = FirebaseFirestore.instance;
  final _secure = const FlutterSecureStorage();

  String? get _uidOrNull => FirebaseAuth.instance.currentUser?.uid;

  String get _uid {
    final uid = _uidOrNull;
    if (uid == null) throw StateError('No hay usuario logueado.');
    return uid;
  }

  DocumentReference<Map<String, dynamic>> get _userDoc => _db.collection('users').doc(_uid);

  String _key(String uid) => 'sos_contact_$uid';
  String _pendingKey(String uid) => 'sos_contact_pending_$uid';

  // ---------------------------------------------------------------- local

  /// Lee la copia local (null si nunca se configuró o no hay sesión).
  Future<SosContact?> getLocal() async {
    final uid = _uidOrNull;
    if (uid == null) return null;
    try {
      final raw = await _secure.read(key: _key(uid));
      if (raw == null || raw.isEmpty) return null;
      final c = SosContact.fromMap(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      return c.phoneNumber.trim().isEmpty ? null : c;
    } catch (e) {
      debugPrint('SosContactService.getLocal: $e');
      return null;
    }
  }

  Future<void> _writeLocal(String uid, SosContact? c) async {
    try {
      if (c == null) {
        await _secure.delete(key: _key(uid));
      } else {
        await _secure.write(key: _key(uid), value: jsonEncode(c.toMap()));
      }
    } catch (e) {
      debugPrint('SosContactService._writeLocal: $e');
    }
  }

  Future<bool> _isPending(String uid) async =>
      (await _secure.read(key: _pendingKey(uid))) == '1';

  Future<void> _setPending(String uid, bool v) async {
    try {
      if (v) {
        await _secure.write(key: _pendingKey(uid), value: '1');
      } else {
        await _secure.delete(key: _pendingKey(uid));
      }
    } catch (_) {}
  }

  /// Borra la copia local (usar al eliminar la cuenta).
  Future<void> clearLocalFor(String uid) async {
    await _writeLocal(uid, null);
    await _setPending(uid, false);
  }

  // ---------------------------------------------------------------- lectura

  /// Contacto para usar AHORA: primero local (instantáneo y sin red), y si
  /// no hay, intenta la nube con un tope corto para no demorar una emergencia.
  Future<SosContact?> getSosContact() async {
    final local = await getLocal();
    if (local != null) return local;
    final uid = _uidOrNull;
    if (uid == null) return null;
    try {
      final doc = await _userDoc.get().timeout(const Duration(seconds: 3));
      final raw = doc.data()?['sosContact'] as Map<String, dynamic>?;
      if (raw == null) return null;
      final c = SosContact.fromMap(raw);
      await _writeLocal(uid, c);
      return c;
    } catch (_) {
      return null;
    }
  }

  /// Stream: emite primero la copia local y después los cambios de la nube.
  /// Un snapshot que viene del caché y no trae contacto NO borra la copia
  /// local (puede ser simplemente que todavía no sincronizó).
  Stream<SosContact?> watchSosContact() async* {
    final uid = _uidOrNull;
    if (uid == null) {
      yield null;
      return;
    }
    yield await getLocal();
    await for (final snap in _userDoc.snapshots(includeMetadataChanges: true)) {
      final raw = snap.data()?['sosContact'] as Map<String, dynamic>?;
      if (raw != null) {
        final c = SosContact.fromMap(raw);
        if (!(await _isPending(uid))) await _writeLocal(uid, c);
        yield c;
      } else if (!snap.metadata.isFromCache && !(await _isPending(uid))) {
        await _writeLocal(uid, null);
        yield null;
      } else {
        yield await getLocal();
      }
    }
  }

  // --------------------------------------------------------------- escritura

  /// Guarda local de inmediato (no espera a la red) y sube en segundo plano.
  Future<void> saveSosContact(SosContact contacto) async {
    final uid = _uid;
    await _writeLocal(uid, contacto);
    await _setPending(uid, true);
    unawaited(_push(uid, contacto));
  }

  Future<void> clearSosContact() async {
    final uid = _uid;
    await _writeLocal(uid, null);
    await _setPending(uid, true);
    unawaited(_push(uid, null));
  }

  Future<void> _push(String uid, SosContact? c) async {
    try {
      final ref = _db.collection('users').doc(uid);
      if (c == null) {
        await ref.update({'sosContact': FieldValue.delete()});
      } else {
        await ref.set({'sosContact': c.toMap()}, SetOptions(merge: true));
      }
      await _setPending(uid, false);
    } catch (e) {
      // Sigue pendiente: se reintenta en syncPending().
      debugPrint('SosContactService._push (queda pendiente): $e');
    }
  }

  /// Reintenta subir cambios hechos sin conexión. Llamar al abrir la app y
  /// cuando vuelve a primer plano.
  Future<void> syncPending() async {
    final uid = _uidOrNull;
    if (uid == null) return;
    try {
      if (!await _isPending(uid)) return;
      await _push(uid, await getLocal());
    } catch (e) {
      debugPrint('SosContactService.syncPending: $e');
    }
  }
}
