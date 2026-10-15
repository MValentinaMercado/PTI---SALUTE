import 'package:cloud_firestore/cloud_firestore.dart';

enum ProfileType { persona, mascota }

ProfileType profileTypeFromString(String value) {
  return ProfileType.values.firstWhere(
        (t) => t.name == value,
    orElse: () => ProfileType.persona,
  );
}

/// Perfil de un integrante del grupo familiar (persona o mascota).
/// Vive en dos lugares de Firestore, según qué tan sensible sea cada dato:
///
/// - `profiles/{profileId}` (documento raíz): solo lo BÁSICO, que ve toda
///   la familia: nombre, apellido, relación, tipo, fecha de nacimiento,
///   avatar, especie/raza y los campos de pertenencia/consentimiento.
/// - `profiles/{profileId}/datos_clinicos/ficha`: lo CLÍNICO (grupo
///   sanguíneo, alergias, contacto de emergencia, obra social, último
///   chequeo, peso). Las reglas de Firestore solo dejan leerlo a quien
///   administra el perfil o a quien recibió permiso (`sharedWithUids`).
///
/// En Dart sigue siendo un solo objeto: [ProfileService] junta las dos
/// partes cuando el usuario tiene permiso, y deja los campos clínicos
/// vacíos cuando no. La historia clínica en sí (diagnósticos,
/// observaciones) vive en `profiles/{profileId}/historial`, cifrada.
class FamilyProfile {
  final String id;
  final String ownerUid;
  final ProfileType type;
  final String name;
  // Apellido. Vacío para perfiles viejos que todavía no lo cargaron, o
  // para dependientes (mascotas) donde no aplica.
  final String lastName;
  // Nombre por el que la app se dirige a esta persona en el resto de las
  // pantallas (saludo, navegación, etc.), a diferencia de `name`+`lastName`
  // que es el nombre completo que se muestra en la ficha de Perfil. Si es
  // null o está vacío, se usa `name` (el nombre de pila) como default.
  final String? username;
  final String relation; // ej: "Padre", "Hija", "Perro"
  final DateTime? birthDate;
  final String bloodType;
  final String allergies;
  final String avatarUrl;
  final String emergencyContact;
  // Obra social / prepaga elegida (texto). Vacío = sin obra social o todavía
  // sin cargar. Solo aplica a personas; en mascotas queda vacío. Es un
  // metadato administrativo (como `bloodType` o `allergies`), no historia
  // clínica, así que no va cifrado.
  final String insurance;
  final DateTime? lastCheckup;
  // Solo mascotas:
  final String? species;
  final String? breed;
  final double? weightKg;
  // Marca el perfil que se crea automáticamente para el dueño de la
  // cuenta (ver AuthService.register / ProfileService.ensureSelfProfile).
  // Sirve para distinguir "mi perfil" del resto de los perfiles que
  // administro (hijos, mascotas, etc.) y para evitar que se borre por
  // accidente desde la UI.
  final bool isSelf;
  // BUG-002: a qué grupo familiar compartido pertenece este perfil.
  // `null` significa "todavía no formo parte de ninguna familia": el
  // perfil solo lo ve su dueño (comportamiento previo a FEAT-001/002).
  // Cuando el dueño crea o se une a una familia, `FamilyService` marca
  // con este `familyId` tanto su perfil propio como sus dependientes,
  // y a partir de ahí `ProfileService.watchProfiles()` filtra por acá
  // en vez de por `uid`, para que todos los miembros de la familia se
  // vean entre sí.
  final String? familyId;
  // BUG-002: distingue un "miembro independiente" (tiene su propia
  // cuenta de Firebase Auth; este campo guarda ese uid) de un
  // "dependiente" (no tiene cuenta propia, ej. un hijo o una mascota;
  // este campo queda null). Para el perfil propio (`isSelf: true`)
  // siempre es igual a `ownerUid`, porque una persona siempre administra
  // su propia cuenta.
  final String? linkedUid;
  // Consentimiento explícito para compartir los datos CLÍNICOS de este
  // perfil (agenda, métricas, historial, vacunas, medicación, recetas)
  // con otros miembros de la familia. Por default está vacío: que dos
  // cuentas compartan familia solo te deja ver que el otro perfil
  // existe (nombre, relación) —eso no es dato sensible—, pero no te da
  // acceso automático a su información de salud. Quien administra el
  // perfil (el dependiente lo administra su tutor; el miembro
  // independiente se administra a sí mismo) es quien decide, uno por
  // uno, con qué uids de la familia comparte eso. Es información de
  // salud: compartirla sin este opt-in explícito puede no ser legal
  // según la jurisdicción (dato sensible bajo leyes de protección de
  // datos personales).
  final List<String> sharedWithUids;

  const FamilyProfile({
    required this.id,
    required this.ownerUid,
    required this.type,
    required this.name,
    this.lastName = '',
    this.username,
    this.relation = '',
    this.birthDate,
    this.bloodType = '',
    this.allergies = '',
    this.avatarUrl = '',
    this.emergencyContact = '',
    this.insurance = '',
    this.lastCheckup,
    this.species,
    this.breed,
    this.weightKg,
    this.isSelf = false,
    this.familyId,
    this.linkedUid,
    this.sharedWithUids = const [],
  });

  /// Campos que viven en `datos_clinicos/ficha` y NO en el documento raíz.
  static const clinicalKeys = [
    'bloodType',
    'allergies',
    'emergencyContact',
    'insurance',
    'lastCheckup',
    'weightKg',
  ];

  /// ¿Hay algún dato clínico cargado? (para no escribir una ficha vacía).
  bool get hasClinicalData =>
      bloodType.isNotEmpty ||
      allergies.isNotEmpty ||
      emergencyContact.isNotEmpty ||
      insurance.isNotEmpty ||
      lastCheckup != null ||
      weightKg != null;

  /// `true` si este perfil no tiene cuenta propia (lo administra por
  /// completo quien lo creó): hijos, mascotas, etc. `false` si es un
  /// miembro independiente (tiene su propio login) o el perfil propio.
  bool get isDependent => linkedUid == null;

  /// Nombre completo (nombre + apellido), para la ficha de Perfil. Si no
  /// hay apellido cargado, queda igual que `name`.
  String get fullName => lastName.trim().isEmpty ? name : '$name $lastName';

  /// Nombre por el que se llama a esta persona en el resto de la app
  /// (saludo, navegación). Si no cargó un nombre de usuario, cae al
  /// nombre de pila.
  String get displayUsername {
    final u = username?.trim();
    return (u != null && u.isNotEmpty) ? u : name;
  }

  factory FamilyProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return FamilyProfile(
      id: doc.id,
      ownerUid: data['uid'] as String? ?? '',
      type: profileTypeFromString(data['type'] as String? ?? 'persona'),
      name: data['name'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      username: data['username'] as String?,
      relation: data['relation'] as String? ?? '',
      birthDate: (data['birthDate'] as Timestamp?)?.toDate(),
      bloodType: data['bloodType'] as String? ?? '',
      allergies: data['allergies'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String? ?? '',
      emergencyContact: data['emergencyContact'] as String? ?? '',
      insurance: data['insurance'] as String? ?? '',
      lastCheckup: (data['lastCheckup'] as Timestamp?)?.toDate(),
      species: data['species'] as String?,
      breed: data['breed'] as String?,
      weightKg: (data['weightKg'] as num?)?.toDouble(),
      isSelf: data['isSelf'] as bool? ?? false,
      familyId: data['familyId'] as String?,
      linkedUid: data['linkedUid'] as String?,
      sharedWithUids: List<String>.from(data['sharedWithUids'] as List? ?? const []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': ownerUid,
      'type': type.name,
      'name': name,
      'lastName': lastName,
      'username': username,
      'relation': relation,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
      'avatarUrl': avatarUrl,
      'species': species,
      'breed': breed,
      'isSelf': isSelf,
      'familyId': familyId,
      'linkedUid': linkedUid,
      'sharedWithUids': sharedWithUids,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Los datos clínicos, listos para escribir en `datos_clinicos/ficha`.
  Map<String, dynamic> clinicalToFirestore() {
    return {
      'bloodType': bloodType,
      'allergies': allergies,
      'emergencyContact': emergencyContact,
      'insurance': insurance,
      'lastCheckup': lastCheckup != null ? Timestamp.fromDate(lastCheckup!) : null,
      'weightKg': weightKg,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Copia con los campos clínicos tomados de [data] (el documento
  /// `datos_clinicos/ficha`). Si [data] es null (todavía no hay ficha), se
  /// conserva lo que vino del documento raíz: así los perfiles viejos,
  /// que aún no se migraron, siguen mostrando sus datos.
  FamilyProfile withClinical(Map<String, dynamic>? data) {
    if (data == null) return this;
    return _rebuild(
      bloodType: data['bloodType'] as String? ?? bloodType,
      allergies: data['allergies'] as String? ?? allergies,
      emergencyContact: data['emergencyContact'] as String? ?? emergencyContact,
      insurance: data['insurance'] as String? ?? insurance,
      lastCheckup: (data['lastCheckup'] as Timestamp?)?.toDate() ?? lastCheckup,
      weightKg: (data['weightKg'] as num?)?.toDouble() ?? weightKg,
    );
  }

  /// Copia SIN datos clínicos: lo que se devuelve para un perfil sobre el
  /// que el usuario no tiene permiso.
  FamilyProfile withoutClinical() => _rebuild(
        bloodType: '',
        allergies: '',
        emergencyContact: '',
        insurance: '',
        lastCheckup: null,
        weightKg: null,
      );

  FamilyProfile _rebuild({
    required String bloodType,
    required String allergies,
    required String emergencyContact,
    required String insurance,
    required DateTime? lastCheckup,
    required double? weightKg,
  }) {
    return FamilyProfile(
      id: id,
      ownerUid: ownerUid,
      type: type,
      name: name,
      lastName: lastName,
      username: username,
      relation: relation,
      birthDate: birthDate,
      bloodType: bloodType,
      allergies: allergies,
      avatarUrl: avatarUrl,
      emergencyContact: emergencyContact,
      insurance: insurance,
      lastCheckup: lastCheckup,
      species: species,
      breed: breed,
      weightKg: weightKg,
      isSelf: isSelf,
      familyId: familyId,
      linkedUid: linkedUid,
      sharedWithUids: sharedWithUids,
    );
  }

  FamilyProfile copyWith({
    String? name,
    String? lastName,
    String? username,
    String? relation,
    DateTime? birthDate,
    String? bloodType,
    String? allergies,
    String? avatarUrl,
    String? emergencyContact,
    String? insurance,
    DateTime? lastCheckup,
    String? species,
    String? breed,
    double? weightKg,
    bool? isSelf,
    String? familyId,
    String? linkedUid,
    List<String>? sharedWithUids,
  }) {
    return FamilyProfile(
      id: id,
      ownerUid: ownerUid,
      type: type,
      name: name ?? this.name,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      relation: relation ?? this.relation,
      birthDate: birthDate ?? this.birthDate,
      bloodType: bloodType ?? this.bloodType,
      allergies: allergies ?? this.allergies,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      insurance: insurance ?? this.insurance,
      lastCheckup: lastCheckup ?? this.lastCheckup,
      species: species ?? this.species,
      breed: breed ?? this.breed,
      weightKg: weightKg ?? this.weightKg,
      isSelf: isSelf ?? this.isSelf,
      familyId: familyId ?? this.familyId,
      linkedUid: linkedUid ?? this.linkedUid,
      sharedWithUids: sharedWithUids ?? this.sharedWithUids,
    );
  }
}