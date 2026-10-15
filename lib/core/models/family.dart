import 'package:cloud_firestore/cloud_firestore.dart';

/// Grupo familiar compartido entre varias cuentas (FEAT-001/002).
/// Vive en `families/{familyId}`. El `code` es lo que se comparte para
/// que otra cuenta se una (`FamilyService.joinFamily`).
class Family {
  final String id;
  final String name;
  final String code;
  final String ownerUid;
  final List<String> memberUids;

  const Family({
    required this.id,
    required this.name,
    required this.code,
    required this.ownerUid,
    required this.memberUids,
  });

  factory Family.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Family(
      id: doc.id,
      name: data['name'] as String? ?? '',
      code: data['code'] as String? ?? '',
      ownerUid: data['ownerUid'] as String? ?? '',
      memberUids: List<String>.from(data['memberUids'] as List? ?? const []),
    );
  }
}

/// Invitación por email pendiente (FEAT-003), vive en `familyInvites`.
/// No es un mecanismo de unión alternativo al código: es solo un
/// registro de a quién ya se le mandó el código por mail, para poder
/// mostrar "invitados pendientes" en la pantalla de familia.
class FamilyInvite {
  final String id;
  final String email;
  final String status;

  const FamilyInvite({required this.id, required this.email, required this.status});

  factory FamilyInvite.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return FamilyInvite(
      id: doc.id,
      email: data['email'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
    );
  }
}
