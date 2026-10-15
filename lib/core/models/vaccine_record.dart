import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:saluteapp/core/services/attachment_service.dart';

/// De dónde salió el registro: lo cargó el usuario a mano o se armó a
/// partir de la lectura (OCR) de un certificado y el usuario lo confirmó.
enum VaccineSource { manual, ocr }

VaccineSource vaccineSourceFromString(String value) {
  return VaccineSource.values.firstWhere(
    (s) => s.name == value,
    orElse: () => VaccineSource.manual,
  );
}

/// Una dosis YA APLICADA, colgando de `profiles/{profileId}/vacunas/{id}`.
///
/// El carné guarda lo que ocurrió de verdad (historial); lo que "debería
/// corresponder" sale del catálogo (ver `VaccineCatalog`) y se compara
/// recién al mostrar. Por eso acá nunca se inventan dosis.
///
/// - Metadatos consultables (SIN cifrar): nombre, fechas, veterinario,
///   origen, id del evento de agenda.
/// - `details` (CIFRADO, ver CryptoService): lote, notas, adjunto y el
///   texto crudo del OCR.
class VaccineRecord {
  final String id;
  final String name;

  /// Fecha de aplicación de la dosis.
  final DateTime date;

  /// Próxima dosis / refuerzo indicado (por el certificado, el veterinario
  /// o la sugerencia del catálogo que el usuario aceptó). `null` = no hay.
  final DateTime? nextDoseDate;

  final String professional;
  final VaccineSource source;

  /// Evento de agenda (`agenda/{id}`, tipo vacuna) que dispara el
  /// recordatorio de la próxima dosis. `null` si no se creó.
  final String? agendaEventId;

  // ── Dentro de `details` (cifrado) ──
  final String lot;
  final String notes;
  final OrderAttachment? attachment;
  final String ocrText;

  const VaccineRecord({
    required this.id,
    required this.name,
    required this.date,
    this.nextDoseDate,
    this.professional = '',
    this.source = VaccineSource.manual,
    this.agendaEventId,
    this.lot = '',
    this.notes = '',
    this.attachment,
    this.ocrText = '',
  });

  Map<String, dynamic> detailsToMap() => {
        if (lot.isNotEmpty) 'lot': lot,
        if (notes.isNotEmpty) 'notes': notes,
        if (attachment != null) ...attachment!.toDetails(),
        if (ocrText.trim().isNotEmpty)
          'ocrText': ocrText.length > 6000 ? ocrText.substring(0, 6000) : ocrText,
      };

  factory VaccineRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> details,
  ) {
    final data = doc.data() ?? {};
    return VaccineRecord(
      id: doc.id,
      name: data['name'] as String? ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      nextDoseDate: (data['nextDoseDate'] as Timestamp?)?.toDate(),
      professional: data['professional'] as String? ?? '',
      source: vaccineSourceFromString(data['source'] as String? ?? 'manual'),
      agendaEventId: data['agendaEventId'] as String?,
      lot: details['lot'] as String? ?? '',
      notes: details['notes'] as String? ?? '',
      attachment: OrderAttachment.fromDetails(details),
      ocrText: details['ocrText'] as String? ?? '',
    );
  }

  Map<String, dynamic> metadataToFirestore() => {
        'name': name,
        'date': Timestamp.fromDate(date),
        'nextDoseDate': nextDoseDate != null ? Timestamp.fromDate(nextDoseDate!) : null,
        'professional': professional,
        'source': source.name,
        'agendaEventId': agendaEventId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  VaccineRecord copyWith({
    String? id,
    String? agendaEventId,
    bool clearAgendaEventId = false,
  }) {
    return VaccineRecord(
      id: id ?? this.id,
      name: name,
      date: date,
      nextDoseDate: nextDoseDate,
      professional: professional,
      source: source,
      agendaEventId: clearAgendaEventId ? null : (agendaEventId ?? this.agendaEventId),
      lot: lot,
      notes: notes,
      attachment: attachment,
      ocrText: ocrText,
    );
  }
}

/// Borrador editable de una dosis: lo que sale del OCR o del formulario
/// ANTES de confirmarse. A diferencia de [VaccineRecord], la fecha puede
/// faltar (si el OCR no la encontró NO se inventa una): no se puede
/// guardar hasta que el usuario la complete.
class VaccineDraft {
  String name;
  DateTime? date;
  DateTime? nextDoseDate;
  String professional;
  String lot;
  String notes;
  VaccineSource source;

  VaccineDraft({
    this.name = '',
    this.date,
    this.nextDoseDate,
    this.professional = '',
    this.lot = '',
    this.notes = '',
    this.source = VaccineSource.manual,
  });

  bool get isComplete => name.trim().isNotEmpty && date != null;

  VaccineDraft copy() => VaccineDraft(
        name: name,
        date: date,
        nextDoseDate: nextDoseDate,
        professional: professional,
        lot: lot,
        notes: notes,
        source: source,
      );

  factory VaccineDraft.fromRecord(VaccineRecord r) => VaccineDraft(
        name: r.name,
        date: r.date,
        nextDoseDate: r.nextDoseDate,
        professional: r.professional,
        lot: r.lot,
        notes: r.notes,
        source: r.source,
      );
}
