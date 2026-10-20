import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:saluteapp/core/app_navigator.dart';
import 'package:saluteapp/core/models/sos_contact.dart';
import 'package:saluteapp/core/services/sos_alert_service.dart';
import 'package:saluteapp/core/services/sos_contact_service.dart';
import 'package:saluteapp/sos/sos_emergency_screen.dart';

enum SosPhase { idle, sending, done }

/// Estado de la emergencia en curso. Vive solo en memoria: al finalizar se
/// descarta todo (incluida la ubicación), sin historial ni seguimiento.
class SosController extends ChangeNotifier {
  SosController._();
  static final SosController instance = SosController._();

  SosPhase _phase = SosPhase.idle;
  SosAlertResult? _result;
  SosContact? _contact;
  DateTime? _activatedAt;
  bool _whatsAppAvailable = false;
  bool _screenOpen = false;

  SosPhase get phase => _phase;
  bool get isActive => _phase != SosPhase.idle;
  SosAlertResult? get result => _result;
  SosContact? get contact => _contact;
  DateTime? get activatedAt => _activatedAt;
  bool get whatsAppAvailable => _whatsAppAvailable;

  String get _senderName {
    final n = FirebaseAuth.instance.currentUser?.displayName?.trim();
    return (n != null && n.isNotEmpty) ? n : 'un usuario de Salute';
  }

  /// Activa la emergencia: abre la pantalla de emergencia al instante y
  /// dispara el envío en paralelo.
  Future<void> activate() async {
    if (isActive) {
      _openScreen();
      return;
    }
    HapticFeedback.heavyImpact();
    _phase = SosPhase.sending;
    _result = null;
    _activatedAt = DateTime.now();
    notifyListeners();
    _openScreen();
    await _run();
  }

  /// Reintenta el envío (después de un fallo o de configurar el contacto).
  Future<void> retry() async {
    if (_phase == SosPhase.sending) return;
    _phase = SosPhase.sending;
    _result = null;
    notifyListeners();
    await _run();
  }

  Future<void> _run() async {
    try {
      _contact = await SosContactService.instance.getSosContact();
      final svc = SosAlertService.instance;
      final res = await svc.sendAlert(contact: _contact, senderName: _senderName);
      _whatsAppAvailable = _contact != null && await svc.isWhatsAppAvailable();
      _result = res;
    } catch (e) {
      debugPrint('SOS: error inesperado: $e');
      _result = const SosAlertResult(
        status: SosSendStatus.failed,
        failure: SosFailure.other,
      );
    }
    _phase = SosPhase.done;
    notifyListeners();
  }

  /// Termina la emergencia y descarta todo lo asociado (ubicación incluida).
  void finish() {
    _phase = SosPhase.idle;
    _result = null;
    _contact = null;
    _activatedAt = null;
    _whatsAppAvailable = false;
    notifyListeners();
  }

  void _openScreen() {
    if (_screenOpen) return;
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    _screenOpen = true;
    nav
        .push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const SosEmergencyScreen(),
        ))
        .whenComplete(() => _screenOpen = false);
  }
}
