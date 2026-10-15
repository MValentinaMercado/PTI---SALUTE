import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/services/profile_service.dart';

/// Fuente única de verdad de "sobre qué perfil estoy operando ahora"
/// (BUG-006). Vive como singleton, igual que `ProfileService.instance`
/// o `AgendaService.instance`, así cualquier pantalla puede leerlo sin
/// tener que pasarlo por constructor en cada nivel del árbol de widgets.
///
/// Las pantallas que necesiten reconstruirse cuando cambia el perfil
/// activo deben envolver su build en un `ListenableBuilder` (o
/// `AnimatedBuilder`) escuchando `ActiveProfileController.instance`.
///
/// Este controller NO decide por sí solo cuándo cambiar de perfil: eso
/// lo dispara `ensureValid` (llamado cada vez que llega una nueva lista
/// de perfiles desde Firestore, ver `SaluteShell`) o el selector visual
/// que el usuario toca a mano (Parte 2 de BUG-006, todavía pendiente).
class ActiveProfileController extends ChangeNotifier {
  ActiveProfileController._();
  static final ActiveProfileController instance = ActiveProfileController._();

  FamilyProfile? _active;

  /// El perfil sobre el que deberían operar Agenda, Triaje, Ánimo,
  /// Métricas, etc. `null` significa "todavía no sabemos" (recién
  /// logueado, esperando el primer snapshot de `watchProfiles()`) o
  /// "no hay ningún perfil" (no debería pasar nunca en la práctica,
  /// porque `ensureSelfProfile` siempre crea el perfil propio).
  FamilyProfile? get active => _active;

  String? get activeProfileId => _active?.id;

  /// Cambia el perfil activo a mano (lo va a usar el selector visual
  /// de la Parte 2). No hace nada si ya era el activo, para no disparar
  /// rebuilds de más.
  void setActive(FamilyProfile profile) {
    if (_active?.id == profile.id) return;
    _active = profile;
    notifyListeners();
  }

  /// Se llama cada vez que cambia la lista de perfiles del usuario
  /// (alta, baja, o el primer snapshot después de loguearse).
  ///
  /// Reglas:
  /// - Si no hay perfiles todavía, no hay perfil activo.
  /// - Si el perfil activo actual sigue existiendo en la lista, no se
  ///   toca (evita, por ejemplo, sacarte de "Tomás" solo porque
  ///   Firestore mandó un snapshot nuevo).
  /// - Si no hay perfil activo o el que había ya no existe (se borró,
  ///   o es la primera vez que entramos), se elige el perfil propio
  ///   (`isSelf: true`). Si por algún motivo no hay perfil propio
  ///   (no debería pasar), se elige el primero de la lista en vez de
  ///   dejar a la app sin ningún perfil activo.
  void ensureValid(List<FamilyProfile> profiles) {
    if (profiles.isEmpty) {
      if (_active != null) {
        _active = null;
        notifyListeners();
      }
      return;
    }

    final current = _active;
    FamilyProfile? fresh;
    if (current != null) {
      for (final p in profiles) {
        if (p.id == current.id) {
          fresh = p;
          break;
        }
      }
    }
    if (fresh != null) {
      // El perfil activo sigue existiendo: no se cambia de perfil, pero se
      // actualiza la copia que guardamos si cambió algo que se ve en pantalla
      // (foto, nombre, especie...). Si no, el Diario y el selector seguirían
      // mostrando la foto/nombre viejos hasta reiniciar la app. Solo se
      // notifica ante cambios reales, para no reconstruir por cada snapshot.
      if (_displayChanged(current!, fresh)) {
        _active = fresh;
        notifyListeners();
      }
      return;
    }

    // El perfil propio es el `isSelf` de ESTE usuario, no el primero que
    // tenga `isSelf` (cada integrante de la familia tiene el suyo). Si no
    // aparece, antes que cualquier otro se prefiere uno que administre.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final mine = profiles.where((p) => p.ownerUid == uid);
    final next = ProfileService.selfOf(profiles, uid) ??
        (mine.isNotEmpty ? mine.first : profiles.first);
    _active = next;
    notifyListeners();
  }

  static bool _displayChanged(FamilyProfile a, FamilyProfile b) =>
      a.avatarUrl != b.avatarUrl ||
      a.name != b.name ||
      a.lastName != b.lastName ||
      a.relation != b.relation ||
      a.species != b.species ||
      a.breed != b.breed ||
      a.birthDate != b.birthDate ||
      a.weightKg != b.weightKg;

  /// Se llama al cerrar sesión, para que la próxima cuenta que se
  /// loguee en este mismo proceso no arranque viendo el perfil de la
  /// cuenta anterior.
  void clear() {
    if (_active == null) return;
    _active = null;
    notifyListeners();
  }
}
