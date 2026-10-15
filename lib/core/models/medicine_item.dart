import 'package:cloud_firestore/cloud_firestore.dart';

enum MedicineStatus { normal, critical, expired }

/// Un ítem del botiquín familiar, colgando de la colección top-level
/// `botiquin` (filtrada por `uid`, ver MedicineItemService).
///
/// A diferencia de [Medication] (que es el tratamiento activo de UN
/// perfil puntual, con horarios y notas clínicas cifradas), esto es
/// inventario físico compartido por toda la familia: cuántas unidades
/// quedan de una caja y cuándo vence. No es dato clínico sensible, así
/// que no pasa por CryptoService — mismo criterio que AgendaService.
class MedicineItem {
  final String id;
  final String name;
  final String dosage;
  final String schedule;
  final DateTime expirationDate;
  final int currentStock;
  final int totalStock;

  const MedicineItem({
    required this.id,
    required this.name,
    required this.dosage,
    required this.schedule,
    required this.expirationDate,
    required this.currentStock,
    required this.totalStock,
  });

  MedicineStatus get status {
    if (expirationDate.isBefore(DateTime.now())) return MedicineStatus.expired;
    if (totalStock == 0) return MedicineStatus.normal;
    final percentage = (currentStock / totalStock) * 100;
    return percentage < 20 ? MedicineStatus.critical : MedicineStatus.normal;
  }

  double get stockPercentage => totalStock == 0 ? 0 : currentStock / totalStock;
  bool get isCritical => status == MedicineStatus.critical;
  bool get isExpired => status == MedicineStatus.expired;

  factory MedicineItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return MedicineItem(
      id: doc.id,
      name: data['name'] as String? ?? '',
      dosage: data['dosage'] as String? ?? '',
      schedule: data['schedule'] as String? ?? '',
      expirationDate: (data['expirationDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      currentStock: (data['currentStock'] as num?)?.toInt() ?? 0,
      totalStock: (data['totalStock'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'dosage': dosage,
      'schedule': schedule,
      'expirationDate': Timestamp.fromDate(expirationDate),
      'currentStock': currentStock,
      'totalStock': totalStock,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  MedicineItem copyWith({
    String? name,
    String? dosage,
    String? schedule,
    DateTime? expirationDate,
    int? currentStock,
    int? totalStock,
  }) {
    return MedicineItem(
      id: id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      schedule: schedule ?? this.schedule,
      expirationDate: expirationDate ?? this.expirationDate,
      currentStock: currentStock ?? this.currentStock,
      totalStock: totalStock ?? this.totalStock,
    );
  }
}
