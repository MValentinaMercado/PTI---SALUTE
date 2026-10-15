import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/agenda_event.dart';
import 'package:saluteapp/core/models/dose_log.dart';
import 'package:saluteapp/core/models/dose_slot.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/services/agenda_service.dart';
import 'package:saluteapp/core/services/dose_log_service.dart';
import 'package:saluteapp/core/services/medication_botiquin_link.dart';
import 'package:saluteapp/core/services/medication_service.dart';
import 'package:saluteapp/core/services/medicine_item_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';

/// Claves de shared_preferences para "leídas"/"descartadas" (ver
/// NotificationsScreen). Viven acá, públicas, para que cualquier otra
/// pantalla (ej. el puntito del header) pueda calcular el mismo estado
/// de "sin leer" sin duplicar la lógica ni desincronizarse.
const kNotificationsReadIdsKey = 'notifications_read_ids';
const kNotificationsDismissedIdsKey = 'notifications_dismissed_ids';

/// Tipo visual de una notificación (no confundir con AgendaEventType).
enum NotificationKind { alert, reminder, info }

/// Una notificación derivada del estado real de la app (agenda, medicación,
/// botiquín, perfiles). No es un documento de Firestore ni una push
/// notification: es una vista calculada cada vez que se abre la pantalla.
///
/// Push notifications (con FCM y avisos aunque la app esté cerrada) o los
/// avisos por SMS/WhatsApp del "sistema de alerta familiar" que menciona
/// el proyecto son otra cosa — requieren integrar un servicio externo y
/// quedan fuera de este alcance.
class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime date; // fecha real del evento/vencimiento asociado
  final NotificationKind kind;
  final IconData icon;
  final Color color;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.date,
    required this.kind,
    required this.icon,
    required this.color,
  });
}

const _agendaTypeLabels = {
  AgendaEventType.turno: 'Turno',
  AgendaEventType.estudio: 'Estudio',
  AgendaEventType.vacuna: 'Vacuna',
  AgendaEventType.control: 'Control',
  AgendaEventType.medicacion: 'Medicación',
  AgendaEventType.otro: 'Evento',
};

const _agendaTypeIcons = {
  AgendaEventType.turno: Icons.event_available,
  AgendaEventType.estudio: Icons.biotech_outlined,
  AgendaEventType.vacuna: Icons.vaccines_outlined,
  AgendaEventType.control: Icons.monitor_heart_outlined,
  AgendaEventType.medicacion: Icons.medication_outlined,
  AgendaEventType.otro: Icons.event_note_outlined,
};

class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();

  /// Días sin control médico a partir de los cuales se avisa.
  static const _checkupStaleDays = 180;

  /// Cantidad de notificaciones sin leer que prende el puntito del header.
  /// Es una única fuente de verdad: el Home la escucha, y quien la cambia
  /// (NotificationsScreen al leer/descartar, o [refreshUnread]) la actualiza
  /// al instante, sin depender de que el Home se vuelva a armar.
  final ValueNotifier<int> unreadBadge = ValueNotifier<int>(0);

  // Cada actualización lleva un número; si una consulta lenta termina
  // después de otra más nueva, su resultado (viejo) se descarta.
  int _badgeSeq = 0;

  /// Recalcula el contador desde cero (agenda, medicación, botiquín,
  /// perfiles + leídas/descartadas) y lo publica en [unreadBadge].
  Future<void> refreshUnread() async {
    final seq = ++_badgeSeq;
    try {
      final count = await unreadCount();
      if (seq == _badgeSeq) unreadBadge.value = count;
    } catch (e) {
      debugPrint('NotificationsService: no se pudo actualizar el contador. $e');
    }
  }

  /// Publica un contador ya calculado (lo usa NotificationsScreen, que ya
  /// tiene la lista en memoria) e invalida cualquier [refreshUnread] en curso.
  void setUnread(int count) {
    _badgeSeq++;
    unreadBadge.value = count;
  }

  /// Cuántas de [notifications] prenden el puntito: las que no son `info`
  /// (ej. "Control pendiente" es una sugerencia, no un aviso) y que el
  /// usuario no leyó ni descartó.
  static int badgeCount(
    List<AppNotification> notifications,
    Set<String> readIds,
    Set<String> dismissedIds,
  ) {
    return notifications
        .where((n) =>
            n.kind != NotificationKind.info &&
            !dismissedIds.contains(n.id) &&
            !readIds.contains(n.id))
        .length;
  }

  Future<List<AppNotification>> generate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final profiles = await ProfileService.instance.watchProfiles().first;
    final agendaEvents = await AgendaService.instance.watchAll().first;
    final botiquin = await MedicineItemService.instance.watchAll().first;

    final notifications = <AppNotification>[];

    // ── Alcance: SOLO lo propio ───────────────────────────────────────
    // Las notificaciones de un perfil las recibe únicamente quien lo
    // administra: el perfil propio y sus dependientes (hijos, mascotas...).
    // Los perfiles de otros integrantes de la familia con cuenta propia NO
    // generan avisos acá, aunque hayan compartido sus datos con este
    // usuario (eso se consulta desde Familia, no como notificación).
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return const [];
    final ownProfiles = profiles.where((p) => p.ownerUid == myUid).toList();
    final ownProfileIds = ownProfiles.map((p) => p.id).toSet();

    // ── Agenda: turnos/estudios/vacunas vencidos sin marcar, y los de
    //    hoy/mañana ──────────────────────────────────────────────────
    for (final e in agendaEvents) {
      if (!ownProfileIds.contains(e.profileId)) continue;
      if (e.status != AgendaEventStatus.pendiente) continue;
      final label = _agendaTypeLabels[e.type] ?? 'Evento';
      final icon = _agendaTypeIcons[e.type] ?? Icons.event_note_outlined;

      if (e.isOverdue) {
        notifications.add(AppNotification(
          id: 'agenda-${e.id}',
          title: '$label vencido de ${e.profileName}',
          message: '"${e.title}" ya pasó y sigue sin marcarse como completado.',
          date: e.date,
          kind: NotificationKind.alert,
          icon: icon,
          color: const Color(0xFFE74C3C),
        ));
        continue;
      }
      final daysUntil = e.date.difference(today).inDays;
      if (daysUntil == 0 || daysUntil == 1) {
        notifications.add(AppNotification(
          id: 'agenda-${e.id}',
          title: '$label de ${e.profileName}',
          message: daysUntil == 0
              ? '"${e.title}" es hoy${e.location.isNotEmpty ? ' en ${e.location}' : ''}.'
              : '"${e.title}" es mañana${e.location.isNotEmpty ? ' en ${e.location}' : ''}.',
          date: e.date,
          kind: NotificationKind.reminder,
          icon: icon,
          color: SaluteColors.terracotta,
        ));
      }
    }

    // ── Medicación: tratamientos activos que terminan pronto ──────────
    // Solo perfiles propios (ver "Alcance" arriba). Antes también se
    // incluían los perfiles que otros integrantes compartían con este
    // usuario, y sus tratamientos aparecían como notificaciones ajenas.
    for (final p in ownProfiles) {
      List<Medication> meds;
      try {
        // decryptNotes: false → acá no hacen falta las indicaciones, y
        // así no depende de la clave de cifrado.
        meds = await MedicationService.instance
            .watchMedications(p.id, onlyActive: true, decryptNotes: false)
            .first;
      } catch (e) {
        debugPrint('NotificationsService: no se pudo leer medicación de ${p.id}. $e');
        continue;
      }
      // ── Tomas de hoy (solo perfiles que administro yo: las tomas de
      //    otro familiar las ve y las marca su propio dispositivo) ────────
      if (p.ownerUid == myUid) {
        List<DoseLog> todayLogs = const [];
        try {
          todayLogs = await DoseLogService.instance.fetchDay(p.id, today);
        } catch (e) {
          debugPrint('NotificationsService: no se pudieron leer tomas de ${p.id}. $e');
        }
        final slots = DoseSlot.buildForDay(
          profileId: p.id,
          profileName: p.name,
          medications: meds,
          logs: todayLogs,
          day: today,
        );
        for (final slot in slots) {
          final state = slot.stateAt(now);
          final hh = slot.scheduledAt.hour.toString().padLeft(2, '0');
          final mm = slot.scheduledAt.minute.toString().padLeft(2, '0');
          final doseId = 'dose-${p.id}-${slot.medication.id}-${slot.scheduledAt.millisecondsSinceEpoch}';
          if (state == DoseState.late) {
            notifications.add(AppNotification(
              id: doseId,
              title: 'Toma atrasada de ${p.name}',
              message: '${slot.medication.name} (${slot.medication.dose}) estaba programada a las $hh:$mm y sigue sin marcarse.',
              date: slot.scheduledAt,
              kind: NotificationKind.alert,
              icon: Icons.alarm_outlined,
              color: const Color(0xFFE74C3C),
            ));
          } else if (state == DoseState.pending &&
              slot.scheduledAt.difference(now) <= const Duration(hours: 1)) {
            notifications.add(AppNotification(
              id: doseId,
              title: 'Próxima toma de ${p.name}',
              message: '${slot.medication.name} (${slot.medication.dose}) a las $hh:$mm.',
              date: slot.scheduledAt,
              kind: NotificationKind.reminder,
              icon: Icons.medication_outlined,
              color: const Color(0xFF27AE60),
            ));
          }
        }
      }

      for (final m in meds) {
        // ── Botiquín ↔ tratamiento: el stock no alcanza ──────────────────
        final item = p.ownerUid == myUid ? MedicationBotiquinLink.resolveItem(m, botiquin) : null;
        if (item != null && !item.isExpired) {
          final left = MedicationBotiquinLink.stockShortfallDays(item, m);
          if (left != null) {
            notifications.add(AppNotification(
              id: 'med-stock-${p.id}-${m.id}',
              title: 'Poco stock para el tratamiento de ${p.name}',
              message: m.isChronic
                  ? 'Con lo que queda de ${item.name} alcanza para $left día${left == 1 ? '' : 's'}.'
                  : 'Con lo que queda de ${item.name} alcanza para $left día${left == 1 ? '' : 's'}, '
                      'pero al tratamiento le faltan ${m.daysRemaining} días.',
              date: now,
              kind: NotificationKind.reminder,
              icon: Icons.inventory_2_outlined,
              color: Colors.orange,
            ));
          }
        }

        if (m.isEndingSoon) {
          final days = m.daysRemaining ?? 0;
          notifications.add(AppNotification(
            id: 'med-${p.id}-${m.id}',
            title: 'Tratamiento de ${p.name} termina pronto',
            message: days == 0
                ? '${m.name} (${m.dose}) termina hoy.'
                : '${m.name} (${m.dose}) termina en $days día${days == 1 ? '' : 's'}.',
            date: m.endDate ?? now,
            kind: NotificationKind.reminder,
            icon: Icons.medication_outlined,
            color: const Color(0xFF27AE60),
          ));
        }
      }
    }

    // ── Botiquín: stock crítico o vencido ─────────────────────────────
    for (final item in botiquin) {
      if (item.isExpired) {
        notifications.add(AppNotification(
          id: 'botiquin-${item.id}',
          title: 'Medicamento vencido',
          message: '${item.name} venció y sigue en el botiquín.',
          date: item.expirationDate,
          kind: NotificationKind.alert,
          icon: Icons.dangerous_outlined,
          color: const Color(0xFFE74C3C),
        ));
      } else if (item.isCritical) {
        notifications.add(AppNotification(
          id: 'botiquin-${item.id}',
          title: 'Stock bajo de ${item.name}',
          message: 'Quedan ${item.currentStock} de ${item.totalStock} unidades.',
          date: now,
          kind: NotificationKind.reminder,
          icon: Icons.inventory_2_outlined,
          color: Colors.orange,
        ));
      }
    }

    // ── Perfiles sin control médico reciente ──────────────────────────
    // Solo perfiles propios: el último chequeo es dato clínico y el aviso
    // le corresponde a quien administra ese perfil.
    for (final p in ownProfiles) {
      final last = p.lastCheckup;
      final staleDays = last == null ? null : now.difference(last).inDays;
      if (last == null || (staleDays != null && staleDays > _checkupStaleDays)) {
        notifications.add(AppNotification(
          id: 'checkup-${p.id}',
          title: 'Control pendiente de ${p.name}',
          message: last == null
              ? 'Todavía no cargaste ningún control médico.'
              : 'Su último control fue hace $staleDays días.',
          date: last ?? DateTime(now.year - 1, now.month, now.day),
          kind: NotificationKind.info,
          icon: Icons.event_note_outlined,
          color: SaluteColors.primaryGreen,
        ));
      }
    }

    // Alertas primero, después recordatorios, después info; dentro de
    // cada grupo, lo más próximo/urgente primero.
    notifications.sort((a, b) {
      final kindOrder = {NotificationKind.alert: 0, NotificationKind.reminder: 1, NotificationKind.info: 2};
      final byKind = kindOrder[a.kind]!.compareTo(kindOrder[b.kind]!);
      if (byKind != 0) return byKind;
      return a.date.compareTo(b.date);
    });

    return notifications;
  }

  /// Cuántas notificaciones hay para mostrar el puntito del header: las
  /// que genera [generate] menos las que el usuario ya descartó o marcó
  /// como leídas en NotificationsScreen. Antes el puntito del header
  /// estaba siempre prendido, sin mirar esto —por eso aparecía aunque no
  /// hubiera nada nuevo—.
  Future<int> unreadCount() async {
    // Primero se genera (es lo lento) y recién después se leen las
    // leídas/descartadas: si el usuario descarta algo mientras tanto, el
    // resultado ya lo tiene en cuenta.
    final notifications = await generate();
    final prefs = await SharedPreferences.getInstance();
    final readIds = (prefs.getStringList(kNotificationsReadIdsKey) ?? const []).toSet();
    final dismissedIds = (prefs.getStringList(kNotificationsDismissedIdsKey) ?? const []).toSet();
    return badgeCount(notifications, readIds, dismissedIds);
  }
}