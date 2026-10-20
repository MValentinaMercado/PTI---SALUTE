import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/profile/profileCard.dart';

const _monthNames = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
];

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')} ${_monthNames[date.month - 1]}, ${date.year}';
}

int _ageInYears(DateTime birthDate) {
  final now = DateTime.now();
  var years = now.year - birthDate.year;
  final birthdayAlreadyHappened = (now.month > birthDate.month) ||
      (now.month == birthDate.month && now.day >= birthDate.day);
  if (!birthdayAlreadyHappened) years -= 1;
  return years;
}

/// Convierte el modelo de Firestore [FamilyProfile] al value object
/// [FamilyProfileData] que ya consume toda la UI de profileCard.dart.
///
/// `alerts`, `medications` y las métricas de bienestar todavía no salen
/// de Firestore (esas viven en las subcolecciones `agenda`, `medicacion`
/// y `metricas`, que no están conectadas todavía) — por ahora se muestran
/// vacías/placeholder. Cuando esas colecciones se conecten, esta es la
/// única función que hay que tocar.
extension FamilyProfileDisplay on FamilyProfile {
  FamilyProfileData toDisplayData() {
    return FamilyProfileData(
      name: fullName,
      relation: relation.isNotEmpty
          ? relation
          : (type == ProfileType.mascota ? 'Mascota' : 'Familiar'),
      age: birthDate != null ? '${_ageInYears(birthDate!)} años' : '—',
      avatarUrl: avatarUrl,
      bloodType: bloodType.isNotEmpty ? bloodType : '—',
      allergies: allergies.isNotEmpty ? allergies : 'Ninguna registrada',
      lastCheckup: lastCheckup != null ? _formatDate(lastCheckup!) : 'Sin registrar',
      emergencyContact: emergencyContact.isNotEmpty ? emergencyContact : 'Sin configurar',
      // null = no aplica (mascotas): la ficha no muestra el casillero.
      insurance: type == ProfileType.persona
          ? (insurance.isNotEmpty ? insurance : 'Sin registrar')
          : null,
      // Una mascota no tiene sueño, pasos ni estrés: su tarjeta es la del
      // peso (el valor real lo completa LiveProfileScreen con el historial).
      wellbeingLabel: type == ProfileType.mascota ? 'PESO' : 'MÉTRICAS',
      wellbeingTitle: type == ProfileType.mascota ? 'Peso actual' : 'Bienestar Actual',
      wellbeingValue: 'Sin datos aún',
      isPet: type == ProfileType.mascota,
      // Cabecera: en una mascota, especie y raza (si están cargadas).
      badges: type == ProfileType.mascota
          ? [
              if ((species ?? '').trim().isNotEmpty) species!.trim(),
              if ((breed ?? '').trim().isNotEmpty) breed!.trim(),
            ]
          : const [],
      alerts: const [],
      medications: const [],
    );
  }
}