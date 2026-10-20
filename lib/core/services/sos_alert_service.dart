import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:saluteapp/core/models/sos_contact.dart';
import 'package:saluteapp/core/services/app_settings_service.dart';
import 'package:saluteapp/core/services/sos_sms_sender.dart';

/// Estado del envío de la alerta. "Enviado" SOLO si el sistema confirmó que el
/// SMS salió del teléfono. Abrir una app con el mensaje preparado NO cuenta.
enum SosSendStatus {
  /// No hay contacto de emergencia configurado: no se intentó enviar nada.
  noContact,

  /// El SMS salió del teléfono (confirmado por el sistema).
  sent,

  /// No se pudo enviar (ver [SosAlertResult.failure]).
  failed,

  /// Esta plataforma no puede enviar SMS sin que la persona toque "Enviar"
  /// (iOS). La alerta NO está enviada: hay que mandarla a mano o llamar.
  notAutomatic,
}

enum SosFailure { noService, radioOff, noPermission, invalidNumber, other }

/// Por qué no hay ubicación (o por qué no es la actual).
enum SosLocationIssue {
  /// El usuario la desactivó en Configuración de la app.
  disabledInApp,

  /// La app la permite pero el sistema negó el permiso.
  permissionDenied,

  /// El GPS / servicios de ubicación del teléfono están apagados.
  serviceOff,

  /// Hay permiso y GPS, pero no se pudo obtener una posición a tiempo.
  unavailable,
}

/// Una ubicación usada en la emergencia. NO se guarda en ningún lado: vive
/// solo en memoria durante la emergencia (sin historial ni seguimiento).
class SosLocation {
  final double latitude;
  final double longitude;
  final double accuracyMeters;

  /// `true` si es la última ubicación conocida del sistema (no una lectura
  /// nueva). Nunca debe presentarse como "actual".
  final bool isLastKnown;

  /// Antigüedad estimada (solo tiene sentido si [isLastKnown]).
  final Duration? age;

  const SosLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.isLastKnown,
    this.age,
  });

  String get mapsUrl =>
      'https://maps.google.com/?q=${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

  /// "hace 5 min", "hace 3 h", "hace 2 días".
  String get ageLabel {
    final a = age;
    if (a == null) return 'hace un tiempo';
    if (a.inMinutes < 1) return 'hace menos de 1 min';
    if (a.inMinutes < 60) return 'hace ${a.inMinutes} min';
    if (a.inHours < 24) return 'hace ${a.inHours} h';
    return 'hace ${a.inDays} ${a.inDays == 1 ? 'día' : 'días'}';
  }
}

/// Resultado de una alerta, con los tiempos medidos (la medición ya existía y
/// se conserva: sirve para verificar el objetivo de respuesta).
class SosAlertResult {
  final SosSendStatus status;
  final SosFailure? failure;
  final SosLocation? location;
  final SosLocationIssue? locationIssue;

  /// Mensaje completo que se armó (se reutiliza para WhatsApp).
  final String message;

  /// Cuánto tardó en obtenerse la ubicación (o en rendirse).
  final Duration locationTime;

  /// Tiempo total desde que se activó el SOS hasta tener el resultado del
  /// envío (confirmado o fallido).
  final Duration totalTime;

  const SosAlertResult({
    required this.status,
    this.failure,
    this.location,
    this.locationIssue,
    this.message = '',
    this.locationTime = Duration.zero,
    this.totalTime = Duration.zero,
  });

  bool get sent => status == SosSendStatus.sent;
  bool get withLocation => location != null;
}

/// Arma y manda la alerta SOS al contacto de emergencia (uno solo).
///
/// - Canal principal: SMS real (funciona sin datos, solo con señal celular).
/// - WhatsApp es adicional y manual: abrirlo nunca cuenta como "enviado".
/// - Ubicación: lectura puntual por GPS (no necesita internet); si no hay,
///   última ubicación conocida, claramente rotulada. Sin seguimiento ni
///   historial: no se guarda nada.
class SosAlertService {
  SosAlertService._();
  static final SosAlertService instance = SosAlertService._();

  /// Último resultado, útil para telemetría/depuración del objetivo de tiempo.
  SosAlertResult? lastResult;

  Future<SosAlertResult> sendAlert({
    required SosContact? contact,
    required String senderName,
  }) async {
    final total = Stopwatch()..start();

    if (contact == null || contact.phoneNumber.trim().isEmpty) {
      return _finish(
        total,
        const SosAlertResult(status: SosSendStatus.noContact),
        Duration.zero,
      );
    }

    final locWatch = Stopwatch()..start();
    final loc = await locate();
    locWatch.stop();

    final message = buildMessage(
      senderName: senderName,
      location: loc.location,
    );

    final number = dialable(contact.phoneNumber);
    if (number.isEmpty) {
      return _finish(
        total,
        SosAlertResult(
          status: SosSendStatus.failed,
          failure: SosFailure.invalidNumber,
          location: loc.location,
          locationIssue: loc.issue,
          message: message,
        ),
        locWatch.elapsed,
      );
    }

    final sms = SosSmsSender.instance;
    var outcome = SmsOutcome.failed;
    var permissionDenied = false;
    if (!await sms.canSendNow()) {
      // Primera vez: pedir el permiso de SMS; si lo niega, no se puede enviar.
      final granted = await sms.requestPermission();
      permissionDenied = !granted;
    }
    if (permissionDenied && SosSmsSender.instance.isAndroidDevice) {
      outcome = SmsOutcome.noPermission;
    } else {
      outcome = await sms.send(number: number, message: message);
      // Un reintento corto: el primer envío falla a veces justo después de
      // conceder el permiso o de reconectarse a la red móvil.
      if (outcome == SmsOutcome.failed) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        outcome = await sms.send(number: number, message: message);
      }
    }
    debugPrint('SOS: resultado SMS=${outcome.name} número=$number');

    final SosSendStatus status;
    SosFailure? failure;
    switch (outcome) {
      case SmsOutcome.sent:
        status = SosSendStatus.sent;
      case SmsOutcome.unsupported:
        status = SosSendStatus.notAutomatic;
      case SmsOutcome.noService:
        status = SosSendStatus.failed;
        failure = SosFailure.noService;
      case SmsOutcome.radioOff:
        status = SosSendStatus.failed;
        failure = SosFailure.radioOff;
      case SmsOutcome.noPermission:
        status = SosSendStatus.failed;
        failure = SosFailure.noPermission;
      case SmsOutcome.failed:
        status = SosSendStatus.failed;
        failure = SosFailure.other;
    }

    return _finish(
      total,
      SosAlertResult(
        status: status,
        failure: failure,
        location: loc.location,
        locationIssue: loc.issue,
        message: message,
      ),
      locWatch.elapsed,
    );
  }

  SosAlertResult _finish(Stopwatch total, SosAlertResult r, Duration locTime) {
    total.stop();
    final result = SosAlertResult(
      status: r.status,
      failure: r.failure,
      location: r.location,
      locationIssue: r.locationIssue,
      message: r.message,
      locationTime: locTime,
      totalTime: total.elapsed,
    );
    lastResult = result;
    debugPrint(
      'SOS: total=${result.totalTime.inMilliseconds} ms '
      '(ubicación=${result.locationTime.inMilliseconds} ms, '
      'conUbicación=${result.withLocation}, '
      'ultimaConocida=${result.location?.isLastKnown}, estado=${result.status.name})',
    );
    return result;
  }

  // ---------------------------------------------------------------- mensaje

  @visibleForTesting
  static String buildMessage({required String senderName, SosLocation? location}) {
    final buf = StringBuffer('ALERTA SOS de $senderName (app Salute). Necesito ayuda.');
    if (location == null) {
      buf.write('\nNo pude obtener mi ubicacion: llamame lo antes posible.');
    } else if (location.isLastKnown) {
      buf.write(
        '\nOJO: esta es mi ULTIMA ubicacion conocida (${location.ageLabel}), '
        'puede que ya no este ahi: ${location.mapsUrl}',
      );
    } else {
      buf.write('\nMi ubicacion actual: ${location.mapsUrl}');
      if (location.accuracyMeters > 0) {
        buf.write(' (precision aprox. ${location.accuracyMeters.round()} m)');
      }
    }
    return buf.toString();
  }

  // -------------------------------------------------------------- ubicación

  /// Intenta devolver una posición rápido y sin internet (GPS puro). Respeta
  /// la preferencia de la app. Nunca bloquea la alerta más de ~5 s.
  Future<({SosLocation? location, SosLocationIssue? issue})> locate() async {
    if (!AppSettingsService.instance.locationEnabled) {
      return (location: null, issue: SosLocationIssue.disabledInApp);
    }
    try {
      // OJO: no se pide el permiso acá (el diálogo demoraría la emergencia);
      // se pide al configurar el SOS y al activar la ubicación en Configuración.
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (location: null, issue: SosLocationIssue.permissionDenied);
      }
      final serviceOn = await Geolocator.isLocationServiceEnabled();

      Position? last;
      try {
        last = await Geolocator.getLastKnownPosition();
      } catch (_) {
        last = null; // no soportado en todas las plataformas
      }

      Position? fresh;
      if (serviceOn) {
        final future = Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        ).then<Position?>((p) => p, onError: (_) => null);
        final wait = last != null ? const Duration(milliseconds: 1500) : const Duration(seconds: 5);
        fresh = await future.timeout(wait, onTimeout: () => null);
      }

      if (fresh != null) {
        return (
          location: SosLocation(
            latitude: fresh.latitude,
            longitude: fresh.longitude,
            accuracyMeters: fresh.accuracy,
            isLastKnown: false,
          ),
          issue: null,
        );
      }
      if (last != null) {
        return (
          location: SosLocation(
            latitude: last.latitude,
            longitude: last.longitude,
            accuracyMeters: last.accuracy,
            isLastKnown: true,
            age: DateTime.now().difference(last.timestamp),
          ),
          issue: serviceOn ? null : SosLocationIssue.serviceOff,
        );
      }
      return (
        location: null,
        issue: serviceOn ? SosLocationIssue.unavailable : SosLocationIssue.serviceOff,
      );
    } catch (e) {
      debugPrint('SOS: error obteniendo ubicación: $e');
      return (location: null, issue: SosLocationIssue.unavailable);
    }
  }

  // --------------------------------------------------------------- WhatsApp

  /// `true` si hay WhatsApp (o WhatsApp Business) instalado.
  Future<bool> isWhatsAppAvailable() async {
    try {
      return await canLaunchUrl(Uri.parse('whatsapp://send'));
    } catch (_) {
      return false;
    }
  }

  /// Abre WhatsApp con el mensaje listo. Devuelve si pudo abrirlo; eso NO
  /// significa que el mensaje se haya enviado (la persona tiene que tocar
  /// "Enviar"), por eso nunca se usa para marcar la alerta como enviada.
  Future<bool> openWhatsApp({required SosContact contact, required String message}) async {
    final number = whatsAppNumber(contact.phoneNumber);
    if (number.isEmpty) return false;
    try {
      return await launchUrl(
        Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(message)}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('SOS: no se pudo abrir WhatsApp: $e');
      return false;
    }
  }

  static String dialable(String raw) {
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return trimmed.startsWith('+') ? '+$digits' : digits;
  }

  /// WhatsApp exige el número en formato internacional, solo dígitos.
  /// Si viene sin código de país asumimos Argentina (móvil: 54 9 + 10 dígitos).
  @visibleForTesting
  static String whatsAppNumber(String raw) {
    final trimmed = raw.trim();
    var digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    if (trimmed.startsWith('+')) return digits;
    if (digits.startsWith('00')) return digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.startsWith('54')) return digits;
    if (digits.length == 10) return '549$digits';
    return digits;
  }
}
