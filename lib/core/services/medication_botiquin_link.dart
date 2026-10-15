import 'package:saluteapp/core/models/medicine_item.dart';
import 'package:saluteapp/core/models/medication.dart';

/// Reglas de integración entre un tratamiento ([Medication], por perfil)
/// y el inventario del hogar ([MedicineItem], Mi Botiquín).
///
/// Vive como funciones puras a propósito: hoy las usan el formulario de
/// medicación, Mi Botiquín y las notificaciones, y mañana las puede usar
/// el escáner de recetas para proponer "este medicamento ya lo tenés en
/// el botiquín" sin duplicar la lógica de matching.
class MedicationBotiquinLink {
  MedicationBotiquinLink._();

  /// "Losartán 50 mg" → "losartan". Sin tildes, sin dosis, sin símbolos.
  static String normalize(String input) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    var s = input.toLowerCase();
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      buf.write(i >= 0 ? to[i] : ch);
    }
    s = buf.toString();
    s = s.replaceAll(RegExp(r'\b\d+([.,]\d+)?\s*(mg|mcg|g|gr|ml|ui|comprimidos?|comp)\b'), ' ');
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return s;
  }

  /// El ítem del botiquín que corresponde a [medName], o null.
  /// Coincidencia exacta (normalizada) gana; si no, una contiene a la
  /// otra (solo con 4+ letras, para no vincular "ibu" con cualquier cosa).
  /// A igual calidad se prefiere un ítem no vencido.
  static MedicineItem? findMatch(String medName, List<MedicineItem> items) {
    final target = normalize(medName);
    if (target.length < 3) return null;
    MedicineItem? best;
    var bestScore = 0;
    for (final item in items) {
      final candidate = normalize(item.name);
      if (candidate.isEmpty) continue;
      var score = 0;
      if (candidate == target) {
        score = 3;
      } else {
        final shorter = candidate.length < target.length ? candidate : target;
        final longer = candidate.length < target.length ? target : candidate;
        if (shorter.length >= 4 && longer.contains(shorter)) score = 2;
      }
      if (score == 0) continue;
      if (!item.isExpired) score += 1;
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    return best;
  }

  /// Ítem del botiquín asociado a [med]: primero el vínculo explícito
  /// (`botiquinItemId`), y si no hay, el que coincide por nombre.
  static MedicineItem? resolveItem(Medication med, List<MedicineItem> items) {
    final linked = med.botiquinItemId;
    if (linked != null) {
      for (final i in items) {
        if (i.id == linked) return i;
      }
    }
    return findMatch(med.name, items);
  }

  /// Para cuántos días alcanza el stock actual de [item] con el ritmo de
  /// tomas de [med]. null si no se puede calcular (sin horarios).
  static int? daysOfStockLeft(MedicineItem item, Medication med) {
    final perDay = med.unitsPerDay;
    if (perDay <= 0) return null;
    return item.currentStock ~/ perDay;
  }

  /// Si el stock NO alcanza, devuelve para cuántos días alcanza; si
  /// alcanza (o no se puede calcular), null.
  ///  - Tratamiento con duración: no alcanza para los días que faltan.
  ///  - Crónico: quedan 3 días o menos.
  static int? stockShortfallDays(MedicineItem item, Medication med) {
    final left = daysOfStockLeft(item, med);
    if (left == null) return null;
    final remaining = med.daysRemaining;
    if (remaining != null) return left < remaining ? left : null;
    return left <= 3 ? left : null;
  }
}
