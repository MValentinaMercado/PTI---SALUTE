import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/medical_record.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/models/sos_contact.dart';

/// Bloques opcionales de la ficha médica. "Datos personales" no está acá
/// porque siempre va (una ficha sin nombre no sirve).
enum MedicalSheetSection {
  insurance('Obra social'),
  allergies('Alergias'),
  medication('Medicación actual'),
  emergency('Contacto de emergencia'),
  history('Historial médico reciente');

  final String label;
  const MedicalSheetSection(this.label);
}

/// Una línea de la ficha. Con [label] se muestra como "Etiqueta: valor";
/// sin [label] es un ítem de lista, con [detail] opcional debajo.
class SheetLine {
  final String? label;
  final String value;
  final String? detail;
  const SheetLine({this.label, required this.value, this.detail});
}

class MedicalSheetBlock {
  final String title;
  final List<SheetLine> lines;
  const MedicalSheetBlock({required this.title, required this.lines});
}

/// Categorías del historial que entran en la ficha. `animo`, `psicologia` y
/// `triaje` quedan afuera A PROPÓSITO: son salud mental y síntomas
/// autoinformados, y no corresponde que salgan en una ficha que se manda a
/// terceros sin que el usuario los haya elegido uno por uno.
const Set<RecordCategory> kSheetHistoryCategories = {
  RecordCategory.consulta,
  RecordCategory.estudio,
  RecordCategory.vacuna,
  RecordCategory.odontologia,
  RecordCategory.cardiologia,
  RecordCategory.laboratorio,
  RecordCategory.otro,
};

const Map<RecordCategory, String> _categoryLabels = {
  RecordCategory.consulta: 'Consulta',
  RecordCategory.estudio: 'Estudio',
  RecordCategory.vacuna: 'Vacuna',
  RecordCategory.odontologia: 'Odontología',
  RecordCategory.cardiologia: 'Cardiología',
  RecordCategory.laboratorio: 'Laboratorio',
  RecordCategory.otro: 'Otro',
};

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtDateTime(DateTime d) =>
    '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

int _ageInYears(DateTime birthDate) {
  final now = DateTime.now();
  var years = now.year - birthDate.year;
  final hadBirthday = now.month > birthDate.month ||
      (now.month == birthDate.month && now.day >= birthDate.day);
  if (!hadBirthday) years -= 1;
  return years;
}

/// Todo lo que hace falta para armar la ficha de un perfil. Las tres
/// salidas (vista previa, texto y PDF) salen de [blocks], así nunca
/// pueden diferir entre sí.
class MedicalSheetData {
  final FamilyProfile profile;
  final List<Medication> medications;
  final List<MedicalRecord> history;

  /// Contacto SOS de la cuenta. Solo tiene sentido para el perfil propio y
  /// los dependientes de esta cuenta; ver [emergencyApplicable].
  final SosContact? sosContact;
  final bool emergencyApplicable;

  /// Secciones que no se pudieron cargar (ej. sin permiso) y por qué. No se
  /// pueden incluir en la ficha.
  final Map<MedicalSheetSection, String> unavailable;
  final DateTime generatedAt;

  const MedicalSheetData({
    required this.profile,
    required this.medications,
    required this.history,
    required this.sosContact,
    required this.emergencyApplicable,
    required this.unavailable,
    required this.generatedAt,
  });

  bool get isPet => profile.type == ProfileType.mascota;

  /// Títulos según el tipo de perfil: una mascota tiene ficha veterinaria.
  String get sheetTitle => isPet ? 'Ficha veterinaria' : 'Ficha médica';
  String get identityLabel => isPet ? 'Datos del animal' : 'Datos personales';

  /// Secciones que existen para este tipo de perfil (la obra social no
  /// aplica a mascotas; el contacto de emergencia solo al perfil propio y a
  /// los dependientes de esta cuenta).
  Set<MedicalSheetSection> get applicableSections => {
    if (profile.type == ProfileType.persona) MedicalSheetSection.insurance,
    MedicalSheetSection.allergies,
    MedicalSheetSection.medication,
    // El contacto SOS es de una persona: en una ficha veterinaria no va.
    if (emergencyApplicable && !isPet) MedicalSheetSection.emergency,
    MedicalSheetSection.history,
  };

  /// Qué viene tildado al abrir. El historial arranca destildado: es lo más
  /// sensible y conviene que el usuario lo incluya a propósito.
  Set<MedicalSheetSection> get defaultSelection => applicableSections
      .where((s) => s != MedicalSheetSection.history && !unavailable.containsKey(s))
      .toSet();

  bool _on(Set<MedicalSheetSection> included, MedicalSheetSection s) =>
      included.contains(s) && applicableSections.contains(s) && !unavailable.containsKey(s);

  List<MedicalSheetBlock> blocks(Set<MedicalSheetSection> included) {
    final result = <MedicalSheetBlock>[_identityBlock()];

    if (_on(included, MedicalSheetSection.insurance)) {
      result.add(MedicalSheetBlock(
        title: 'Obra social',
        lines: [
          SheetLine(value: profile.insurance.isNotEmpty ? profile.insurance : 'Sin datos cargados'),
        ],
      ));
    }

    if (_on(included, MedicalSheetSection.allergies)) {
      // "Sin datos cargados" y no "Ninguna": que no haya nada cargado no
      // significa que la persona no tenga alergias, y en una ficha que lee
      // un profesional esa diferencia importa.
      result.add(MedicalSheetBlock(
        title: 'Alergias',
        lines: [
          SheetLine(value: profile.allergies.isNotEmpty ? profile.allergies : 'Sin datos cargados'),
        ],
      ));
    }

    if (_on(included, MedicalSheetSection.medication)) {
      result.add(MedicalSheetBlock(
        title: 'Medicación actual',
        lines: medications.isEmpty
            ? const [SheetLine(value: 'Sin datos cargados')]
            : medications.map(_medicationLine).toList(),
      ));
    }

    if (_on(included, MedicalSheetSection.emergency)) {
      final lines = <SheetLine>[];
      final sos = sosContact;
      if (sos != null) {
        lines.add(SheetLine(
          label: sos.displayName,
          value: sos.phoneNumber.isNotEmpty ? sos.phoneNumber : 'Sin teléfono',
        ));
      }
      final legacy = profile.emergencyContact.trim();
      if (legacy.isNotEmpty && legacy != sos?.displayName) {
        lines.add(SheetLine(value: legacy));
      }
      result.add(MedicalSheetBlock(
        title: 'Contacto de emergencia',
        lines: lines.isEmpty ? const [SheetLine(value: 'Sin datos cargados')] : lines,
      ));
    }

    if (_on(included, MedicalSheetSection.history)) {
      result.add(MedicalSheetBlock(
        title: 'Historial médico reciente',
        lines: history.isEmpty
            ? const [SheetLine(value: 'Sin datos cargados')]
            : history.map(_historyLine).toList(),
      ));
    }

    return result;
  }

  MedicalSheetBlock _identityBlock() {
    final lines = <SheetLine>[SheetLine(label: 'Nombre', value: profile.fullName)];
    final birth = profile.birthDate;
    lines.add(SheetLine(
      label: 'Edad',
      value: birth != null ? '${_ageInYears(birth)} años (nac. ${_fmtDate(birth)})' : 'Sin datos cargados',
    ));
    if (profile.type == ProfileType.persona) {
      lines.add(SheetLine(
        label: 'Grupo sanguíneo',
        value: profile.bloodType.isNotEmpty ? profile.bloodType : 'Sin datos cargados',
      ));
    } else {
      lines.add(const SheetLine(label: 'Tipo', value: 'Mascota'));
      if ((profile.species ?? '').isNotEmpty) {
        lines.add(SheetLine(label: 'Especie', value: profile.species!));
      }
      if ((profile.breed ?? '').isNotEmpty) {
        lines.add(SheetLine(label: 'Raza', value: profile.breed!));
      }
      if (profile.weightKg != null) {
        lines.add(SheetLine(label: 'Peso', value: '${profile.weightKg} kg'));
      }
    }
    return MedicalSheetBlock(title: identityLabel, lines: lines);
  }

  SheetLine _medicationLine(Medication m) {
    final dose = m.dose.isNotEmpty ? ' ${m.dose}' : '';
    final times = m.timesOfDay.isNotEmpty ? ' · ${m.timesOfDay.join(' / ')}' : '';
    final end = m.endDate;
    final until = end != null ? ' · hasta ${_fmtDate(end)}' : ' · tratamiento continuo';
    return SheetLine(
      value: '${m.name}$dose$times$until',
      detail: m.notes.trim().isNotEmpty ? 'Indicaciones: ${m.notes.trim()}' : null,
    );
  }

  SheetLine _historyLine(MedicalRecord r) {
    final who = [r.professional, r.institution].where((s) => s.trim().isNotEmpty).join(' · ');
    return SheetLine(
      value: '${_fmtDate(r.date)} · ${_categoryLabels[r.category] ?? 'Otro'}'
          '${r.title.isNotEmpty ? ' · ${r.title}' : ''}',
      detail: who.isNotEmpty ? who : null,
    );
  }

  static const String disclaimer =
      'Datos cargados por el usuario en la app Salute. Es un resumen informativo: no reemplaza la historia clínica oficial.';

  String get generatedLabel => 'Generada el ${_fmtDateTime(generatedAt)}';

  /// Versión en texto plano (portapapeles y "compartir como texto").
  String toPlainText(Set<MedicalSheetSection> included) {
    final b = StringBuffer('${sheetTitle.toUpperCase()}\n$generatedLabel\n');
    for (final block in blocks(included)) {
      b.writeln();
      b.writeln(block.title.toUpperCase());
      for (final line in block.lines) {
        if (line.label != null) {
          b.writeln('${line.label}: ${line.value}');
        } else {
          b.writeln('- ${line.value}');
          if (line.detail != null) b.writeln('  ${line.detail}');
        }
      }
    }
    b.writeln();
    b.writeln(disclaimer);
    return b.toString().trimRight();
  }
}