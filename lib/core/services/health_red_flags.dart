// ─────────────────────────────────────────────────────────────────────────────
// ALERTAS DE EMERGENCIA POR REGLAS FIJAS
//
// Estas reglas NO dependen de la IA: se evalúan en el dispositivo y se
// muestran aunque el servicio de IA falle, tarde o no esté disponible.
//
// Los umbrales son conservadores y están pensados para ADULTOS. No
// reemplazan el criterio clínico. Si el perfil es un niño, pasá [ageYears]:
// con menos de 12 años se omiten las reglas de frecuencia cardíaca y presión
// arterial, porque sus rangos normales son distintos.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class HealthRedFlags {
  /// Signos vitales sueltos (sirve para Métricas y para Triaje).
  static List<String> vitals({
    double? heartRate,
    double? temperature,
    double? oxygenSat,
    String? bloodPressure,
    int? ageYears,
  }) {
    final flags = <String>[];
    final isChild = ageYears != null && ageYears < 12;

    if (oxygenSat != null && oxygenSat > 0 && oxygenSat < 90) {
      flags.add(
        'Saturación de oxígeno muy baja (${oxygenSat.toStringAsFixed(0)} %).',
      );
    }

    if (!isChild && heartRate != null && heartRate > 0) {
      if (heartRate > 130) {
        flags.add('Frecuencia cardíaca muy alta (${heartRate.round()} BPM).');
      } else if (heartRate < 40) {
        flags.add('Frecuencia cardíaca muy baja (${heartRate.round()} BPM).');
      }
    }

    if (temperature != null && temperature > 0) {
      if (temperature >= 39.5) {
        flags.add('Fiebre muy alta (${temperature.toStringAsFixed(1)} °C).');
      } else if (temperature < 35) {
        flags.add(
          'Temperatura corporal muy baja (${temperature.toStringAsFixed(1)} °C).',
        );
      }
    }

    final bp = _parseBloodPressure(bloodPressure);
    if (!isChild && bp != null) {
      final (sys, dia) = bp;
      if (sys >= 180 || dia >= 120) {
        flags.add('Presión arterial muy elevada ($sys/$dia mmHg).');
      } else if (sys < 90) {
        flags.add('Presión arterial muy baja ($sys/$dia mmHg).');
      }
    }

    return flags;
  }

  /// Reglas del Triaje: nivel elegido, dolor, vitales y síntomas.
  ///
  /// [primaryBySystem]: sistema → síntoma principal elegido.
  /// [specifierByPrimary]: síntoma principal → especificador elegido.
  /// Los textos deben coincidir con los de la pantalla de Triaje.
  static List<String> triage({
    required int level,
    required double eva,
    double? heartRate,
    double? temperature,
    double? oxygenSat,
    String? bloodPressure,
    Map<String, String> primaryBySystem = const {},
    Map<String, String> specifierByPrimary = const {},
    int? ageYears,
  }) {
    final flags = <String>[];

    if (level == 1) {
      flags.add('Clasificaste este cuadro como Nivel 1 (Emergencia).');
    }
    if (eva >= 9) {
      flags.add('Dolor muy intenso (${eva.round()}/10).');
    }

    flags.addAll(
      vitals(
        heartRate: heartRate,
        temperature: temperature,
        oxygenSat: oxygenSat,
        bloodPressure: bloodPressure,
        ageYears: ageYears,
      ),
    );

    final chosen = primaryBySystem.values.toSet();
    String? spec(String primary) => specifierByPrimary[primary];

    if (chosen.contains('Dolor precordial')) {
      final s = spec('Dolor precordial');
      final severe =
          s == 'Opresion' ||
              s == 'Irradiado al brazo izquierdo' ||
              s == 'Irradiado a la mandibula';
      flags.add(
        severe
            ? 'Dolor en el pecho con opresión o que se irradia: puede ser una urgencia cardíaca.'
            : 'Dolor en el pecho: conviene que lo evalúe un profesional cuanto antes.',
      );
    }
    if (chosen.contains('Dificultad para respirar (Disnea)') &&
        spec('Dificultad para respirar (Disnea)') == 'En reposo') {
      flags.add('Dificultad para respirar en reposo.');
    }
    if (chosen.contains('Tos') && spec('Tos') == 'Con sangre') {
      flags.add('Tos con sangre.');
    }
    if (chosen.contains('Circulacion') &&
        spec('Circulacion') == 'Coloracion azulada') {
      flags.add('Coloración azulada en la piel.');
    }
    if (chosen.contains('Nivel de conciencia') &&
        spec('Nivel de conciencia') == 'Desorientacion') {
      flags.add('Desorientación.');
    }

    return flags;
  }

  /// "120/80" → (120, 80). `null` si no se puede interpretar.
  static (int, int)? _parseBloodPressure(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^\s*(\d{2,3})\s*[/\-]\s*(\d{2,3})\s*$').firstMatch(raw);
    if (m == null) return null;
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }
}