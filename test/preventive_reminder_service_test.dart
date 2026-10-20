import 'package:flutter_test/flutter_test.dart';
import 'package:saluteapp/core/services/preventive_reminder_service.dart';

void main() {
  group('upcomingReminderTime', () {
    test('avisa 3 días antes a las 9:00', () {
      final now = DateTime(2026, 10, 18, 12);
      final t = PreventiveReminderService.upcomingReminderTime(DateTime(2026, 10, 28), now);
      expect(t, DateTime(2026, 10, 25, 9));
    });
    test('si faltan menos de 3 días, avisa el mismo día a las 9:00', () {
      final now = DateTime(2026, 10, 18, 12);
      final t = PreventiveReminderService.upcomingReminderTime(DateTime(2026, 10, 20), now);
      expect(t, DateTime(2026, 10, 20, 9));
    });
    test('si ya pasó la hora del día, no programa nada', () {
      final now = DateTime(2026, 10, 20, 10);
      expect(PreventiveReminderService.upcomingReminderTime(DateTime(2026, 10, 20), now), isNull);
    });
  });

  group('nextMonday', () {
    test('desde un domingo (18/10/2026) da el lunes 19 a las 10:00', () {
      expect(PreventiveReminderService.nextMonday(DateTime(2026, 10, 18, 15)), DateTime(2026, 10, 19, 10));
    });
    test('un lunes antes de las 10 es el mismo día; después, el siguiente lunes', () {
      expect(PreventiveReminderService.nextMonday(DateTime(2026, 10, 19, 8)), DateTime(2026, 10, 19, 10));
      expect(PreventiveReminderService.nextMonday(DateTime(2026, 10, 19, 11)), DateTime(2026, 10, 26, 10));
    });
  });

  group('nextMonthly', () {
    test('primer lunes de noviembre 2026 es el 2', () {
      expect(PreventiveReminderService.nextMonthly(DateTime(2026, 10, 18)), DateTime(2026, 11, 2, 10));
    });
    test('pasa de diciembre a enero', () {
      expect(PreventiveReminderService.nextMonthly(DateTime(2026, 12, 20)), DateTime(2027, 1, 4, 10));
    });
  });

  group('checkupReminderTime', () {
    final now = DateTime(2026, 10, 18, 12);
    test('sin control cargado: recordatorio mensual', () {
      expect(PreventiveReminderService.checkupReminderTime(null, now), DateTime(2026, 11, 2, 10));
    });
    test('control vencido: recordatorio mensual', () {
      expect(PreventiveReminderService.checkupReminderTime(DateTime(2026, 1, 1), now), DateTime(2026, 11, 2, 10));
    });
    test('control que se cumple en pocos días: avisa ese día a las 10:00', () {
      final last = DateTime(2026, 10, 18).subtract(const Duration(days: 170));
      final t = PreventiveReminderService.checkupReminderTime(last, now)!;
      expect(t.difference(DateTime(2026, 10, 28, 10)).inDays, 0);
    });
    test('control reciente: no avisa todavía', () {
      expect(PreventiveReminderService.checkupReminderTime(DateTime(2026, 9, 1), now), isNull);
    });
  });
}
