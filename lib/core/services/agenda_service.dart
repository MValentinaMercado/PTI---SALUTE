import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:saluteapp/core/models/agenda_event.dart';
import 'package:saluteapp/core/services/local_alarm_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';

/// CRUD de `agenda` (turnos, estudios, vacunas y controles), colgando de
/// una colección top-level filtrada por `profileId` (ver firestore.rules).
///
/// BUGFIX (2026-09): `watchAll()` antes hacía `where('uid', ==, miUid)`
/// sobre toda la colección para poder listar "todos los turnos de la
/// familia" en una sola query. El problema: la regla de lectura de
/// `agenda` no depende de `uid`, depende de `profileId` (¿administrás ese
/// perfil o tenés consentimiento clínico compartido?). Apenas esa query
/// devolvía UN documento que no pasaba esa regla — por ejemplo un evento
/// que vos mismo creaste para el perfil de un familiar sin
/// `sharedWithUids` — Firestore no filtraba ese documento: rechazaba la
/// consulta ENTERA con permission-denied. Como esta stream la usan
/// Agenda, Home (próximos turnos), Diario y el generador de
/// notificaciones, un solo documento así tiraba abajo medio app.
///
/// Ahora `watchAll()` arma el listado combinando una query por cada
/// perfil sobre el que el usuario YA tiene consentimiento clínico
/// (mismo criterio que exige la regla de lectura), tomando esos perfiles
/// de `ProfileService.watchProfiles()`. Un perfil problemático ya ni se
/// consulta, y si algo falla igual solo se cae ese perfil puntual, no
/// el resto.
class AgendaService {
  AgendaService._();
  static final AgendaService instance = AgendaService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('agenda');

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('No hay usuario logueado.');
    }
    return uid;
  }

  /// Todos los eventos de los perfiles que el usuario ADMINISTRA (el suyo
  /// y sus dependientes: hijos, mascotas...), ordenados por fecha. Se
  /// actualiza solo si cambia esa lista de perfiles o los eventos de alguno.
  ///
  /// A propósito NO incluye los perfiles de otros integrantes de la familia,
  /// aunque hayan compartido sus datos con el usuario: la agenda es privada
  /// y eso se mira desde Familia, no mezclado con los turnos propios. Esta
  /// stream también la usan el Home (próximos turnos) y las notificaciones,
  /// así que unos y otras muestran solo lo propio.
  Stream<List<AgendaEvent>> watchAll() {
    late StreamController<List<AgendaEvent>> controller;
    StreamSubscription? profilesSub;
    final eventsByProfile = <String, List<AgendaEvent>>{};
    final subsByProfile = <String, StreamSubscription>{};

    void emit() {
      if (controller.isClosed) return;
      final all = eventsByProfile.values.expand((e) => e).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      controller.add(all);
    }

    void start() {
      profilesSub = ProfileService.instance.watchProfiles().listen((profiles) {
        String myUid;
        try {
          myUid = _uid;
        } catch (_) {
          return;
        }
        final visibleIds = profiles
            .where((p) => p.ownerUid == myUid)
            .map((p) => p.id)
            .toSet();

        // Dar de baja perfiles que ya no son visibles (se dejaron de
        // compartir, o cambiaron de familia).
        for (final id in subsByProfile.keys.toList()) {
          if (!visibleIds.contains(id)) {
            subsByProfile.remove(id)?.cancel();
            eventsByProfile.remove(id);
          }
        }
        // Suscribirse a los perfiles nuevos.
        for (final id in visibleIds) {
          if (subsByProfile.containsKey(id)) continue;
          subsByProfile[id] = watchForProfile(id).listen(
                (events) {
              eventsByProfile[id] = events;
              emit();
            },
            onError: (_) {
              // Defensivo: si por algún motivo puntual este perfil falla,
              // no arrastramos al resto de la agenda con él.
              eventsByProfile[id] = const [];
              emit();
            },
          );
        }
        emit();
      });
    }

    controller = StreamController<List<AgendaEvent>>.broadcast(
      onListen: start,
      onCancel: () {
        profilesSub?.cancel();
        for (final s in subsByProfile.values) {
          s.cancel();
        }
        subsByProfile.clear();
      },
    );

    return controller.stream;
  }

  /// Eventos de un perfil puntual.
  Stream<List<AgendaEvent>> watchForProfile(String profileId) {
    return _col.where('profileId', isEqualTo: profileId).snapshots().map((snap) {
      final events = snap.docs.map(AgendaEvent.fromFirestore).toList();
      events.sort((a, b) => a.date.compareTo(b.date));
      return events;
    });
  }

  /// El próximo evento pendiente de un perfil (para la tarjeta de alertas).
  Stream<AgendaEvent?> watchNextForProfile(String profileId) {
    return watchForProfile(profileId).map((events) {
      final upcoming = events.where((e) => e.isUpcoming).toList();
      return upcoming.isEmpty ? null : upcoming.first;
    });
  }

  Future<String> addEvent(AgendaEvent event) async {
    final myUid = _uid;
    final data = event.toFirestore();
    data['uid'] = myUid;
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _col.add(data);
    if (event.reminderMinutesBefore != null) {
      await LocalAlarmService.instance.scheduleFor(
        AgendaEvent(
          id: ref.id,
          ownerUid: myUid,
          profileId: event.profileId,
          profileName: event.profileName,
          type: event.type,
          status: event.status,
          title: event.title,
          location: event.location,
          date: event.date,
          reminderMinutesBefore: event.reminderMinutesBefore,
        ),
      );
    }
    return ref.id;
  }

  Future<void> updateEvent(AgendaEvent event) async {
    await _col.doc(event.id).update(event.toFirestore());
    await LocalAlarmService.instance.scheduleFor(event);
  }

  Future<void> setStatus(String eventId, AgendaEventStatus status) async {
    await _col.doc(eventId).update({'status': status.name});
    if (status != AgendaEventStatus.pendiente) {
      await LocalAlarmService.instance.cancelFor(eventId);
    }
  }

  Future<void> deleteEvent(String eventId) async {
    await _col.doc(eventId).delete();
    await LocalAlarmService.instance.cancelFor(eventId);
  }

  /// Borra varios eventos de una vez (selección múltiple en la agenda).
  /// Cada evento se borra por separado: si uno falla (ej. permisos) los demás
  /// igual se eliminan. Devuelve cuántos se borraron.
  Future<int> deleteEvents(Iterable<String> eventIds) async {
    var deleted = 0;
    for (final id in eventIds) {
      try {
        await deleteEvent(id);
        deleted++;
      } catch (_) {
        // Se sigue con el resto; el llamador compara contra el total.
      }
    }
    return deleted;
  }

  /// Vuelve a programar los recordatorios de todos los eventos pendientes
  /// (al reactivar las notificaciones en Configuración).
  Future<void> rescheduleAllAlarms() async {
    try {
      final events = await watchAll().first;
      for (final e in events) {
        if (e.reminderTime != null) await LocalAlarmService.instance.scheduleFor(e);
      }
    } catch (_) {}
  }
}
