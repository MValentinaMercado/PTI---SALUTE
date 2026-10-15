/// Contacto de emergencia (S.O.S.) configurado por el usuario para
/// acceso rápido de llamada desde el Protocolo de Emergencia.
///
/// No es su propia colección de Firestore: vive como un campo
/// (`sosContact`) dentro de `users/{uid}`, porque es un solo dato de
/// cuenta (no un historial ni algo que se comparta con la familia).
class SosContact {
  final String displayName;
  final String phoneNumber;

  const SosContact({required this.displayName, required this.phoneNumber});

  factory SosContact.fromMap(Map<String, dynamic> map) => SosContact(
    displayName: map['displayName'] as String? ?? 'Sin nombre',
    phoneNumber: map['phoneNumber'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    'phoneNumber': phoneNumber,
  };
}