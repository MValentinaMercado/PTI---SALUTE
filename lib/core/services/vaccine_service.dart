import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:saluteapp/core/models/agenda_event.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/vaccine_record.dart';
import 'package:saluteapp/core/services/agenda_service.dart';
import 'package:saluteapp/core/services/attachment_service.dart';
import 'package:saluteapp/core/services/crypto_service.dart';
import 'package:saluteapp/core/services/vaccine_catalog.dart';

/// Resultado de guardar una dosis: el id y si se pudo dejar el
/// recordatorio de la próxima dosis en la agenda.
class VaccineSaveResult {
  final String id;

  /// `null` = no había próxima dosis (no correspondía crear recordatorio).
  /// `true`/`false` = se intentó crear el evento de agenda y salió bien/mal.
  final bool? reminderCreated;

  const VaccineSaveResult(this.id, this.reminderCreated);
}

/// CRUD de `profiles/{profileId}/vacunas` (carné de vacunación).
///
/// - Cifra `details` (lote, notas, adjunto, texto OCR) igual que
///   `MedicalRecordService`.
/// - Mantiene un evento de agenda tipo `vacuna` por cada próxima dosis,
///   para que dispare el recordatorio local (ver `LocalAlarmService`).
/// - Si una dosis nueva reemplaza a una próxima que estaba agendada
///   (misma vacuna), esa agenda vieja se marca como completada.
class VaccineService {
  VaccineService._();
  static final VaccineService instance = VaccineService._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String profileId) =>
      _db.collection('profiles').doc(profileId).collection('vacunas');

  Future<List<VaccineRecord>> fetch(String profileId, {int limit = 200}) async {
    final snap = await _col(profileId).orderBy('date', descending: true).limit(limit).get();
    final out = <VaccineRecord>[];
    for (final doc in snap.docs) {
      final encrypted = doc.data()['encryptedDetails'] as String?;
      Map<String, dynamic> details;
      try {
        details = encrypted != null
            ? await CryptoService.instance.decryptJson(encrypted)
            : <String, dynamic>{};
      } catch (e) {
        // Un registro indescifrable no tira abajo todo el carné.
        debugPrint('VaccineService: no se pudo descifrar ${doc.id}. $e');
        details = <String, dynamic>{};
      }
      out.add(VaccineRecord.fromFirestore(doc, details));
    }
    return out;
  }

  /// Guarda una dosis nueva (y su recordatorio, si hay próxima dosis).
  Future<VaccineSaveResult> add(
    FamilyProfile profile,
    VaccineRecord record, {
    List<VaccineRecord>? existing,
  }) async {
    final data = record.metadataToFirestore();
    data['encryptedDetails'] = await CryptoService.instance.encryptJson(record.detailsToMap());
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _col(profile.id).add(data);

    // Esta dosis "cierra" el recordatorio pendiente de la misma vacuna.
    await _completePreviousReminders(
      profile.id,
      record,
      existing,
      person: profile.type == ProfileType.persona,
    );

    final reminder = await _syncReminder(profile, record.copyWith(id: ref.id));
    return VaccineSaveResult(ref.id, reminder.created);
  }

  Future<VaccineSaveResult> update(FamilyProfile profile, VaccineRecord record) async {
    final reminder = await _syncReminder(profile, record);
    final saved = record.copyWith(
      agendaEventId: reminder.eventId,
      clearAgendaEventId: reminder.eventId == null,
    );
    final data = saved.metadataToFirestore();
    data['encryptedDetails'] = await CryptoService.instance.encryptJson(saved.detailsToMap());
    await _col(profile.id).doc(record.id).update(data);
    return VaccineSaveResult(record.id, reminder.created);
  }

  Future<void> delete(String profileId, VaccineRecord record) async {
    await _col(profileId).doc(record.id).delete();

    if (record.agendaEventId != null) {
      try {
        await AgendaService.instance.deleteEvent(record.agendaEventId!);
      } catch (e) {
        debugPrint('VaccineService: no se pudo borrar el recordatorio. $e');
      }
    }

    // Un certificado escaneado puede estar compartido por varias dosis:
    // el archivo solo se borra si ya no lo usa ninguna otra.
    final att = record.attachment;
    if (att != null) {
      try {
        final others = await fetch(profileId);
        final stillUsed = others.any((o) => o.id != record.id && o.attachment?.path == att.path);
        if (!stillUsed) await AttachmentService.instance.delete(att.path);
      } catch (e) {
        debugPrint('VaccineService: no se pudo revisar el adjunto. $e');
      }
    }
  }

  // ── Recordatorio (agenda tipo `vacuna`) ──────────────────────────────────

  /// Crea / actualiza / borra el evento de agenda según `nextDoseDate`.
  /// Nunca tira excepción: si la agenda falla, la dosis igual queda guardada.
  Future<({String? eventId, bool? created})> _syncReminder(
    FamilyProfile profile,
    VaccineRecord record,
  ) async {
    final oldId = record.agendaEventId;
    final next = record.nextDoseDate;

    try {
      if (next == null) {
        if (oldId != null) await AgendaService.instance.deleteEvent(oldId);
        return (eventId: null, created: null);
      }

      final when = DateTime(next.year, next.month, next.day, 9); // 9:00 hs
      final event = AgendaEvent(
        id: oldId ?? '',
        ownerUid: FirebaseAuth.instance.currentUser?.uid ?? '',
        profileId: profile.id,
        profileName: profile.name,
        type: AgendaEventType.vacuna,
        title: 'Vacuna: ${record.name}',
        date: when,
        reminderMinutesBefore: _reminderMinutes(when),
      );

      if (oldId != null) {
        await AgendaService.instance.updateEvent(event);
        return (eventId: oldId, created: true);
      }
      final newId = await AgendaService.instance.addEvent(event);
      if (record.id.isNotEmpty) {
        await _col(profile.id).doc(record.id).update({'agendaEventId': newId});
      }
      return (eventId: newId, created: true);
    } catch (e) {
      debugPrint('VaccineService: falló el recordatorio de agenda. $e');
      return (eventId: oldId, created: false);
    }
  }

  /// Avisa el día anterior a las 9:00; si eso ya pasó, una hora antes;
  /// si tampoco, sin alarma (el evento igual queda en la agenda).
  int? _reminderMinutes(DateTime when) {
    final now = DateTime.now();
    for (final minutes in const [1440, 60]) {
      if (when.subtract(Duration(minutes: minutes)).isAfter(now)) return minutes;
    }
    return null;
  }

  /// Una dosis nueva de la misma vacuna reemplaza al recordatorio de las
  /// dosis anteriores: esos eventos de agenda pasan a "completado".
  Future<void> _completePreviousReminders(
    String profileId,
    VaccineRecord newRecord,
    List<VaccineRecord>? existing, {
    required bool person,
  }) async {
    try {
      final all = existing ?? await fetch(profileId);
      final key = VaccineCatalog.keyFor(newRecord.name, person: person);
      for (final r in all) {
        if (r.agendaEventId == null) continue;
        if (VaccineCatalog.keyFor(r.name, person: person) != key) continue;
        if (!r.date.isBefore(newRecord.date)) continue;
        await AgendaService.instance.setStatus(r.agendaEventId!, AgendaEventStatus.completado);
      }
    } catch (e) {
      debugPrint('VaccineService: no se pudo cerrar el recordatorio anterior. $e');
    }
  }
}
