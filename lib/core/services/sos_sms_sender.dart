import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Resultado de intentar mandar un SMS desde el teléfono.
enum SmsOutcome {
  /// El sistema confirmó que el SMS salió del teléfono hacia la red.
  sent,

  /// Sin señal de red celular.
  noService,

  /// Modo avión / radio apagada.
  radioOff,

  /// Falló por otro motivo o el sistema no confirmó a tiempo.
  failed,

  /// Falta el permiso de envío de SMS.
  noPermission,

  /// El dispositivo/plataforma no puede enviar SMS sin intervención
  /// (iOS, tablets sin telefonía).
  unsupported,
}

/// Puente con `SosSmsChannel.kt`. Solo Android envía de verdad: iOS no
/// permite mandar un SMS sin que la persona toque "Enviar", así que ahí el
/// resultado es [SmsOutcome.unsupported] y la UI NUNCA debe decir "enviado".
class SosSmsSender {
  SosSmsSender._();
  static final SosSmsSender instance = SosSmsSender._();

  static const _channel = MethodChannel('saluteapp/sos_sms');

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get isAndroidDevice => _isAndroid;

  /// `true` si se puede enviar ya (hay telefonía y permiso).
  Future<bool> canSendNow() async => (await _capability()) == 'ok';

  Future<String> _capability() async {
    if (!_isAndroid) return 'no_telephony';
    try {
      return await _channel.invokeMethod<String>('capability') ?? 'no_telephony';
    } catch (e) {
      debugPrint('SosSmsSender.capability: $e');
      return 'no_telephony';
    }
  }

  /// Pide el permiso de SMS (diálogo del sistema). Devuelve si quedó concedido.
  Future<bool> requestPermission() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (e) {
      debugPrint('SosSmsSender.requestPermission: $e');
      return false;
    }
  }

  Future<SmsOutcome> send({required String number, required String message}) async {
    if (!_isAndroid) return SmsOutcome.unsupported;
    try {
      final raw = await _channel.invokeMethod<String>('send', {
        'number': number,
        'message': message,
      });
      switch (raw) {
        case 'sent':
          return SmsOutcome.sent;
        case 'no_service':
          return SmsOutcome.noService;
        case 'radio_off':
          return SmsOutcome.radioOff;
        case 'no_permission':
          return SmsOutcome.noPermission;
        case 'unsupported':
          return SmsOutcome.unsupported;
        default:
          return SmsOutcome.failed;
      }
    } catch (e) {
      debugPrint('SosSmsSender.send: $e');
      return SmsOutcome.failed;
    }
  }
}
