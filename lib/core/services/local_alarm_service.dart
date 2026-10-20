import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:saluteapp/core/services/app_settings_service.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:saluteapp/core/models/agenda_event.dart';

/// Alarmas locales (notificaciones programadas en el dispositivo) para
/// eventos de la agenda y, desde `MedicationReminderService`, para las
/// tomas de medicación. Corre 100% en el celular: no depende de que la
/// app esté abierta ni de conexión, así que sirve como recordatorio real
/// de "en X minutos tenés el turno de Juana".
///
/// Requiere:
///  - Dependencias en pubspec.yaml: `flutter_local_notifications` y
///    `timezone` (ver comentario al final de este archivo).
///  - Llamar a `LocalAlarmService.instance.init()` una vez, apenas arranca
///    la app (en `main()`, antes de `runApp`).
///  - Android: permiso `POST_NOTIFICATIONS` (Android 13+) y, si querés que
///    la alarma sea exacta al minuto, `SCHEDULE_EXACT_ALARM` en el
///    AndroidManifest.xml. iOS: se pide permiso solo la primera vez que se
///    llama a `init()`.
class LocalAlarmService {
  LocalAlarmService._();
  static final LocalAlarmService instance = LocalAlarmService._();

  static const String medicationChannelId = 'medication_reminders';
  static const String medicationChannelName = 'Recordatorios de medicación';
  static const String medicationChannelDescription = 'Avisos para tomar tus medicamentos.';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Payloads de las notificaciones que el usuario tocó con la app viva
  /// (en segundo plano o abierta). Para el caso "la notificación abrió la
  /// app desde cero" ver `plugin.getNotificationAppLaunchDetails()`.
  final _taps = StreamController<String>.broadcast();
  Stream<String> get taps => _taps.stream;

  FlutterLocalNotificationsPlugin get plugin => _plugin;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      final deviceTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTz.identifier));
    } catch (_) {
      // Si por algún motivo no se puede leer la zona horaria del
      // dispositivo, seguimos en UTC antes que romper el init entero;
      // las alarmas van a quedar corridas hasta que se pueda leer bien.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _taps.add(payload);
      },
    );

    if (Platform.isAndroid) {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      await androidImpl?.requestExactAlarmsPermission();
      await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        'agenda_reminders',
        'Recordatorios de agenda',
        description: 'Avisos de turnos, estudios, vacunas y controles.',
        importance: Importance.high,
      ));
      await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        medicationChannelId,
        medicationChannelName,
        description: medicationChannelDescription,
        importance: Importance.max,
      ));
    }
    _initialized = true;
  }

  Future<void> ensureInit() async {
    if (!_initialized) await init();
  }

  /// ¿Puede el sistema mostrar notificaciones de esta app? Si el usuario
  /// las desactivó en los ajustes del teléfono, ninguna alerta de
  /// medicación se va a ver. Si no se puede saber, devuelve `true` (no
  /// alarmamos al usuario sin motivo).
  Future<bool> notificationsAllowed() async {
    try {
      await ensureInit();
      if (Platform.isAndroid) {
        final impl = _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await impl?.areNotificationsEnabled() ?? true;
      }
      if (Platform.isIOS) {
        final impl = _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        final options = await impl?.checkPermissions();
        return options?.isEnabled ?? true;
      }
    } catch (_) {
      // Sin datos: asumimos que sí.
    }
    return true;
  }

  /// Pide el permiso de notificaciones al sistema y devuelve si quedó
  /// permitido. Se usa al activar el switch en Configuración.
  Future<bool> requestNotificationsPermission() async {
    try {
      await ensureInit();
      if (Platform.isAndroid) {
        final impl = _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await impl?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        final impl = _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        await impl?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {}
    return notificationsAllowed();
  }

  /// Cancela TODAS las notificaciones pendientes (switch apagado en
  /// Configuración).
  Future<void> cancelAllPending() async {
    await ensureInit();
    await _plugin.cancelAll();
  }

  /// Id numérico estable derivado del id de Firestore (los ids de
  /// notification de flutter_local_notifications son int).
  int _notifId(String eventId) => eventId.hashCode & 0x7fffffff;

  /// Programa (o reprograma, si ya existía) la alarma de un evento según
  /// `event.reminderTime`. Si el evento no tiene recordatorio configurado,
  /// o ya no tiene sentido (pasado, completado, cancelado), cancela
  /// cualquier alarma previa y no programa nada.
  Future<void> scheduleFor(AgendaEvent event) async {
    await ensureInit();
    final id = _notifId(event.id);
    await _plugin.cancel(id);

    final when = event.reminderTime;
    if (when == null || event.status != AgendaEventStatus.pendiente) return;

    await schedule(
      id: id,
      title: event.title,
      body: event.location.isNotEmpty
          ? '${event.profileName} · ${event.location}'
          : event.profileName,
      when: when,
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          'agenda_reminders',
          'Recordatorios de agenda',
          channelDescription: 'Avisos de turnos, estudios, vacunas y controles.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Programa una notificación local. Si Android 12+/14 no dio el permiso
  /// de alarmas exactas (`SCHEDULE_EXACT_ALARM`), `zonedSchedule` lanza
  /// `exact_alarms_not_permitted`; en vez de perder la alerta, se
  /// reintenta como alarma "inexacta" (puede demorarse unos minutos, pero
  /// suena). [repeatDaily] repite todos los días a la misma hora.
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required NotificationDetails details,
    String? payload,
    bool repeatDaily = false,
  }) async {
    await ensureInit();
    // Switch de Notificaciones apagado en Configuración: no se programa nada.
    if (!AppSettingsService.instance.notificationsEnabled) return;
    final scheduled = tz.TZDateTime.from(when, tz.local);

    Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
          matchDateTimeComponents: repeatDaily ? DateTimeComponents.time : null,
        );

    try {
      await go(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (e) {
      if (e.code == 'exact_alarms_not_permitted') {
        await go(AndroidScheduleMode.inexactAllowWhileIdle);
      } else {
        rethrow;
      }
    }
  }

  Future<void> cancelFor(String eventId) async {
    await ensureInit();
    await _plugin.cancel(_notifId(eventId));
  }
}
