import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Lee los datos que el smartwatch ya sincronizó a Health Connect (Android)
/// o HealthKit (iOS). La app no habla directo con el reloj.
class HealthSyncService {
  final Health _health = Health();
  bool _configured = false;

  /// Calorías: por defecto solo ACTIVAS (lo que muestra el reloj como
  /// "kcal"). Las totales incluyen el gasto basal (el cuerpo en reposo) y dan
  /// un número bastante mayor. Poné `true` si tu reloj solo envía totales.
  static const bool usarCaloriasTotalesSiFaltanActivas = false;

  /// Avisos de la última lectura: explican por qué una métrica quedó sin
  /// datos (sin permiso, error de lectura, o Health Connect sin datos).
  List<String> avisos = [];

  /// Apps (paquetes) que escribieron en Health Connect los datos que sí
  /// llegaron (pasos / calorías). Sirve para saber qué app del reloj está
  /// sincronizando y cuál no.
  String fuentesDatos = '';

  /// true si los únicos datos que llegan los escribe el propio teléfono
  /// (conteo nativo de Android), o sea, ninguna app de reloj está enviando
  /// datos a Health Connect.
  bool soloDatosDelTelefono = false;

  /// Tipos soportados por plataforma (pedir un tipo que la plataforma no
  /// soporta lanza excepción).
  static final List<HealthDataType> types = [
    HealthDataType.HEART_RATE,
    HealthDataType.STEPS,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.WEIGHT,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    if (Platform.isAndroid) ...[
      HealthDataType.SLEEP_SESSION,
      HealthDataType.TOTAL_CALORIES_BURNED,
    ],
  ];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure(); // obligatorio en health >= 11
    _configured = true;
  }

  Future<bool> _healthConnectDisponible() async {
    if (!Platform.isAndroid) return true;
    final status = await _health.getHealthConnectSdkStatus();
    return status == HealthConnectSdkStatus.sdkAvailable;
  }

  /// Tipos que tienen permiso de lectura, chequeados de a uno. Así, si un
  /// permiso no se otorga (o no existe), el resto de las métricas igual
  /// se lee. En iOS `hasPermissions` devuelve null para lectura (no se puede
  /// saber): ahí se intenta leer igual.
  Future<List<HealthDataType>> _concedidos(List<HealthDataType> tipos) async {
    final ok = <HealthDataType>[];
    for (final t in tipos) {
      try {
        final r = await _health.hasPermissions(
          [t],
          permissions: [HealthDataAccess.READ],
        );
        if (r != false) ok.add(t);
      } catch (e) {
        debugPrint('hasPermissions($t) falló: $e');
      }
    }
    return ok;
  }

  /// Chequea permisos sin mostrar ningún diálogo (para sync silencioso).
  /// Es true si al menos una métrica tiene permiso.
  Future<bool> tienePermisos() async {
    try {
      await _ensureConfigured();
      if (!await _healthConnectDisponible()) return false;
      return (await _concedidos(types)).isNotEmpty;
    } catch (e) {
      debugPrint('Error al chequear permisos de salud: $e');
      return false;
    }
  }

  /// Solicita los permisos que falten (diálogo nativo de Health Connect /
  /// Apple Health). Es true si al menos una métrica quedó con permiso: no
  /// hace falta que se otorgue todo.
  Future<bool> solicitarPermisos() async {
    try {
      await _ensureConfigured();

      if (!await _healthConnectDisponible()) {
        // Health Connect no está instalado o hay que actualizarlo.
        await _health.installHealthConnect();
        return false;
      }

      final concedidos = await _concedidos(types);
      final faltan = types.where((t) => !concedidos.contains(t)).toList();
      if (faltan.isNotEmpty) {
        await _health.requestAuthorization(
          faltan,
          permissions: faltan.map((_) => HealthDataAccess.READ).toList(),
        );
      }
      return (await _concedidos(types)).isNotEmpty;
    } catch (e) {
      debugPrint('Error al solicitar permisos de salud: $e');
      return false;
    }
  }

  // ───────────────────────── helpers ─────────────────────────

  /// Lee un grupo de tipos; si falla devuelve lista vacía y deja un aviso
  /// (un tipo que falla no tira abajo al resto de las métricas).
  Future<List<HealthDataPoint>> _leer(
      String nombre,
      List<HealthDataType> tipos,
      DateTime desde,
      DateTime hasta,
      ) async {
    try {
      final data = await _health.getHealthDataFromTypes(
        startTime: desde,
        endTime: hasta,
        types: tipos,
      );
      final sin = _health.removeDuplicates(data);
      debugPrint('Health[$nombre]: ${sin.length} puntos');
      return sin;
    } catch (e) {
      debugPrint('Error leyendo $nombre: $e');
      avisos.add('$nombre (error al leer: $e)');
      return [];
    }
  }

  double? _valor(HealthDataPoint p) {
    final v = p.value;
    return v is NumericHealthValue ? v.numericValue.toDouble() : null;
  }

  DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _enRango(DateTime t, DateTime desde, DateTime hasta) =>
      !t.isBefore(desde) && t.isBefore(hasta);

  /// Minutos totales uniendo intervalos que se solapan (evita contar doble
  /// si dos fuentes registraron el mismo tramo).
  double _minutosUnidos(Iterable<HealthDataPoint> pts) {
    final iv = pts.map((p) => (p.dateFrom, p.dateTo)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    if (iv.isEmpty) return 0;

    double total = 0;
    var ini = iv.first.$1;
    var fin = iv.first.$2;
    for (final i in iv.skip(1)) {
      if (i.$1.isAfter(fin)) {
        total += fin.difference(ini).inSeconds / 60;
        ini = i.$1;
        fin = i.$2;
      } else if (i.$2.isAfter(fin)) {
        fin = i.$2;
      }
    }
    total += fin.difference(ini).inSeconds / 60;
    return total;
  }

  // ───────────────────────── lectura ─────────────────────────

  /// Métricas de los últimos [dias] días (incluye hoy), un mapa por día
  /// (clave = medianoche local de ese día). Los días sin ningún dato no
  /// aparecen, y las métricas sin dato vienen en `null` (no se inventa 0).
  /// Después de llamarla, [avisos] explica qué métricas quedaron sin datos y por qué.
  ///
  /// Claves: pasos, ritmoCardiaco, oxigeno, sueñoHoras, calorias, pesoKg.
  ///
  /// Criterio por día:
  /// - pasos / calorías: total del día.
  /// - frecuencia cardíaca / oxígeno: promedio del día (hoy: última lectura).
  /// - sueño: la noche que termina ese día (18:00 del día anterior → 18:00).
  /// - peso: última medición del día. Si hay mediciones de los últimos 30
  ///   días fuera de la ventana, se guardan en el día en que se midieron.
  Future<Map<DateTime, Map<String, dynamic>>> obtenerMetricasPorDia({
    int dias = 7,
  }) async {
    await _ensureConfigured();
    avisos = [];
    fuentesDatos = '';
    soloDatosDelTelefono = false;

    final ahora = DateTime.now();
    final hoy = _dia(ahora);
    final primerDia = DateTime(hoy.year, hoy.month, hoy.day - (dias - 1));

    // Solo se leen los tipos con permiso.
    final concedidos = await _concedidos(types);
    bool tiene(HealthDataType t) => concedidos.contains(t);

    final tiposSueno = [
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_REM,
      if (Platform.isAndroid) HealthDataType.SLEEP_SESSION,
    ].where(tiene).toList();

    final tiposEnergia = [
      HealthDataType.ACTIVE_ENERGY_BURNED,
      if (Platform.isAndroid && usarCaloriasTotalesSiFaltanActivas)
        HealthDataType.TOTAL_CALORIES_BURNED,
    ].where(tiene).toList();

    // Una lectura por métrica (un tipo que falla no arrastra a los demás).
    final fcPts = tiene(HealthDataType.HEART_RATE)
        ? await _leer('frecuencia cardíaca', [
      HealthDataType.HEART_RATE,
    ], primerDia, ahora)
        : <HealthDataPoint>[];

    final oxPts = tiene(HealthDataType.BLOOD_OXYGEN)
        ? await _leer('oxígeno', [
      HealthDataType.BLOOD_OXYGEN,
    ], primerDia, ahora)
        : <HealthDataPoint>[];

    final sueno = tiposSueno.isNotEmpty
        ? await _leer(
      'sueño',
      tiposSueno,
      primerDia.subtract(const Duration(hours: 6)),
      ahora,
    )
        : <HealthDataPoint>[];

    final energia = tiposEnergia.isNotEmpty
        ? await _leer('calorías activas', tiposEnergia, primerDia, ahora)
        : <HealthDataPoint>[];

    final pesos = tiene(HealthDataType.WEIGHT)
        ? await _leer('peso', [
      HealthDataType.WEIGHT,
    ], ahora.subtract(const Duration(days: 30)), ahora)
        : <HealthDataPoint>[];

    // Origen de los datos que sí llegan (qué app los escribe en Health Connect).
    final fuentes = <String>{};
    for (final p in energia) {
      fuentes.add(p.sourceName);
    }
    if (tiene(HealthDataType.STEPS)) {
      final pasosPts = await _leer('pasos (origen)', [
        HealthDataType.STEPS,
      ], ahora.subtract(const Duration(days: 2)), ahora);
      for (final p in pasosPts) {
        fuentes.add(p.sourceName);
      }
    }
    fuentes.remove('');
    bool esTelefono(String s) => s.startsWith('com.android.healthconnect.phone');
    soloDatosDelTelefono = fuentes.isNotEmpty && fuentes.every(esTelefono);
    fuentesDatos = fuentes
        .map((s) => esTelefono(s) ? 'el propio teléfono (conteo nativo de Android)' : s)
        .toSet()
        .join(', ');

    // Peso: última medición de cada día (últimos 30 días).
    final pesoPorDia = <DateTime, double>{};
    final pesosOrdenados = [...pesos]
      ..sort((a, b) => a.dateTo.compareTo(b.dateTo));
    for (final p in pesosOrdenados) {
      final v = _valor(p);
      if (v != null && v > 0) pesoPorDia[_dia(p.dateFrom)] = v;
    }

    final out = <DateTime, Map<String, dynamic>>{};

    for (var i = 0; i < dias; i++) {
      final dia = DateTime(primerDia.year, primerDia.month, primerDia.day + i);
      final finDia = DateTime(dia.year, dia.month, dia.day + 1);
      final esHoy = dia == hoy;
      final topeDia = finDia.isAfter(ahora) ? ahora : finDia;

      final m = <String, dynamic>{
        'pasos': null,
        'ritmoCardiaco': null,
        'oxigeno': null,
        'sueñoHoras': null,
        'calorias': null,
        'pesoKg': pesoPorDia[dia],
      };

      // PASOS: agregado por la plataforma (sin duplicados entre fuentes).
      if (tiene(HealthDataType.STEPS)) {
        try {
          final pasos = await _health.getTotalStepsInInterval(dia, topeDia);
          if (pasos != null && pasos > 0) m['pasos'] = pasos;
        } catch (e) {
          debugPrint('Error leyendo pasos ($dia): $e');
        }
      }

      // FRECUENCIA CARDÍACA
      final fc =
      fcPts
          .where(
            (p) =>
        p.type == HealthDataType.HEART_RATE &&
            _enRango(p.dateFrom, dia, finDia),
      )
          .toList()
        ..sort((a, b) => a.dateTo.compareTo(b.dateTo));
      final fcVals = fc
          .map(_valor)
          .whereType<double>()
          .where((v) => v > 0)
          .toList();
      if (fcVals.isNotEmpty) {
        m['ritmoCardiaco'] = esHoy
            ? fcVals.last
            : fcVals.reduce((a, b) => a + b) / fcVals.length;
      }

      // OXÍGENO (iOS lo entrega como fracción: 0.97 → 97 %)
      final ox =
      oxPts
          .where(
            (p) =>
        p.type == HealthDataType.BLOOD_OXYGEN &&
            _enRango(p.dateFrom, dia, finDia),
      )
          .toList()
        ..sort((a, b) => a.dateTo.compareTo(b.dateTo));
      final oxVals = ox
          .map(_valor)
          .whereType<double>()
          .map((v) => v <= 1 ? v * 100 : v)
          .where((v) => v > 0)
          .toList();
      if (oxVals.isNotEmpty) {
        m['oxigeno'] = esHoy
            ? oxVals.last
            : oxVals.reduce((a, b) => a + b) / oxVals.length;
      }

      // SUEÑO: la noche que termina este día. Fases > asleep > sesión
      // (nunca se suman todos juntos).
      final iniSueno = dia.subtract(const Duration(hours: 6));
      final finSueno = dia.add(const Duration(hours: 18));
      final tope = finSueno.isAfter(ahora) ? ahora : finSueno;
      final ptsSueno = sueno
          .where((p) => _enRango(p.dateFrom, iniSueno, tope))
          .toList();

      var minutos = _minutosUnidos(
        ptsSueno.where(
              (p) =>
          p.type == HealthDataType.SLEEP_LIGHT ||
              p.type == HealthDataType.SLEEP_DEEP ||
              p.type == HealthDataType.SLEEP_REM,
        ),
      );
      if (minutos == 0) {
        minutos = _minutosUnidos(
          ptsSueno.where((p) => p.type == HealthDataType.SLEEP_ASLEEP),
        );
      }
      if (minutos == 0) {
        minutos = _minutosUnidos(
          ptsSueno.where((p) => p.type == HealthDataType.SLEEP_SESSION),
        );
      }
      if (minutos > 0) m['sueñoHoras'] = minutos / 60;

      // CALORÍAS: activas del día; si no hay, totales (Android).
      double sumaEnergia(HealthDataType t) => energia
          .where((p) => p.type == t && _enRango(p.dateFrom, dia, finDia))
          .fold<double>(0, (s, p) => s + (_valor(p) ?? 0));

      var kcal = sumaEnergia(HealthDataType.ACTIVE_ENERGY_BURNED);
      if (kcal <= 0 && usarCaloriasTotalesSiFaltanActivas) {
        kcal = sumaEnergia(HealthDataType.TOTAL_CALORIES_BURNED);
      }
      if (kcal > 0) m['calorias'] = kcal;

      if (m.values.any((v) => v != null)) out[dia] = m;
    }

    // Pesos de los últimos 30 días que caen fuera de la ventana de 7 días:
    // se guardan en el día en que se midieron.
    pesoPorDia.forEach((dia, kg) {
      out.putIfAbsent(dia, () => {
        'pasos': null,
        'ritmoCardiaco': null,
        'oxigeno': null,
        'sueñoHoras': null,
        'calorias': null,
        'pesoKg': kg,
      });
    });

    // Diagnóstico: por qué una métrica quedó sin datos.
    bool hay(String k) => out.values.any((m) => m[k] != null);
    void chequeo(String nombre, String clave, bool permiso) {
      if (!permiso) {
        avisos.add('$nombre (sin permiso en Health Connect)');
      } else if (!hay(clave) && !avisos.any((a) => a.startsWith(nombre))) {
        avisos.add(
          '$nombre (Health Connect no tiene datos: la app del reloj no los está sincronizando)',
        );
      }
    }

    chequeo('pasos', 'pasos', tiene(HealthDataType.STEPS));
    chequeo(
      'frecuencia cardíaca',
      'ritmoCardiaco',
      tiene(HealthDataType.HEART_RATE),
    );
    chequeo('oxígeno', 'oxigeno', tiene(HealthDataType.BLOOD_OXYGEN));
    chequeo('sueño', 'sueñoHoras', tiposSueno.isNotEmpty);
    chequeo('calorías activas', 'calorias', tiposEnergia.isNotEmpty);

    return Map.fromEntries(
      out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// Compatibilidad: métricas de hoy (mismas claves que `obtenerMetricasPorDia`).
  Future<Map<String, dynamic>> obtenerMetricasUltimas24Horas() async {
    final porDia = await obtenerMetricasPorDia(dias: 1);
    final hoy = _dia(DateTime.now());
    return porDia[hoy] ??
        {
          'pasos': null,
          'ritmoCardiaco': null,
          'oxigeno': null,
          'sueñoHoras': null,
          'calorias': null,
          'pesoKg': null,
        };
  }
}