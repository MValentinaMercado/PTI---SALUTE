import 'package:saluteapp/core/models/vaccine_record.dart';
import 'package:saluteapp/core/services/vaccine_catalog.dart';

/// Extrae dosis de vacunas del texto crudo de un certificado / libreta
/// sanitaria (lo que devuelve el OCR). Es HEURÍSTICO: todo lo que sale de
/// acá es una sugerencia que el usuario revisa y corrige antes de guardar.
///
/// Criterio: no inventar. Si no se encuentra la fecha de aplicación, el
/// borrador queda sin fecha (y no se puede guardar hasta completarla).
class VaccineOcrParser {
  VaccineOcrParser._();

  static final _dateRe = RegExp(r'\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b');

  static final _vetRe = RegExp(
    r'\b(?:dr|dra|doctor|doctora|mv|m\.v|med\.?\s*vet)\b\.?\s*[:\-]?\s*(\p{L}{2,}(?:\s\p{L}{2,}){0,2})',
    caseSensitive: false,
    unicode: true,
  );

  static final _lotRe = RegExp(
    r'\b(?:lote|lot|serie|nro\.?\s*de\s*serie)\b\.?\s*[:#\-]?\s*([A-Za-z0-9][A-Za-z0-9\-\/]{2,})',
    caseSensitive: false,
  );

  static const _nextKeywords = ['prox', 'refuerzo', 'revacun', 'vence', 'vto', 'repetir'];
  static const _skipKeywords = ['nacim', 'naci '];

  static List<VaccineDraft> parse(String raw, {DateTime? now, bool person = false}) {
    final today = now ?? DateTime.now();
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];

    final norm = lines.map(VaccineCatalog.normalize).toList();
    final hits = [for (final n in norm) VaccineCatalog.findInLine(n, person: person)];

    final globalVet = _firstVet(lines);

    final drafts = <VaccineDraft>[];
    final seen = <String>{};

    for (var i = 0; i < lines.length; i++) {
      final hit = hits[i];
      if (hit == null) continue;

      // Fila "propia" + vecinas sin otra vacuna (las columnas del OCR a
      // veces separan fecha / lote en líneas contiguas).
      final window = <int>[i];
      for (final j in [i + 1, i - 1]) {
        if (j >= 0 && j < lines.length && hits[j] == null && !_isSkipLine(norm[j])) {
          window.add(j);
        }
      }

      // 1) La propia línea manda.
      final own = _split(_datesIn(lines[i], norm[i], today));
      DateTime? applied = own.applied;
      DateTime? next = own.next;

      // 2) Si falta algo, miramos las líneas vecinas.
      if (applied == null || next == null) {
        for (final j in window.skip(1)) {
          final d = _datesIn(lines[j], norm[j], today);
          if (d.isEmpty) continue;
          final s = _split(d);
          applied ??= s.applied;
          next ??= s.next;
        }
      }

      // Coherencia: el refuerzo tiene que ser posterior a la aplicación.
      if (applied != null && next != null && !next.isAfter(applied)) next = null;

      // Aplicación en el futuro = lectura dudosa: se descarta.
      if (applied != null && applied.isAfter(today.add(const Duration(days: 1)))) {
        applied = null;
      }

      String? lot;
      String? vet;
      for (final j in window) {
        lot ??= _findLot(lines[j]);
        vet ??= _findVet(lines[j]);
      }

      final draft = VaccineDraft(
        name: hit.label,
        date: applied,
        nextDoseDate: next,
        professional: vet ?? globalVet ?? '',
        lot: lot ?? '',
        source: VaccineSource.ocr,
      );

      final key = '${VaccineCatalog.keyFor(draft.name, person: person)}|${draft.date}|${draft.nextDoseDate}';
      if (seen.add(key)) drafts.add(draft);
    }

    // Más recientes primero; las que no tienen fecha, al final.
    drafts.sort((a, b) {
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return b.date!.compareTo(a.date!);
    });
    return drafts;
  }

  // ── Fechas ──────────────────────────────────────────────────────────────

  /// Fechas de una línea, en orden de aparición, marcando cuáles están
  /// precedidas por una palabra de "próxima dosis".
  static List<_FoundDate> _datesIn(String line, String normLine, DateTime today) {
    final out = <_FoundDate>[];
    var prevEnd = 0;
    for (final m in _dateRe.allMatches(line)) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      if (mo < 1 || mo > 12 || d < 1 || d > 31) continue;
      if (y < 2000 || y > today.year + 6) continue;
      final date = DateTime(y, mo, d);
      if (date.month != mo) continue; // descarta 31/02, etc.
      final before = normLine.substring(prevEnd, m.start);
      final isNext = _nextKeywords.any(before.contains);
      out.add(_FoundDate(date, isNext));
      prevEnd = m.end;
    }
    return out;
  }

  /// Reparte las fechas de una línea entre "aplicación" y "próxima".
  static ({DateTime? applied, DateTime? next}) _split(List<_FoundDate> dates) {
    if (dates.isEmpty) return (applied: null, next: null);
    if (dates.length == 1) {
      final d = dates.first;
      return d.isNext ? (applied: null, next: d.date) : (applied: d.date, next: null);
    }
    // Varias: las marcadas como "próx." son refuerzo; si ninguna lo está,
    // la más antigua es la aplicación y la más nueva el refuerzo.
    final marked = dates.where((d) => d.isNext).toList();
    final plain = dates.where((d) => !d.isNext).toList();
    if (marked.isNotEmpty) {
      return (
        applied: plain.isEmpty ? null : plain.first.date,
        next: marked.last.date,
      );
    }
    final sorted = [...dates]..sort((a, b) => a.date.compareTo(b.date));
    return (applied: sorted.first.date, next: sorted.last.date);
  }

  // ── Otros campos ────────────────────────────────────────────────────────

  static bool _isSkipLine(String normLine) => _skipKeywords.any(normLine.contains);

  static String? _findLot(String line) {
    for (final m in _lotRe.allMatches(line)) {
      final token = m.group(1)!;
      if (RegExp(r'\d').hasMatch(token)) return token;
    }
    return null;
  }

  static String? _findVet(String line) {
    final m = _vetRe.firstMatch(line);
    if (m == null) return null;
    final isFemale = RegExp(r'\bdra\b|\bdoctora\b', caseSensitive: false).hasMatch(line);
    // El nombre captura hasta 3 palabras; se corta apenas aparece una
    // palabra de la tabla ("Gomez Próx" -> "Gomez").
    final words = <String>[];
    for (final w in m.group(1)!.trim().split(RegExp(r'\s+'))) {
      if (_vetStopWords.contains(VaccineCatalog.normalize(w))) break;
      words.add(w);
    }
    if (words.isEmpty) return null;
    return '${isFemale ? 'Dra.' : 'Dr.'} ${words.join(' ')}';
  }

  static const _vetStopWords = {
    'prox', 'proxima', 'proximo', 'lote', 'serie', 'refuerzo', 'vence', 'vto',
    'fecha', 'tel', 'matricula', 'mp', 'mat', 'firma', 'sello',
  };

  static String? _firstVet(List<String> lines) {
    for (final l in lines) {
      final v = _findVet(l);
      if (v != null) return v;
    }
    return null;
  }
}

class _FoundDate {
  final DateTime date;
  final bool isNext;
  const _FoundDate(this.date, this.isNext);
}
