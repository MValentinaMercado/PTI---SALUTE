import 'package:flutter_test/flutter_test.dart';
import 'package:saluteapp/core/services/sos_alert_service.dart';

void main() {
  group('whatsAppNumber', () {
    test('respeta números internacionales', () {
      expect(SosAlertService.whatsAppNumber('+54 9 351 123-4567'), '5493511234567');
    });
    test('agrega 549 a móviles argentinos de 10 dígitos', () {
      expect(SosAlertService.whatsAppNumber('351 123 4567'), '5493511234567');
      expect(SosAlertService.whatsAppNumber('0351 123 4567'), '5493511234567');
    });
    test('convierte prefijo 00', () {
      expect(SosAlertService.whatsAppNumber('0034 600 123 456'), '34600123456');
    });
    test('vacío si no hay dígitos', () {
      expect(SosAlertService.whatsAppNumber('abc'), '');
    });
  });

  test('mensaje sin ubicación pide que lo llamen', () {
    final msg = SosAlertService.buildMessage(senderName: 'Ana');
    expect(msg, contains('ALERTA SOS de Ana'));
    expect(msg, contains('No pude obtener mi ubicación'));
  });
}
