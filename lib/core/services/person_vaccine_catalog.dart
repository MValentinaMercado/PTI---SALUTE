import 'package:saluteapp/core/models/vaccine_record.dart';
import 'package:saluteapp/core/services/vaccine_catalog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Carné de vacunación de PERSONAS.
//
// Plantilla basada en el Calendario Nacional de Vacunación de Argentina
// (vigente 2026). Es una guía ORIENTATIVA: el esquema real depende de los
// antecedentes, el embarazo, los factores de riesgo y la zona de residencia,
// y lo indica el médico / el vacunatorio. Igual que en las mascotas, el
// catálogo NUNCA inventa dosis: lo que no está cargado figura "Sin registro".
//
// Edades en MESES (0 = al nacer, 12 = 1 año, 60 = 5 años, 132 = 11 años).
// ─────────────────────────────────────────────────────────────────────────────

bool _adultClaim(int ageMonths) => ageMonths >= 216; // 18 años

/// Antigripal: se reclama en bebés de 6 a 24 meses y desde los 65 años. En el
/// resto de las edades es para grupos de riesgo / embarazo / personal de salud.
bool _fluClaim(int ageMonths) => (ageMonths >= 6 && ageMonths <= 24) || ageMonths >= 780;

/// Triple viral: desde 2026, los nacidos a partir del 1/7/2024 reciben la 2ª
/// dosis a los 15-18 meses; los anteriores, al ingreso escolar (5 años).
List<int> _tripleViralDoses(DateTime? birth, DateTime today) {
  if (birth != null && !birth.isBefore(DateTime(2024, 7, 1))) return const [12, 15];
  return const [12, 60];
}

/// Neumococo: 2, 4 y 12 meses en la infancia; una dosis desde los 65 años.
List<int> _neumococoDoses(DateTime? birth, DateTime today) {
  if (birth == null) return const [];
  final age = PersonVaccines.monthsBetween(birth, today);
  if (age < 60) return const [2, 4, 12];
  if (age >= 780) return const [780];
  return const [];
}

const _bcg = VaccineTemplate(
  key: 'bcg',
  name: 'BCG',
  covers: 'Previene las formas graves de tuberculosis. Dosis única, antes de salir de la maternidad.',
  aliases: {'bcg': 'BCG'},
  doseMonths: [0],
  claimUntilMonths: 72,
  suggestions: ['BCG'],
);

const _hepB = VaccineTemplate(
  key: 'hepatitis_b',
  name: 'Hepatitis B',
  covers: 'Dosis neonatal en las primeras 12 horas de vida. Adolescentes y adultos sin '
      'vacunación previa: 3 dosis.',
  aliases: {'hepatitis b': 'Hepatitis B', 'hep b': 'Hepatitis B'},
  doseMonths: [0],
  claimUntilMonths: 24,
  suggestions: ['Hepatitis B'],
);

const _rotavirus = VaccineTemplate(
  key: 'rotavirus',
  name: 'Rotavirus',
  covers: 'Diarreas graves por rotavirus. Dosis a los 2 y 4 meses (solo en el primer semestre de vida).',
  aliases: {'rotavirus': 'Rotavirus'},
  doseMonths: [2, 4],
  claimUntilMonths: 8,
  suggestions: ['Rotavirus'],
);

const _neumococo = VaccineTemplate(
  key: 'neumococo',
  name: 'Neumococo conjugada',
  covers: 'Neumonía, meningitis y sepsis por neumococo. Bebés: 2, 4 y 12 meses. '
      'Desde los 65 años: una dosis.',
  aliases: {'neumococ': 'Neumococo conjugada', 'neumo': 'Neumococo conjugada', 'prevenar': 'Neumococo conjugada'},
  doseMonthsFor: _neumococoDoses,
  suggestions: ['Neumococo conjugada'],
);

const _quintuple = VaccineTemplate(
  key: 'quintuple',
  name: 'Quíntuple (pentavalente)',
  covers: 'Difteria, tétanos, tos convulsa, hepatitis B y Haemophilus influenzae b. '
      '2, 4 y 6 meses, y refuerzo a los 15-18 meses.',
  aliases: {'quintuple': 'Quíntuple', 'pentavalente': 'Quíntuple', 'cuadruple': 'Cuádruple'},
  doseMonths: [2, 4, 6, 18],
  claimUntilMonths: 84,
  suggestions: ['Quíntuple'],
);

const _ipv = VaccineTemplate(
  key: 'polio',
  name: 'Polio (IPV / Sabin)',
  covers: 'Poliomielitis. 2, 4 y 6 meses, y refuerzo al ingreso escolar (5 años).',
  aliases: {
    'poliomielitis': 'Polio',
    'polio': 'Polio',
    'ipv': 'Polio (IPV)',
    'salk': 'Polio (Salk)',
    'sabin': 'Polio (Sabin)',
  },
  doseMonths: [2, 4, 6, 60],
  claimUntilMonths: 216,
  suggestions: ['Polio (IPV)'],
);

const _meningococo = VaccineTemplate(
  key: 'meningococo',
  name: 'Meningococo ACYW',
  covers: 'Meningitis y sepsis por meningococo. 3 y 5 meses, refuerzo a los 15 meses y otro a los 11 años.',
  aliases: {
    'meningococ': 'Meningococo ACYW',
    'meningitis': 'Meningococo ACYW',
    'acyw': 'Meningococo ACYW',
    'acwy': 'Meningococo ACYW',
  },
  doseMonths: [3, 5, 15, 132],
  claimUntilMonths: 216,
  suggestions: ['Meningococo ACYW'],
);

const _tripleViral = VaccineTemplate(
  key: 'triple_viral',
  name: 'Triple viral',
  covers: 'Sarampión, rubéola y paperas. 1ª dosis a los 12 meses; 2ª a los 15-18 meses '
      '(nacidos desde julio de 2024) o a los 5 años (nacidos antes). Toda persona nacida '
      'después de 1965 debería tener 2 dosis.',
  aliases: {
    'triple viral': 'Triple viral',
    'doble viral': 'Doble viral',
    'sarampion': 'Triple viral',
    'rubeola': 'Triple viral',
    'paperas': 'Triple viral',
    'srp': 'Triple viral',
  },
  doseMonthsFor: _tripleViralDoses,
  claimUntilMonths: 720, // 60 años: antes de 1965 se considera inmune
  suggestions: ['Triple viral'],
);

const _hepA = VaccineTemplate(
  key: 'hepatitis_a',
  name: 'Hepatitis A',
  covers: 'Dosis única a los 12 meses.',
  aliases: {'hepatitis a': 'Hepatitis A', 'hep a': 'Hepatitis A'},
  doseMonths: [12],
  claimUntilMonths: 216,
  suggestions: ['Hepatitis A'],
);

const _varicela = VaccineTemplate(
  key: 'varicela',
  name: 'Varicela',
  covers: '1ª dosis a los 15 meses y refuerzo al ingreso escolar (5 años).',
  aliases: {'varicela': 'Varicela'},
  doseMonths: [15, 60],
  claimUntilMonths: 216,
  suggestions: ['Varicela'],
);

const _dtpCelular = VaccineTemplate(
  key: 'dtp_celular',
  name: 'Triple bacteriana celular (DTP)',
  covers: 'Difteria, tétanos y tos convulsa. Refuerzo al ingreso escolar (5-6 años).',
  aliases: {'triple bacteriana celular': 'Triple bacteriana celular (DTP)', 'dtp': 'Triple bacteriana celular (DTP)'},
  doseMonths: [60],
  claimUntilMonths: 216,
  suggestions: ['Triple bacteriana celular (DTP)'],
);

const _dtpa = VaccineTemplate(
  key: 'dtpa',
  name: 'Triple bacteriana acelular (dTpa)',
  covers: 'Difteria, tétanos y tos convulsa. Refuerzo a los 11 años y en cada embarazo '
      '(desde la semana 20).',
  aliases: {'triple bacteriana acelular': 'Triple bacteriana acelular (dTpa)', 'dtpa': 'Triple bacteriana acelular (dTpa)'},
  doseMonths: [132],
  claimUntilMonths: 216,
  suggestions: ['Triple bacteriana acelular (dTpa)'],
);

const _vph = VaccineTemplate(
  key: 'vph',
  name: 'VPH (papiloma humano)',
  covers: 'Previene cánceres y lesiones por VPH. Dosis única a los 11 años '
      '(esquemas distintos para personas inmunocomprometidas).',
  aliases: {'vph': 'VPH', 'papiloma': 'VPH', 'hpv': 'VPH', 'gardasil': 'VPH'},
  doseMonths: [132],
  claimUntilMonths: 216,
  suggestions: ['VPH'],
);

const _dt = VaccineTemplate(
  key: 'doble_adultos',
  name: 'Doble adultos (dT)',
  covers: 'Difteria y tétanos. Refuerzo cada 10 años. Una dTpa reciente también cuenta.',
  aliases: {
    'doble adultos': 'Doble adultos (dT)',
    'doble bacteriana': 'Doble adultos (dT)',
    'doble adulto': 'Doble adultos (dT)',
    'antitetanica': 'Doble adultos (dT)',
  },
  repeatEveryDays: 3650,
  claimWhen: _adultClaim,
  countsAlsoKeys: ['dtpa'],
  suggestions: ['Doble adultos (dT)'],
);

const _gripe = VaccineTemplate(
  key: 'antigripal',
  name: 'Antigripal',
  covers: 'Se aplica todos los años. Calendario: bebés de 6 a 24 meses (2 dosis la primera vez), '
      'embarazadas, personal de salud, mayores de 65 y personas con factores de riesgo.',
  aliases: {'antigripal': 'Antigripal', 'gripe': 'Antigripal', 'influenza': 'Antigripal'},
  repeatEveryDays: 365,
  claimWhen: _fluClaim,
  suggestions: ['Antigripal'],
);

const _fiebreAmarilla = VaccineTemplate(
  key: 'fiebre_amarilla',
  name: 'Fiebre amarilla',
  covers: 'Solo en zonas de riesgo o viajes. 1ª dosis a los 18 meses y refuerzo a los 11 años.',
  aliases: {'fiebre amarilla': 'Fiebre amarilla', 'amarilla': 'Fiebre amarilla'},
  doseMonths: [18, 132],
  optional: true,
  suggestions: ['Fiebre amarilla'],
);

const _fha = VaccineTemplate(
  key: 'fiebre_hemorragica',
  name: 'Fiebre hemorrágica argentina',
  covers: 'Dosis única para personas desde los 15 años que viven o trabajan en zonas endémicas.',
  aliases: {'fiebre hemorragica': 'Fiebre hemorrágica argentina', 'candid': 'Fiebre hemorrágica argentina'},
  doseMonths: [180],
  optional: true,
  suggestions: ['Fiebre hemorrágica argentina'],
);

const _covid = VaccineTemplate(
  key: 'covid',
  name: 'COVID-19',
  covers: 'Según la indicación vigente para grupos de riesgo, mayores y embarazadas.',
  aliases: {
    'covid': 'COVID-19',
    'coronavirus': 'COVID-19',
    'pfizer': 'COVID-19',
    'moderna': 'COVID-19',
    'sinopharm': 'COVID-19',
    'astrazeneca': 'COVID-19',
  },
  repeatEveryDays: 365,
  optional: true,
  suggestions: ['COVID-19'],
);

const _vsr = VaccineTemplate(
  key: 'vsr_embarazo',
  name: 'VSR (embarazo)',
  covers: 'Una dosis en cada embarazo, entre las semanas 32 y 36.6, para proteger al recién nacido '
      'de la bronquiolitis.',
  aliases: {'vsr': 'VSR (embarazo)', 'sincicial': 'VSR (embarazo)'},
  optional: true,
  suggestions: ['VSR (embarazo)'],
);

/// Evaluación del carné de una PERSONA: compara el calendario (qué corresponde
/// a su edad) con las dosis realmente cargadas.
class PersonVaccines {
  PersonVaccines._();

  /// En orden cronológico: es el orden en que aparecen dentro de cada estado.
  static const List<VaccineTemplate> all = [
    _bcg,
    _hepB,
    _rotavirus,
    _neumococo,
    _quintuple,
    _ipv,
    _meningococo,
    _tripleViral,
    _hepA,
    _varicela,
    _dtpCelular,
    _dtpa,
    _vph,
    _dt,
    _gripe,
    _fiebreAmarilla,
    _fha,
    _covid,
    _vsr,
  ];

  // ── Nombres ─────────────────────────────────────────────────────────────

  static VaccineTemplate? templateFor(String name) {
    final n = VaccineCatalog.normalize(name);
    if (n.isEmpty) return null;
    VaccineTemplate? best;
    var bestLen = 0;
    for (final t in all) {
      for (final alias in t.aliases.keys) {
        if (n.contains(alias) && alias.length > bestLen) {
          best = t;
          bestLen = alias.length;
        }
      }
    }
    return best;
  }

  static String keyFor(String name) =>
      templateFor(name)?.key ?? 'custom:${VaccineCatalog.normalize(name)}';

  /// Lo mismo que `VaccineCatalog.findInLine` pero para el calendario humano
  /// (lo usa el OCR de la libreta).
  static ({VaccineTemplate template, String label, int index, int len})? findInLine(
    String normalizedLine,
  ) {
    ({VaccineTemplate template, String label, int index, int len})? best;
    for (final t in all) {
      for (final e in t.aliases.entries) {
        final i = normalizedLine.indexOf(e.key);
        if (i < 0) continue;
        final len = e.key.length;
        if (best == null || len > best.len || (len == best.len && i < best.index)) {
          best = (template: t, label: e.value, index: i, len: len);
        }
      }
    }
    return best;
  }

  // ── Edad ────────────────────────────────────────────────────────────────

  static int monthsBetween(DateTime from, DateTime to) {
    var m = (to.year - from.year) * 12 + (to.month - from.month);
    if (to.day < from.day) m -= 1;
    return m < 0 ? 0 : m;
  }

  static DateTime addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final y = d.year + total ~/ 12;
    final m = total % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d.day > lastDay ? lastDay : d.day);
  }

  /// "Recién nacido", "5 días", "8 meses", "34 años".
  static String ageLabel(DateTime birth, DateTime now) {
    final m = monthsBetween(birth, now);
    if (m < 1) {
      final days = now.difference(birth).inDays;
      if (days <= 0) return 'Recién nacido';
      return '$days ${days == 1 ? 'día' : 'días'}';
    }
    if (m < 24) return '$m ${m == 1 ? 'mes' : 'meses'}';
    return '${m ~/ 12} años';
  }

  // ── Evaluación ──────────────────────────────────────────────────────────

  static List<VaccineSlot> evaluate({
    required DateTime? birthDate,
    required List<VaccineRecord> records,
    DateTime? now,
  }) {
    final today = VaccineCatalog.dayOf(now ?? DateTime.now());
    final age = birthDate == null ? null : monthsBetween(birthDate, today);

    // Dosis agrupadas por vacuna.
    final byKey = <String, List<VaccineRecord>>{};
    for (final r in records) {
      (byKey[keyFor(r.name)] ??= <VaccineRecord>[]).add(r);
    }

    final slots = <VaccineSlot>[];
    final used = <String>{};

    // Sin fecha de nacimiento no se puede saber qué corresponde por edad:
    // solo se muestran las dosis cargadas.
    if (birthDate != null && age != null) {
      for (final t in all) {
        used.add(t.key);
        final counted = <VaccineRecord>[
          ...?byKey[t.key],
          for (final k in t.countsAlsoKeys) ...?byKey[k],
        ]..sort((a, b) => a.date.compareTo(b.date));
        final slot = _evaluateOne(t, counted, birthDate, age, today);
        if (slot != null) slots.add(slot);
      }
    }

    // Vacunas propias del usuario (o todas, si falta la fecha de nacimiento).
    for (final e in byKey.entries) {
      if (used.contains(e.key)) continue;
      final list = [...e.value]..sort((a, b) => a.date.compareTo(b.date));
      final latest = list.last;
      slots.add(VaccineSlot(
        name: latest.name,
        template: templateFor(latest.name),
        latest: latest,
        status: VaccineCatalog.statusOfRecord(latest, today),
        dosesDone: list.length,
      ));
    }

    // Orden estable: primero por prioridad de estado, después el orden original.
    final indexed = slots.asMap().entries.toList()
      ..sort((a, b) {
        final c = a.value.status.index.compareTo(b.value.status.index);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }

  static VaccineSlot? _evaluateOne(
    VaccineTemplate t,
    List<VaccineRecord> recs,
    DateTime birth,
    int age,
    DateTime today,
  ) {
    final doses = t.doseMonthsFor?.call(birth, today) ?? t.doseMonths;
    final total = doses.isEmpty ? null : doses.length;
    final done = recs.length;
    final latest = recs.isEmpty ? null : recs.last;

    VaccineSlot slot(VaccineStatus status, {DateTime? nextDue}) => VaccineSlot(
          name: t.name,
          template: t,
          latest: latest,
          status: status,
          dosesDone: done,
          dosesTotal: total,
          nextDue: nextDue,
        );

    // Fechas contradictorias en la última dosis: siempre se avisa.
    if (latest != null && VaccineCatalog.statusOfRecord(latest, today) == VaccineStatus.verificar) {
      return slot(VaccineStatus.verificar);
    }

    // Opcionales (riesgo / zona / embarazo): sin registros no se reclaman, y
    // con registros solo cuenta la próxima dosis que cargó el usuario.
    if (t.optional) {
      if (latest == null) return null;
      return slot(VaccineCatalog.statusOfRecord(latest, today));
    }

    // ── Refuerzos periódicos (dT, antigripal) ──
    if (t.repeatEveryDays != null) {
      final claim = t.claimWhen?.call(age) ?? true;
      if (latest == null) {
        return claim ? slot(VaccineStatus.sinRegistro) : null;
      }
      if (!claim) return slot(VaccineCatalog.statusOfRecord(latest, today));
      final due = latest.nextDoseDate != null
          ? VaccineCatalog.dayOf(latest.nextDoseDate!)
          : VaccineCatalog.dayOf(latest.date).add(Duration(days: t.repeatEveryDays!));
      final VaccineStatus status;
      if (due.isBefore(today)) {
        status = VaccineStatus.pendiente;
      } else if (due.difference(today).inDays <= 60) {
        status = VaccineStatus.proxima;
      } else {
        status = VaccineStatus.aplicada;
      }
      return slot(status, nextDue: due);
    }

    // ── Series de dosis por edad ──
    if (doses.isEmpty) {
      // Sin esquema para esta edad: se muestra solo si hay dosis cargadas.
      return latest == null ? null : slot(VaccineCatalog.statusOfRecord(latest, today));
    }

    final windowOpen = t.claimUntilMonths == null || age <= t.claimUntilMonths!;
    final dueDates = [for (final m in doses) addMonths(birth, m)];
    final expected = windowOpen ? doses.where((m) => m <= age).length : done;

    if (latest == null) {
      if (!windowOpen) return null;
      if (expected > 0) return slot(VaccineStatus.sinRegistro, nextDue: dueDates.first);
      // Todavía no corresponde: solo se muestra si falta poco (hasta 1 año).
      if (doses.first - age > 12) return null;
      return slot(VaccineStatus.noCorresponde, nextDue: dueDates.first);
    }

    if (done >= doses.length) return slot(VaccineStatus.aplicada);
    if (done < expected) return slot(VaccineStatus.pendiente, nextDue: dueDates[done]);
    if (!windowOpen) return slot(VaccineStatus.aplicada);

    final next = dueDates[done];
    final soon = next.difference(today).inDays <= 365;
    return slot(soon ? VaccineStatus.proxima : VaccineStatus.aplicada, nextDue: next);
  }

  // ── Sugerencias para cargar una dosis ───────────────────────────────────

  /// Vacunas "de la edad" para ofrecer como atajos al cargar una dosis.
  static List<String> suggestionsFor(DateTime? birth, DateTime now) {
    final today = VaccineCatalog.dayOf(now);
    final age = birth == null ? null : monthsBetween(birth, today);
    final out = <String>[];
    for (final t in all) {
      if (age != null && !t.optional) {
        if (t.repeatEveryDays != null) {
          if (!(t.claimWhen?.call(age) ?? true)) continue;
        } else {
          final doses = t.doseMonthsFor?.call(birth, today) ?? t.doseMonths;
          if (doses.isEmpty) continue;
          if (doses.first > age + 3) continue;
          if (t.claimUntilMonths != null && age > t.claimUntilMonths! + 12) continue;
        }
      }
      out.addAll(t.suggestions);
    }
    return out;
  }

  /// Próxima dosis sugerida al cargar una (el usuario la acepta o la cambia):
  /// la siguiente de la serie según la edad, o el refuerzo periódico.
  static DateTime? suggestedNextDose({
    required String name,
    required DateTime appliedOn,
    required DateTime? birthDate,
    required List<VaccineRecord> records,
  }) {
    final t = templateFor(name);
    if (t == null || t.optional) return null;
    final applied = VaccineCatalog.dayOf(appliedOn);

    if (t.repeatEveryDays != null) return applied.add(Duration(days: t.repeatEveryDays!));

    if (birthDate == null) return null;
    final doses = t.doseMonthsFor?.call(birthDate, applied) ?? t.doseMonths;
    if (doses.isEmpty) return null;

    // Dosis ya cargadas de esta vacuna + la que se está cargando ahora.
    final n = records.where((r) => keyFor(r.name) == t.key).length + 1;
    if (n >= doses.length) return null; // esquema completo

    final target = addMonths(birthDate, doses[n]);
    // Si la edad de la siguiente dosis ya pasó (esquema atrasado), el mínimo
    // habitual entre dosis de refuerzo es de 4 semanas.
    return target.isAfter(applied) ? target : applied.add(const Duration(days: 28));
  }

  /// Texto de una edad en meses: "al nacer", "6 meses", "11 años".
  static String doseAgeLabel(int months) {
    if (months == 0) return 'al nacer';
    if (months < 24) return '$months ${months == 1 ? 'mes' : 'meses'}';
    final y = months ~/ 12;
    final rest = months % 12;
    return rest == 0 ? '$y años' : '$y años y $rest meses';
  }
}
