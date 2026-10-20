import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:saluteapp/core/models/agenda_event.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/vaccine_record.dart';
import 'package:saluteapp/core/services/agenda_service.dart';
import 'package:saluteapp/core/services/app_settings_service.dart';
import 'package:saluteapp/core/services/local_alarm_service.dart';
import 'package:saluteapp/core/services/person_vaccine_catalog.dart';
import 'package:saluteapp/core/services/profile_service.dart';
import 'package:saluteapp/core/services/vaccine_catalog.dart';
import 'package:saluteapp/core/services/vaccine_service.dart';
import 'package:saluteapp/profile/vaccine_card_screen.dart';

class _Entry {
  final int id;
  final DateTime when;
  final String title;
  final String body;
  final String payload;
  const _Entry(this.id, this.when, this.title, this.body, this.payload);
}

/// Recordatorios AUTOMÁTICOS de vacunas y controles.
///
/// A diferencia de los avisos de agenda (que existen solo si alguien cargó
/// un evento), acá se calcula qué corresponde a partir de lo que la app ya
/// sabe: el carné de vacunación contra el calendario (personas) o el
/// esquema orientativo (perros/gatos), y la fecha del último control.
///
/// Reglas:
///  - Vacuna próxima (dentro de 30 días): aviso 3 días antes a las 9:00
///    (o el mismo día si ya pasaron esos 3 días).
///  - Vacunas pendientes (atrasadas): UN aviso por perfil, agrupado, el
///    próximo lunes a las 10:00. Se reprograma en cada apertura de la app,
///    pero con fecha fija de calendario: abrir la app todos los días no lo
///    posterga.
///  - Control: aviso cuando se cumplen [checkupIntervalDays] del último; si
///    ya pasó (o nunca se cargó uno) un recordatorio mensual, el primer
///    lunes de cada mes.
///  - No duplica: si ya hay un evento pendiente en la agenda para esa
///    vacuna o un control futuro, no avisa por su cuenta.
///  - Solo perfiles propios (el perfil del usuario y sus dependientes).
///
/// "Sin registro" NO dispara avisos: puede ser una dosis ya aplicada que
/// todavía no se cargó, y avisar sería inventar un atraso.
///
/// Las notificaciones llevan el payload `prev|<profileId>|<vaccines|checkup>`
/// (las de medicación empiezan con `med|`, así que no se pisan).
class PreventiveReminderService {
  PreventiveReminderService._();
  static final PreventiveReminderService instance = PreventiveReminderService._();

  /// Mismo umbral que usa la pantalla de notificaciones ("Control pendiente").
  static const int checkupIntervalDays = 180;
  static const int _upcomingWindowDays = 30;
  static const int _iosPendingCap = 60;
  static const Duration _throttle = Duration(minutes: 30);
  static const String _prefix = 'prev';

  GlobalKey<NavigatorState>? _navKey;
  StreamSubscription<String>? _tapSub;
  bool _launchConsumed = false;
  bool _running = false;
  DateTime? _lastRunAt;

  // ── Programación ────────────────────────────────────────────────────

  /// Recalcula y reprograma todos los avisos preventivos. Si algo falla al
  /// leer datos, no toca lo ya programado.
  Future<void> rescheduleAll({bool force = false}) async {
    // Switch de Notificaciones apagado en Configuración: no se programa nada
    // (al apagarlo, `shell.dart` ya canceló todo lo pendiente).
    if (!AppSettingsService.instance.notificationsEnabled) return;
    final last = _lastRunAt;
    if (!force && last != null && DateTime.now().difference(last) < _throttle) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || _running) return;
    _running = true;

    try {
      await LocalAlarmService.instance.ensureInit();
      if (!await LocalAlarmService.instance.notificationsAllowed()) return;

      final profiles = await ProfileService.instance.watchProfiles().first;
      final agenda = await AgendaService.instance.watchAll().first;
      final now = DateTime.now();

      final entries = <_Entry>[];
      for (final p in profiles.where((p) => p.ownerUid == myUid)) {
        final events = agenda.where((e) => e.profileId == p.id).toList();
        entries.addAll(await _vaccineEntries(p, events, now));
        entries.addAll(_checkupEntries(p, events, now));
      }

      await _cancelAll();
      await _apply(entries, await _budget());
      _lastRunAt = DateTime.now();
    } catch (e) {
      debugPrint('PreventiveReminderService.rescheduleAll falló: $e');
    } finally {
      _running = false;
    }
  }

  /// Cancela todos los avisos preventivos (cierre de sesión, borrado de cuenta).
  Future<void> cancelAll() async {
    await LocalAlarmService.instance.ensureInit();
    await _cancelAll();
    _lastRunAt = null;
  }

  // ── Vacunas ─────────────────────────────────────────────────────────

  Future<List<_Entry>> _vaccineEntries(
    FamilyProfile p,
    List<AgendaEvent> events,
    DateTime now,
  ) async {
    List<VaccineRecord> records;
    try {
      records = await VaccineService.instance.fetch(p.id);
    } catch (e) {
      debugPrint('PreventiveReminderService: sin carné de ${p.id}. $e');
      return const [];
    }

    final slots = slotsFor(p, records, now);
    if (slots.isEmpty) return const [];

    final today = DateTime(now.year, now.month, now.day);
    final pendingVaccineEvents = events
        .where((e) => e.type == AgendaEventType.vacuna && e.status == AgendaEventStatus.pendiente)
        .map((e) => VaccineCatalog.normalize(e.title))
        .toList();
    bool hasAgendaEvent(VaccineSlot s) {
      final n = VaccineCatalog.normalize(s.name);
      return n.isNotEmpty && pendingVaccineEvents.any((t) => t.contains(n));
    }

    final out = <_Entry>[];
    final overdue = <String>[];

    for (final s in slots) {
      if (hasAgendaEvent(s)) continue; // ya tiene su propio recordatorio
      if (s.status == VaccineStatus.pendiente) {
        overdue.add(s.name);
      } else if (s.status == VaccineStatus.proxima && s.nextDue != null) {
        final due = DateTime(s.nextDue!.year, s.nextDue!.month, s.nextDue!.day);
        final days = due.difference(today).inDays;
        if (days < 0 || days > _upcomingWindowDays) continue;
        final when = upcomingReminderTime(due, now);
        if (when == null) continue;
        out.add(_Entry(
          _stableId('$_prefix|${p.id}|up|${VaccineCatalog.normalize(s.name)}'),
          when,
          'Vacuna próxima de ${p.name}',
          '${s.name} corresponde el ${_fmt(due)}.',
          '$_prefix|${p.id}|vaccines',
        ));
      }
    }

    if (overdue.isNotEmpty) {
      out.add(_Entry(
        _stableId('$_prefix|${p.id}|overdue'),
        nextMonday(now),
        'Vacunas pendientes de ${p.name}',
        '${_joinNames(overdue)}. Revisá el carné de vacunación.',
        '$_prefix|${p.id}|vaccines',
      ));
    }
    return out;
  }

  @visibleForTesting
  static List<VaccineSlot> slotsFor(FamilyProfile p, List<VaccineRecord> records, DateTime now) {
    if (p.type == ProfileType.persona) {
      return PersonVaccines.evaluate(birthDate: p.birthDate, records: records, now: now);
    }
    final species = petSpeciesFrom(p.species);
    if (species == PetSpecies.otro) return const []; // sin esquema: no se inventa
    return VaccineCatalog.evaluate(
      species: species,
      birthDate: p.birthDate,
      records: records,
      now: now,
    );
  }

  // ── Controles ───────────────────────────────────────────────────────

  List<_Entry> _checkupEntries(FamilyProfile p, List<AgendaEvent> events, DateTime now) {
    final hasFutureControl = events.any((e) =>
        e.type == AgendaEventType.control &&
        e.status == AgendaEventStatus.pendiente &&
        e.date.isAfter(now));
    if (hasFutureControl) return const [];

    final when = checkupReminderTime(p.lastCheckup, now);
    if (when == null) return const [];

    final last = p.lastCheckup;
    final String body;
    if (last == null) {
      body = 'Todavía no cargaste ningún control. Un chequeo periódico ayuda a prevenir.';
    } else {
      final days = now.difference(last).inDays;
      body = days > checkupIntervalDays
          ? 'Su último control fue hace $days días. ¿Sacás un turno?'
          : 'Se cumplen ${checkupIntervalDays ~/ 30} meses del último control. ¿Sacás un turno?';
    }
    return [
      _Entry(
        _stableId('$_prefix|${p.id}|checkup'),
        when,
        'Control de ${p.name}',
        body,
        '$_prefix|${p.id}|checkup',
      ),
    ];
  }

  // ── Fechas (puras, testeables) ──────────────────────────────────────

  /// 3 días antes a las 9:00; si ya pasó, el mismo día a las 9:00; si
  /// tampoco, `null`.
  @visibleForTesting
  static DateTime? upcomingReminderTime(DateTime due, DateTime now) {
    final threeBefore = DateTime(due.year, due.month, due.day - 3, 9);
    if (threeBefore.isAfter(now)) return threeBefore;
    final sameDay = DateTime(due.year, due.month, due.day, 9);
    return sameDay.isAfter(now) ? sameDay : null;
  }

  /// Cuándo avisar un control: al cumplirse el intervalo (si falta poco),
  /// o el recordatorio mensual si ya venció / no hay control cargado.
  @visibleForTesting
  static DateTime? checkupReminderTime(DateTime? lastCheckup, DateTime now) {
    if (lastCheckup == null) return nextMonthly(now);
    final dueDay = DateTime(lastCheckup.year, lastCheckup.month, lastCheckup.day)
        .add(const Duration(days: checkupIntervalDays));
    final dueAt = DateTime(dueDay.year, dueDay.month, dueDay.day, 10);
    if (dueAt.isAfter(now)) {
      return dueAt.difference(now).inDays <= _upcomingWindowDays ? dueAt : null;
    }
    return nextMonthly(now);
  }

  /// Próximo lunes a las 10:00 (estrictamente en el futuro).
  @visibleForTesting
  static DateTime nextMonday(DateTime now) {
    var d = DateTime(now.year, now.month, now.day, 10);
    while (d.weekday != DateTime.monday || !d.isAfter(now)) {
      d = DateTime(d.year, d.month, d.day + 1, 10);
    }
    return d;
  }

  /// Primer lunes de este mes (o del próximo, si ya pasó) a las 10:00.
  @visibleForTesting
  static DateTime nextMonthly(DateTime now) {
    DateTime firstMonday(int year, int month) {
      var d = DateTime(year, month, 1, 10);
      while (d.weekday != DateTime.monday) {
        d = DateTime(d.year, d.month, d.day + 1, 10);
      }
      return d;
    }

    final thisMonth = firstMonday(now.year, now.month);
    return thisMonth.isAfter(now) ? thisMonth : firstMonday(now.year, now.month + 1);
  }

  // ── Internos ────────────────────────────────────────────────────────

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _joinNames(List<String> names) {
    if (names.length <= 3) return names.join(', ');
    return '${names.take(3).join(', ')} y ${names.length - 3} más';
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          'agenda_reminders',
          'Recordatorios de agenda',
          channelDescription: 'Avisos de turnos, estudios, vacunas y controles.',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      );

  Future<int> _budget() async {
    if (!Platform.isIOS) return 1000;
    final pending = await LocalAlarmService.instance.plugin.pendingNotificationRequests();
    final mine = pending.where((p) => _isMine(p.payload)).length;
    return (_iosPendingCap - (pending.length - mine)).clamp(0, _iosPendingCap);
  }

  Future<void> _apply(List<_Entry> entries, int budget) async {
    entries.sort((a, b) => a.when.compareTo(b.when));
    for (final e in entries.take(budget)) {
      try {
        await LocalAlarmService.instance.schedule(
          id: e.id,
          title: e.title,
          body: e.body,
          when: e.when,
          details: _details(),
          payload: e.payload,
        );
      } catch (err) {
        debugPrint('PreventiveReminderService: no se pudo programar ${e.payload}. $err');
      }
    }
  }

  bool _isMine(String? payload) => payload != null && payload.startsWith('$_prefix|');

  Future<void> _cancelAll() async {
    final plugin = LocalAlarmService.instance.plugin;
    final pending = await plugin.pendingNotificationRequests();
    for (final req in pending) {
      if (_isMine(req.payload)) await plugin.cancel(req.id);
    }
  }

  /// Hash FNV-1a de 31 bits: estable entre ejecuciones (ver el mismo método
  /// en `MedicationReminderService`).
  int _stableId(String input) {
    var h = 0x811C9DC5;
    for (final c in input.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h & 0x7FFFFFFF;
  }

  // ── Toque en un aviso → carné de vacunación ─────────────────────────

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

  Future<void> _consumeLaunchPayload() async {
    if (_launchConsumed) return;
    _launchConsumed = true;
    try {
      await LocalAlarmService.instance.ensureInit();
      final details = await LocalAlarmService.instance.plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        await _open(details!.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('PreventiveReminderService: launch details falló: $e');
    }
  }

  Future<void> _open(String? raw) async {
    if (!_isMine(raw)) return;
    final parts = raw!.split('|');
    if (parts.length != 3 || parts[2] != 'vaccines') return; // control: solo abre la app
    try {
      final profiles = await ProfileService.instance.watchProfiles().first;
      final profile = profiles.where((p) => p.id == parts[1]).firstOrNull;
      final navigator = _navKey?.currentState;
      if (profile == null || navigator == null) return;
      navigator.push(MaterialPageRoute(builder: (_) => VaccineCardScreen(profile: profile)));
    } catch (e) {
      debugPrint('PreventiveReminderService: no se pudo abrir el carné. $e');
    }
  }
}
