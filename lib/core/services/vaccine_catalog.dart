import 'package:saluteapp/core/models/vaccine_record.dart';
import 'package:saluteapp/core/services/person_vaccine_catalog.dart';

/// Especies con plantilla sanitaria predefinida. Para cualquier otra
/// especie (`otro`) no hay plantilla: el usuario arma su propio carné.
enum PetSpecies { perro, gato, otro }

PetSpecies petSpeciesFrom(String? raw) {
  final s = VaccineCatalog.normalize(raw ?? '');
  if (s.isEmpty) return PetSpecies.otro;
  if (s.contains('perr') || s.contains('canin') || s == 'dog' || s.contains('cachorr')) {
    return PetSpecies.perro;
  }
  if (s.contains('gat') || s.contains('felin') || s == 'cat') return PetSpecies.gato;
  return PetSpecies.otro;
}

/// Una vacuna de la plantilla. IMPORTANTE: es una guía ORIENTATIVA (los
/// esquemas reales los define el veterinario según edad, riesgo y zona).
class VaccineTemplate {
  /// Clave estable: agrupa dosis de la misma vacuna aunque el nombre
  /// escrito varíe ("Sextuple", "séxtuple", "DHPP"...).
  final String key;
  final String name;
  final String covers;

  /// alias normalizado (sin tildes, minúsculas) -> nombre para mostrar.
  final Map<String, String> aliases;

  /// Edad mínima orientativa de la primera dosis. Antes de eso la vacuna
  /// figura "No corresponde todavía". `null` = sin límite.
  final int? minAgeWeeks;

  /// Intervalo habitual del refuerzo. Solo sirve para SUGERIR la próxima
  /// fecha al cargar una dosis (el usuario la acepta o la cambia).
  final int boosterIntervalDays;

  /// Opcional según riesgo/criterio del veterinario: si no hay registros,
  /// no se muestra como faltante.
  final bool optional;

  /// Nombres cortos para elegir al cargar una dosis.
  final List<String> suggestions;

  // ── Solo personas (ver `PersonVaccines`) ──

  /// Edad (en meses) a la que corresponde cada dosis de la serie.
  final List<int> doseMonths;

  /// Igual que [doseMonths] pero según la fecha de nacimiento / el día de hoy
  /// (ej.: triple viral cambió de esquema para los nacidos desde 7/2024).
  final List<int> Function(DateTime? birth, DateTime today)? doseMonthsFor;

  /// Refuerzo periódico (dT cada 10 años, antigripal anual).
  final int? repeatEveryDays;

  /// Pasada esta edad (en meses) una dosis que falta ya no se reclama.
  final int? claimUntilMonths;

  /// Para vacunas periódicas: a qué edades se espera aunque no haya registros.
  final bool Function(int ageMonths)? claimWhen;

  /// Claves de otras vacunas cuyas dosis también cuentan como esta
  /// (una dTpa reciente sirve como refuerzo de dT).
  final List<String> countsAlsoKeys;

  const VaccineTemplate({
    required this.key,
    required this.name,
    required this.covers,
    required this.aliases,
    this.minAgeWeeks,
    this.boosterIntervalDays = 365,
    this.optional = false,
    this.suggestions = const [],
    this.doseMonths = const [],
    this.doseMonthsFor,
    this.repeatEveryDays,
    this.claimUntilMonths,
    this.claimWhen,
    this.countsAlsoKeys = const [],
  });
}

const _rabies = VaccineTemplate(
  key: 'antirrabica',
  name: 'Antirrábica',
  covers: 'Rabia. Refuerzo anual.',
  aliases: {'antirrabica': 'Antirrábica', 'rabia': 'Antirrábica'},
  minAgeWeeks: 12,
  suggestions: ['Antirrábica'],
);

const _dogMultiple = VaccineTemplate(
  key: 'multiple_canina',
  name: 'Múltiple (quíntuple / séxtuple)',
  covers: 'Moquillo, hepatitis, parvovirus, parainfluenza y, según la '
      'versión, leptospirosis. Los cachorros llevan varias dosis; luego refuerzo anual.',
  aliases: {
    'octuple': 'Óctuple',
    'sextuple': 'Séxtuple',
    'quintuple': 'Quíntuple',
    'dhpp': 'DHPP',
    'moquillo': 'Moquillo',
    'parvovirus': 'Parvovirus',
    'parvo': 'Parvovirus',
    'leptospirosis': 'Leptospirosis',
  },
  minAgeWeeks: 6,
  suggestions: ['Quíntuple', 'Séxtuple', 'Óctuple'],
);

const _kennelCough = VaccineTemplate(
  key: 'bordetella',
  name: 'Tos de las perreras',
  covers: 'Bordetella. Según riesgo (guarderías, hoteles, exposiciones).',
  aliases: {
    'tos de las perreras': 'Tos de las perreras',
    'bordetella': 'Tos de las perreras',
    'traqueobronquitis': 'Tos de las perreras',
  },
  minAgeWeeks: 8,
  optional: true,
  suggestions: ['Tos de las perreras'],
);

const _felineTriple = VaccineTemplate(
  key: 'triple_felina',
  name: 'Triple felina',
  covers: 'Panleucopenia, calicivirus y rinotraqueítis. Los gatitos llevan '
      'varias dosis; luego refuerzo anual.',
  aliases: {
    'triple felina': 'Triple felina',
    'cuadruple felina': 'Cuádruple felina',
    'panleucopenia': 'Triple felina',
    'calicivirus': 'Triple felina',
    'rinotraqueitis': 'Triple felina',
    'triple': 'Triple felina',
  },
  minAgeWeeks: 8,
  suggestions: ['Triple felina'],
);

const _felv = VaccineTemplate(
  key: 'leucemia_felina',
  name: 'Leucemia felina',
  covers: 'FeLV. Según riesgo (gatos con acceso al exterior o convivencia con otros gatos).',
  aliases: {
    'leucemia': 'Leucemia felina',
    'felv': 'Leucemia felina',
  },
  minAgeWeeks: 8,
  optional: true,
  suggestions: ['Leucemia felina'],
);

/// Catálogo de plantillas + utilidades de nombres + evaluación del carné.
class VaccineCatalog {
  VaccineCatalog._();

  static List<VaccineTemplate> forSpecies(PetSpecies s) {
    switch (s) {
      case PetSpecies.perro:
        return const [_rabies, _dogMultiple, _kennelCough];
      case PetSpecies.gato:
        return const [_felineTriple, _rabies, _felv];
      case PetSpecies.otro:
        return const [];
    }
  }

  static const List<VaccineTemplate> _all = [
    _rabies,
    _dogMultiple,
    _kennelCough,
    _felineTriple,
    _felv,
  ];

  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .trim();

  /// Plantilla a la que pertenece un nombre escrito a mano, o `null` si
  /// es una vacuna propia del usuario.
  static VaccineTemplate? templateFor(String name, {bool person = false}) {
    if (person) return PersonVaccines.templateFor(name);
    final n = normalize(name);
    if (n.isEmpty) return null;
    VaccineTemplate? best;
    var bestLen = 0;
    for (final t in _all) {
      for (final alias in t.aliases.keys) {
        if (n.contains(alias) && alias.length > bestLen) {
          best = t;
          bestLen = alias.length;
        }
      }
    }
    return best;
  }

  /// Clave de agrupación: la de la plantilla, o el nombre normalizado.
  static String keyFor(String name, {bool person = false}) =>
      templateFor(name, person: person)?.key ?? 'custom:${normalize(name)}';

  /// Plantilla que aparece en [normalizedLine] (ya normalizada), con el
  /// nombre para mostrar del alias encontrado. Gana el alias más largo; a
  /// igualdad, el que aparece primero. Lo usa el OCR.
  static ({VaccineTemplate template, String label, int index, int len})? findInLine(
    String normalizedLine, {
    bool person = false,
  }) {
    if (person) return PersonVaccines.findInLine(normalizedLine);
    ({VaccineTemplate template, String label, int index, int len})? best;
    for (final t in _all) {
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

  /// Fecha sugerida de refuerzo para una dosis (null si no hay plantilla).
  static DateTime? suggestedNextDose(String name, DateTime appliedOn) {
    final t = templateFor(name);
    if (t == null) return null;
    return appliedOn.add(Duration(days: t.boosterIntervalDays));
  }

  // ── Evaluación: calendario (qué corresponde) vs historial (qué pasó) ──

  /// Compara la plantilla de la especie con el historial real.
  /// Nunca inventa dosis: lo que no está registrado queda "sin registro".
  static List<VaccineSlot> evaluate({
    required PetSpecies species,
    required DateTime? birthDate,
    required List<VaccineRecord> records,
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());

    // Última dosis registrada por vacuna.
    final latest = <String, VaccineRecord>{};
    final names = <String, String>{};
    for (final r in records) {
      final k = keyFor(r.name);
      final cur = latest[k];
      if (cur == null || r.date.isAfter(cur.date)) {
        latest[k] = r;
        names[k] = r.name;
      }
    }

    final slots = <VaccineSlot>[];
    final used = <String>{};

    for (final t in forSpecies(species)) {
      used.add(t.key);
      final rec = latest[t.key];
      if (rec != null) {
        slots.add(VaccineSlot(
          name: t.name,
          template: t,
          latest: rec,
          status: _statusOf(rec, today),
        ));
      } else if (t.optional) {
        continue; // opcional y sin registros: no se reclama
      } else if (_tooYoung(t, birthDate, today)) {
        slots.add(VaccineSlot(name: t.name, template: t, status: VaccineStatus.noCorresponde));
      } else {
        slots.add(VaccineSlot(name: t.name, template: t, status: VaccineStatus.sinRegistro));
      }
    }

    // Vacunas fuera de la plantilla (o de otra especie / propias).
    for (final e in latest.entries) {
      if (used.contains(e.key)) continue;
      slots.add(VaccineSlot(
        name: names[e.key] ?? e.value.name,
        template: templateFor(e.value.name),
        latest: e.value,
        status: _statusOf(e.value, today),
      ));
    }

    slots.sort((a, b) => a.status.index.compareTo(b.status.index));
    return slots;
  }

  static bool _tooYoung(VaccineTemplate t, DateTime? birth, DateTime today) {
    if (t.minAgeWeeks == null || birth == null) return false;
    return today.difference(_day(birth)).inDays < t.minAgeWeeks! * 7;
  }

  static VaccineStatus _statusOf(VaccineRecord r, DateTime today) {
    final applied = _day(r.date);
    final next = r.nextDoseDate == null ? null : _day(r.nextDoseDate!);
    // Información contradictoria: aplicada en el futuro, o refuerzo
    // anterior o igual a la propia aplicación.
    if (applied.isAfter(today.add(const Duration(days: 1)))) return VaccineStatus.verificar;
    if (next != null && !next.isAfter(applied)) return VaccineStatus.verificar;
    if (next == null) return VaccineStatus.aplicada;
    return next.isBefore(today) ? VaccineStatus.pendiente : VaccineStatus.proxima;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Accesos públicos para el catálogo de personas.
  static DateTime dayOf(DateTime d) => _day(d);
  static VaccineStatus statusOfRecord(VaccineRecord r, DateTime today) => _statusOf(r, today);
}

/// El orden del enum es el orden de prioridad en pantalla.
enum VaccineStatus {
  verificar,
  pendiente,
  proxima,
  sinRegistro,
  aplicada,
  noCorresponde,
}

extension VaccineStatusLabel on VaccineStatus {
  String get label {
    switch (this) {
      case VaccineStatus.aplicada:
        return 'Al día';
      case VaccineStatus.proxima:
        return 'Próxima';
      case VaccineStatus.pendiente:
        return 'Pendiente';
      case VaccineStatus.sinRegistro:
        return 'Sin registro';
      case VaccineStatus.noCorresponde:
        return 'Aún no corresponde';
      case VaccineStatus.verificar:
        return 'Verificar';
    }
  }
}

class VaccineSlot {
  final String name;
  final VaccineTemplate? template;
  final VaccineRecord? latest;
  final VaccineStatus status;

  // ── Solo personas ──

  /// Dosis cargadas de esta vacuna.
  final int dosesDone;

  /// Dosis que tiene la serie completa (`null` = sin serie: refuerzo
  /// periódico u opcional).
  final int? dosesTotal;

  /// Fecha en que corresponde (o correspondía) la próxima dosis.
  final DateTime? nextDue;

  const VaccineSlot({
    required this.name,
    required this.status,
    this.template,
    this.latest,
    this.dosesDone = 0,
    this.dosesTotal,
    this.nextDue,
  });
}
