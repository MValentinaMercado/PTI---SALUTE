import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/services/local_alarm_service.dart';
import 'package:saluteapp/core/services/medication_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';
import 'package:saluteapp/profile/medication_alarm_screen.dart';

enum ReminderKind { daily, at, snooze, test }

/// Lo que viaja dentro de cada notificación de medicación (campo
/// `payload`). Formato: `med|profileId|medicationId|<kind>:<dato>`.
///  - `daily:21:00`  → alarma que se repite todos los días (crónicos).
///  - `at:2026-09-20T21:00:00.000` → una toma puntual (tratamientos con duración).
///  - `snooze:<toma original>` → "posponer 15 min" de una toma.
///  - `test:` → la alerta de prueba.
class MedReminderPayload {
  final ReminderKind kind;
  final String profileId;
  final String medicationId;

  /// Hora de una alarma `daily` ("21:00").
  final String? dailyTime;

  /// Toma original para `at` y `snooze`.
  final DateTime? at;

  const MedReminderPayload({
    required this.kind,
    required this.profileId,
    required this.medicationId,
    this.dailyTime,
    this.at,
  });

  static const _prefix = 'med';

  static bool isMedication(String? raw) => raw != null && raw.startsWith('$_prefix|');

  String encode() {
    final tail = switch (kind) {
      ReminderKind.daily => 'daily:$dailyTime',
      ReminderKind.at => 'at:${at!.toIso8601String()}',
      ReminderKind.snooze => 'snooze:${at!.toIso8601String()}',
      ReminderKind.test => 'test:',
    };
    return '$_prefix|$profileId|$medicationId|$tail';
  }

  static MedReminderPayload? parse(String? raw) {
    if (!isMedication(raw)) return null;
    final parts = raw!.split('|');
    if (parts.length != 4) return null;
    final profileId = parts[1];
    final medId = parts[2];
    final tail = parts[3];
    if (tail.startsWith('daily:')) {
      final time = tail.substring(6);
      if (parseTimeOfDay(time) == null) return null;
      return MedReminderPayload(kind: ReminderKind.daily, profileId: profileId, medicationId: medId, dailyTime: time);
    }
    if (tail.startsWith('at:') || tail.startsWith('snooze:')) {
      final isSnooze = tail.startsWith('snooze:');
      final at = DateTime.tryParse(tail.substring(isSnooze ? 7 : 3));
      if (at == null) return null;
      return MedReminderPayload(
        kind: isSnooze ? ReminderKind.snooze : ReminderKind.at,
        profileId: profileId,
        medicationId: medId,
        at: at,
      );
    }
    if (tail.startsWith('test:')) {
      return MedReminderPayload(kind: ReminderKind.test, profileId: profileId, medicationId: medId);
    }
    return null;
  }

  /// A qué toma corresponde esta notificación. Las `daily` no llevan
  /// fecha: se toma la de hoy, salvo que la hora sea "de ayer" (ej. se
  /// tocó a las 00:10 una alerta de las 23:30).
  DateTime resolveScheduledAt(DateTime now) {
    if (kind == ReminderKind.daily) {
      final hm = parseTimeOfDay(dailyTime!)!;
      final today = DateTime(now.year, now.month, now.day, hm.$1, hm.$2);
      if (today.isAfter(now.add(const Duration(hours: 6)))) {
        return DateTime(now.year, now.month, now.day - 1, hm.$1, hm.$2);
      }
      return today;
    }
    return at ?? now;
  }
}

class _Entry {
  final int id;
  final DateTime when;
  final String payload;
  final String title;
  final String body;
  final bool repeatDaily;
  const _Entry(this.id, this.when, this.payload, this.title, this.body, this.repeatDaily);
}

/// Alertas locales para tomar la medicación.
///
///  - Tratamientos crónicos: UNA alarma diaria repetida por cada horario.
///  - Tratamientos con duración: una alarma por cada toma de los próximos
///    [_oneShotHorizonDays] días. Se vuelve a armar cada vez que se abre
///    la app (ver `rescheduleAll`, llamado desde SaluteShell), así la
///    ventana "se mueve" sola y el tratamiento completo queda cubierto.
///  - iOS permite máximo 64 notificaciones pendientes en total: se
///    respeta un tope, priorizando las diarias y las más próximas.
///
/// Solo se programan alertas de los perfiles que administra el usuario
/// logueado (sus hijos, mascotas, sus propias tomas): las de otro
/// miembro de la familia le corresponden a su dispositivo.
class MedicationReminderService {
  MedicationReminderService._();
  static final MedicationReminderService instance = MedicationReminderService._();

  static const int _oneShotHorizonDays = 7;
  static const int _iosPendingCap = 60;
  static const Duration snoozeDelay = Duration(minutes: 15);
  static const Duration _rescheduleThrottle = Duration(minutes: 10);

  GlobalKey<NavigatorState>? _navKey;
  StreamSubscription<String>? _tapSub;
  bool _launchConsumed = false;
  bool _rescheduling = false;
  DateTime? _lastRescheduleAt;

  // ── Programación ────────────────────────────────────────────────────

  /// Programa (o reprograma) las alertas de UNA medicación. Cancela
  /// antes las que hubiera; si la medicación está pausada, terminó, no
  /// tiene horarios o tiene los recordatorios apagados, solo cancela.
  Future<void> scheduleFor({
    required String profileId,
    required String profileName,
    required Medication medication,
  }) async {
    await LocalAlarmService.instance.ensureInit();
    await cancelFor(medication.id);
    final entries = _entriesFor(profileId, profileName, medication, DateTime.now());
    if (entries.isEmpty) return;
    final budget = await _budget();
    await _apply(entries, budget);
  }

  /// Cancela TODAS las alertas de una medicación (incluye las pospuestas).
  Future<void> cancelFor(String medicationId) async {
    await _cancelWhere((p) => p.medicationId == medicationId);
  }

  /// Vuelve a armar todas las alertas de medicación desde Firestore.
  /// Se llama al abrir la app / volver a primer plano (con tope de
  /// frecuencia). Si algo falla al leer, NO toca lo ya programado: es
  /// preferible una alerta desactualizada a quedarse sin ninguna.
  Future<void> rescheduleAll({bool force = false}) async {
    final last = _lastRescheduleAt;
    if (!force && last != null && DateTime.now().difference(last) < _rescheduleThrottle) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || _rescheduling) return;
    _rescheduling = true;

    try {
      await LocalAlarmService.instance.ensureInit();
      final profiles = await ProfileService.instance.watchProfiles().first;
      final now = DateTime.now();
      final entries = <_Entry>[];
      for (final p in profiles.where((p) => p.ownerUid == myUid)) {
        final meds = await MedicationService.instance
            .watchMedications(p.id, onlyActive: true, decryptNotes: false)
            .first;
        for (final m in meds) {
          entries.addAll(_entriesFor(p.id, p.name, m, now));
        }
      }

      // Se conservan las pospuestas ("posponer 15 min") que estén vigentes.
      await _cancelWhere((p) => p.kind != ReminderKind.snooze);
      await _apply(entries, await _budget());
      _lastRescheduleAt = DateTime.now();
    } catch (e) {
      debugPrint('MedicationReminderService.rescheduleAll falló: $e');
    } finally {
      _rescheduling = false;
    }
  }

  /// "Posponer 15 min": vuelve a avisar por la misma toma.
  Future<void> snooze({
    required String profileId,
    required String profileName,
    required Medication medication,
    required DateTime scheduledAt,
  }) async {
    final payload = MedReminderPayload(
      kind: ReminderKind.snooze,
      profileId: profileId,
      medicationId: medication.id,
      at: scheduledAt,
    ).encode();
    await LocalAlarmService.instance.schedule(
      id: _stableId('snooze|${medication.id}|${scheduledAt.toIso8601String()}'),
      title: 'Hora de tomar ${medication.name}',
      body: _body(profileName, medication),
      when: DateTime.now().add(snoozeDelay),
      details: _details(),
      payload: payload,
    );
  }

  /// Alerta de prueba (a los 5 segundos) para verificar que las
  /// notificaciones llegan y abren la pantalla de toma.
  Future<void> sendTest({
    required String profileId,
    required String profileName,
    required Medication medication,
  }) async {
    await LocalAlarmService.instance.schedule(
      id: _stableId('test|${medication.id}'),
      title: 'Prueba: hora de tomar ${medication.name}',
      body: _body(profileName, medication),
      when: DateTime.now().add(const Duration(seconds: 5)),
      details: _details(),
      payload: MedReminderPayload(
        kind: ReminderKind.test,
        profileId: profileId,
        medicationId: medication.id,
      ).encode(),
    );
  }

  // ── Internos ────────────────────────────────────────────────────────

  String _body(String profileName, Medication m) {
    final who = profileName.trim();
    final dose = m.dose.trim();
    if (who.isEmpty) return dose;
    return dose.isEmpty ? who : '$who · $dose';
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        LocalAlarmService.medicationChannelId,
        LocalAlarmService.medicationChannelName,
        channelDescription: LocalAlarmService.medicationChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
  }

  List<_Entry> _entriesFor(String profileId, String profileName, Medication med, DateTime now) {
    if (!med.active || !med.remindersEnabled || med.timesOfDay.isEmpty || med.hasEnded) {
      return const [];
    }
    final title = 'Hora de tomar ${med.name}';
    final body = _body(profileName, med);
    final entries = <_Entry>[];

    if (med.isChronic) {
      for (final t in med.timesOfDay) {
        final hm = parseTimeOfDay(t);
        if (hm == null) continue;
        var first = DateTime(now.year, now.month, now.day, hm.$1, hm.$2);
        if (!first.isAfter(now)) first = DateTime(now.year, now.month, now.day + 1, hm.$1, hm.$2);
        final start = DateTime(med.startDay.year, med.startDay.month, med.startDay.day, hm.$1, hm.$2);
        if (first.isBefore(start)) first = start;
        final payload = MedReminderPayload(
          kind: ReminderKind.daily,
          profileId: profileId,
          medicationId: med.id,
          dailyTime: t,
        ).encode();
        entries.add(_Entry(_stableId('${med.id}|$payload'), first, payload, title, body, true));
      }
    } else {
      for (var i = 0; i < _oneShotHorizonDays; i++) {
        final day = DateTime(now.year, now.month, now.day + i);
        for (final at in med.dosesOn(day)) {
          if (!at.isAfter(now)) continue;
          final payload = MedReminderPayload(
            kind: ReminderKind.at,
            profileId: profileId,
            medicationId: med.id,
            at: at,
          ).encode();
          entries.add(_Entry(_stableId('${med.id}|$payload'), at, payload, title, body, false));
        }
      }
    }
    return entries;
  }

  /// Cuántas notificaciones de medicación se pueden programar todavía.
  Future<int> _budget() async {
    if (!Platform.isIOS) return 1000;
    final pending = await LocalAlarmService.instance.plugin.pendingNotificationRequests();
    final medPending = pending.where((p) => MedReminderPayload.isMedication(p.payload)).length;
    final others = pending.length - medPending;
    return (_iosPendingCap - others).clamp(0, _iosPendingCap);
  }

  Future<void> _apply(List<_Entry> entries, int budget) async {
    // Las diarias primero (1 slot cubre todos los días), después por hora.
    entries.sort((a, b) {
      if (a.repeatDaily != b.repeatDaily) return a.repeatDaily ? -1 : 1;
      return a.when.compareTo(b.when);
    });
    for (final e in entries.take(budget)) {
      try {
        await LocalAlarmService.instance.schedule(
          id: e.id,
          title: e.title,
          body: e.body,
          when: e.when,
          details: _details(),
          payload: e.payload,
          repeatDaily: e.repeatDaily,
        );
      } catch (err) {
        debugPrint('MedicationReminderService: no se pudo programar ${e.payload}. $err');
      }
    }
  }

  Future<void> _cancelWhere(bool Function(MedReminderPayload p) test) async {
    final plugin = LocalAlarmService.instance.plugin;
    final pending = await plugin.pendingNotificationRequests();
    for (final req in pending) {
      final parsed = MedReminderPayload.parse(req.payload);
      if (parsed != null && test(parsed)) await plugin.cancel(req.id);
    }
  }

  /// Hash FNV-1a de 31 bits: estable entre ejecuciones y versiones de
  /// Dart (a diferencia de `String.hashCode`, cuya estabilidad no está
  /// garantizada), así podemos recalcular el mismo id para cancelar.
  int _stableId(String input) {
    var h = 0x811C9DC5;
    for (final c in input.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h & 0x7FFFFFFF;
  }

  // ── Toque en una alerta → pantalla de toma ─────────────────────────

  /// Engancha el Navigator de la app para abrir la pantalla de toma
  /// cuando el usuario toca una alerta. Se llama desde SaluteShell (o
  /// sea, solo hay listener mientras hay sesión iniciada).
  void attach(GlobalKey<NavigatorState> navigatorKey) {
    _navKey = navigatorKey;
    _tapSub ??= LocalAlarmService.instance.taps.listen(_open);
    _consumeLaunchPayload();
  }

  void detach() {
    _tapSub?.cancel();
    _tapSub = null;
    _navKey = null;
  }

  /// Caso "la app estaba cerrada y la abrió la notificación".
  Future<void> _consumeLaunchPayload() async {
    if (_launchConsumed) return;
    _launchConsumed = true;
    try {
      await LocalAlarmService.instance.ensureInit();
      final details = await LocalAlarmService.instance.plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        _open(details!.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('MedicationReminderService: launch details falló: $e');
    }
  }

  void _open(String? raw) {
    final payload = MedReminderPayload.parse(raw);
    if (payload == null) return; // otras notificaciones (agenda) no llevan payload
    final navigator = _navKey?.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MedicationAlarmScreen(
          profileId: payload.profileId,
          medicationId: payload.medicationId,
          scheduledAt: payload.resolveScheduledAt(DateTime.now()),
          isTest: payload.kind == ReminderKind.test,
        ),
      ),
    );
  }
}
