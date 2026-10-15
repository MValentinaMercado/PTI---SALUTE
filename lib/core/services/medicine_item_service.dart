import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:saluteapp/core/models/medicine_item.dart';

/// CRUD de `botiquin` (inventario de medicamentos del hogar).
/// Es una colección top-level filtrada por `uid` — igual que `agenda` —
/// porque el botiquín es de toda la familia, no de un perfil puntual.
///
/// Nota de diseño: igual que AgendaService/ProfileService, ordenamos en
/// memoria en vez de encadenar `orderBy` a la query con `where('uid', ...)`
/// para no depender de un índice compuesto que no existe en el proyecto.
class MedicineItemService {
  MedicineItemService._();
  static final MedicineItemService instance = MedicineItemService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('botiquin');

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('No hay usuario logueado.');
    }
    return uid;
  }

  Stream<List<MedicineItem>> watchAll() {
    return _col.where('uid', isEqualTo: _uid).snapshots().map((snap) {
      final items = snap.docs.map(MedicineItem.fromFirestore).toList();
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return items;
    });
  }

  Future<String> addItem(MedicineItem item) async {
    final data = item.toFirestore();
    data['uid'] = _uid;
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _col.add(data);
    return ref.id;
  }

  Future<void> updateItem(MedicineItem item) async {
    await _col.doc(item.id).update(item.toFirestore());
  }

  Future<void> updateStock(String itemId, int newStock) async {
    await _col.doc(itemId).update({
      'currentStock': newStock,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Suma/resta [delta] unidades al stock actual de forma atómica (dos
  /// dispositivos marcando tomas a la vez no se pisan) y sin salirse de
  /// 0..totalStock. Devuelve el stock resultante, o null si el ítem ya
  /// no existe. Lo usa el checklist de medicación al marcar una toma.
  ///
  /// Ojo: usa una transacción, así que requiere conexión. Si falla, quien
  /// llama decide qué hacer (el checklist lo ignora: marcar la toma no
  /// debe depender del botiquín).
  Future<int?> adjustStock(String itemId, int delta) {
    final ref = _col.doc(itemId);
    return _db.runTransaction<int?>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return null;
      final data = snap.data() ?? {};
      final current = (data['currentStock'] as num?)?.toInt() ?? 0;
      final total = (data['totalStock'] as num?)?.toInt() ?? 0;
      var next = current + delta;
      if (next < 0) next = 0;
      if (total > 0 && next > total) next = total;
      tx.update(ref, {
        'currentStock': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return next;
    });
  }

  Future<void> deleteItem(String itemId) async {
    await _col.doc(itemId).delete();
  }
}
