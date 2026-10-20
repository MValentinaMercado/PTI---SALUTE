import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:saluteapp/components/design_system.dart';
import 'package:saluteapp/components/design_patterns.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/vital_entry.dart';
import 'package:saluteapp/core/services/health_service.dart';
import 'package:saluteapp/core/services/vitals_service.dart';
import 'package:saluteapp/components/ai_insight_card.dart';
import 'package:saluteapp/core/services/ai_insight_service.dart';
import 'package:saluteapp/core/services/health_red_flags.dart';

String _timeSince(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'Hace ${diff.inHours} h';
  return 'Hace ${diff.inDays} día(s)';
}

/// Combina los registros (más reciente primero) tomando, para cada métrica,
/// el último valor NO nulo. Así un registro del reloj sin peso/estrés no
/// "borra" el peso o estrés cargado a mano antes.
VitalEntry? mergeLatestVitalEntries(List<VitalEntry> entries) {
  if (entries.isEmpty) return null;

  T? pick<T>(T? Function(VitalEntry) f) {
    for (final e in entries) {
      final v = f(e);
      if (v != null) return v;
    }
    return null;
  }

  final first = entries.first;
  return VitalEntry(
    id: first.id,
    ownerUid: first.ownerUid,
    profileId: first.profileId,
    date: first.date,
    heartRate: pick<int>((e) => e.heartRate),
    bloodOxygen: pick<double>((e) => e.bloodOxygen),
    sleepHours: pick<double>((e) => e.sleepHours),
    weightKg: pick<double>((e) => e.weightKg),
    steps: pick<int>((e) => e.steps),
    calories: pick<int>((e) => e.calories),
    stressLevel: pick<StressLevel>((e) => e.stressLevel),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// DATOS PARA LA ORIENTACIÓN DE IA
// ─────────────────────────────────────────────────────────────────────────────

int _aiMetricCount(VitalEntry? e) => e == null
    ? 0
    : [
  e.heartRate,
  e.bloodOxygen,
  e.sleepHours,
  e.weightKg,
  e.steps,
  e.calories,
  e.stressLevel,
].where((v) => v != null).length;

/// Con al menos 2 métricas cargadas ya hay algo que analizar.
bool _aiReady(VitalEntry? latest) => _aiMetricCount(latest) >= 2;

Map<String, dynamic> _buildAiData(
    List<VitalEntry> entries,
    VitalEntry? latest,
    ) {
  return AiPayload.clean({
    'objetivo': 'Interpretar tendencias y relaciones entre las métricas. '
        'No repetir un estado fijo ni emitir diagnósticos.',
    'ultimoValor': {
      'frecuenciaCardiacaBpm': latest?.heartRate,
      'oxigenoPct': latest?.bloodOxygen,
      'suenoHoras': latest?.sleepHours,
      'pesoKg': latest?.weightKg,
      'pasos': latest?.steps,
      'caloriasActivas': latest?.calories,
      'estres': latest?.stressLevel?.name,
    },
    'ultimos7Dias_masViejoPrimero': {
      'frecuenciaCardiacaBpm': _series(entries, (e) => e.heartRate?.toDouble()),
      'oxigenoPct': _series(entries, (e) => e.bloodOxygen),
      'suenoHoras': _series(entries, (e) => e.sleepHours),
      'pesoKg': _series(entries, (e) => e.weightKg),
      'pasos': _series(entries, (e) => e.steps?.toDouble()),
      'caloriasActivas': _series(entries, (e) => e.calories?.toDouble()),
      'estres': _stressSeries(entries),
    },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

/// Los registros pueden venir de dos lados: cargados a mano (`VitalEntry`,
/// ver core/models/vital_entry.dart) o sincronizados desde el smartwatch vía
/// Health Connect (Android) / HealthKit (iOS). La app no habla directo con
/// el reloj: lee lo que la app del reloj ya escribió en Health Connect/HealthKit.
class BiometricsScreen extends StatefulWidget {
  final String profileId;
  final String profileName;
  final VoidCallback? onBackToDashboard;

  const BiometricsScreen({
    super.key,
    required this.profileId,
    required this.profileName,
    this.onBackToDashboard,
  });

  @override
  State<BiometricsScreen> createState() => _BiometricsScreenState();
}

class _BiometricsScreenState extends State<BiometricsScreen> {
  final HealthSyncService _healthService = HealthSyncService();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    // Sync automático y silencioso al abrir la pantalla (solo si ya hay permisos).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWearable(silent: true);
    });
  }

  /// Guarda UN registro por día del reloj (id fijo por día) con merge: no se
  /// duplican documentos, re-sincronizar actualiza el mismo día y no se pisan
  /// los datos cargados a mano. Es lo que alimenta la tendencia de 7 días.
  Future<void> _guardarRegistrosReloj(Map<DateTime, VitalEntry> porDia) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Sesión no iniciada');

    String two(int n) => n.toString().padLeft(2, '0');
    final col = FirebaseFirestore.instance.collection('vitals');
    final batch = FirebaseFirestore.instance.batch();

    porDia.forEach((dia, entry) {
      final id =
          '${widget.profileId}_${dia.year}${two(dia.month)}${two(dia.day)}_watch';
      final data = entry.toFirestore()..['uid'] = uid;
      // Si ya no hay calorías activas, se borra el valor viejo del día
      // (antes podía haberse guardado un total que incluía el gasto basal).
      if (entry.calories == null) data['calories'] = FieldValue.delete();
      batch.set(col.doc(id), data, SetOptions(merge: true));
    });

    await batch.commit();
  }

  void _snack(
      String msg,
      Color color, {
        Duration duration = const Duration(seconds: 4),
      }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: duration),
    );
  }

  Future<void> _syncWearable({bool silent = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      if (silent) {
        if (!await _healthService.tienePermisos()) return;
      } else {
        final authorized = await _healthService.solicitarPermisos();
        if (!authorized) {
          _snack(
            'No se otorgó ningún permiso de salud (o falta instalar Health Connect).',
            SaluteColors.danger,
          );
          return;
        }
      }

      // Últimos 7 días del reloj: se guarda un registro por día, así la
      // tendencia se completa aunque no hayas abierto la app esos días.
      final porDia = await _healthService.obtenerMetricasPorDia(dias: 7);

      final now = DateTime.now();
      final registros = <DateTime, VitalEntry>{};
      final received = <String>{};

      porDia.forEach((dia, m) {
        final steps = (m['pasos'] as num?)?.toInt();
        final heartRate = (m['ritmoCardiaco'] as num?)?.round();
        final oxygen = (m['oxigeno'] as num?)?.toDouble();
        final sleepHours = (m['sueñoHoras'] as num?)?.toDouble();
        final calories = (m['calorias'] as num?)?.round();
        final weight = (m['pesoKg'] as num?)?.toDouble();

        if (steps != null) received.add('pasos');
        if (heartRate != null) received.add('frecuencia cardíaca');
        if (oxygen != null) received.add('oxígeno');
        if (sleepHours != null) received.add('sueño');
        if (calories != null) received.add('calorías');
        if (weight != null) received.add('peso');

        final esHoy =
            dia.year == now.year && dia.month == now.month && dia.day == now.day;

        registros[dia] = VitalEntry(
          id: '',
          ownerUid: '',
          profileId: widget.profileId,
          // Hoy: ahora. Días anteriores: mediodía de ese día (para que caiga
          // en el día correcto en la tendencia).
          date: esHoy ? now : DateTime(dia.year, dia.month, dia.day, 12),
          heartRate: heartRate,
          bloodOxygen: oxygen,
          steps: steps,
          calories: calories,
          sleepHours: sleepHours,
          weightKg: weight,
        );
      });

      if (registros.isEmpty) {
        if (!silent) {
          final detalle = _healthService.avisos.isEmpty
              ? ''
              : '\n${_healthService.avisos.join('\n')}';
          _snack(
            'El reloj no devolvió datos. Revisá que su app (Samsung Health, '
                'Garmin, Fitbit, etc.) esté sincronizando con Health Connect.$detalle',
            SaluteColors.brownOrange,
            duration: const Duration(seconds: 10),
          );
        }
        return;
      }

      await _guardarRegistrosReloj(registros);

      if (!silent) {
        final avisos = _healthService.avisos;
        if (avisos.isEmpty) {
          _snack(
            'Health Connect sincronizado: ${received.join(', ')}.',
            SaluteColors.primaryGreen,
          );
        } else {
          final origen = _healthService.fuentesDatos;
          final avisoTelefono = _healthService.soloDatosDelTelefono
              ? 'Tu reloj no está enviando datos a Health Connect: lo que '
              'llega es del propio teléfono, no del reloj.\n\n'
              : '';
          _snack(
            '${avisoTelefono}Sincronizado: ${received.join(', ')}.\n'
                'Sin datos de:\n${avisos.map((a) => '• $a').join('\n')}'
                '${origen.isEmpty ? '' : '\nLos datos que sí llegan vienen de: $origen'}',
            SaluteColors.brownOrange,
            duration: const Duration(seconds: 12),
          );
        }
      }
    } catch (error) {
      if (!silent) {
        _snack('No se pudo sincronizar el smartwatch: $error',
            SaluteColors.danger);
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openAddSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddVitalsSheet(profileId: widget.profileId),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Registro guardado.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        backgroundColor: SaluteColors.primaryGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'REGISTRAR',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            DsScreenHeader(
              title: 'Métricas',
              subtitle: widget.profileName,
              onBack: widget.onBackToDashboard,
            ),
            Expanded(
              child: StreamBuilder<List<VitalEntry>>(
                stream: VitalsService.instance.watchForProfile(
                  widget.profileId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: SaluteColors.primaryGreen,
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'No se pudieron cargar las métricas.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final entries = snapshot.data ?? [];
                  // Último valor disponible de cada métrica (manual o reloj).
                  final latest = mergeLatestVitalEntries(entries);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      DsSpacing.lg,
                      DsSpacing.lg,
                      DsSpacing.lg,
                      DsSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LinkWearableButton(
                          syncing: _syncing,
                          onPressed: _syncWearable,
                        ),
                        const SizedBox(height: DsSpacing.lg),
                        HealthStatusCard(latest: latest),
                        const SizedBox(height: DsSpacing.xxl),
                        _HealthMetricsGrid(entries: entries, latest: latest),
                        const SizedBox(height: DsSpacing.xxl),
                        _WearablesSection(entries: entries, latest: latest),
                        const SizedBox(height: DsSpacing.xl),
                        _StressCard(latest: latest),
                        const SizedBox(height: DsSpacing.xl),
                        AiInsightCard(
                          key: ValueKey('ai-metricas-${widget.profileId}'),
                          kind: 'metricas',
                          profileId: widget.profileId,
                          subject: const {
                            'tipo': 'persona',
                            'enfoque': 'tendencias_y_contexto',
                          },
                          buildData: () => _buildAiData(entries, latest),
                          redFlags: HealthRedFlags.vitals(
                            heartRate: latest?.heartRate?.toDouble(),
                            oxygenSat: latest?.bloodOxygen,
                          ),
                          ready: _aiReady(latest),
                          notReadyHint:
                          'Registrá o sincronizá al menos dos métricas para poder analizar.',
                        ),
                        const SizedBox(height: DsSpacing.xxl),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS HERO
// ─────────────────────────────────────────────────────────────────────────────

enum _HealthStatus { optima, atencion, sinDatos }

class _HealthEvaluation {
  final _HealthStatus status;
  final int available;
  final List<String> concerns;

  const _HealthEvaluation({
    required this.status,
    required this.available,
    required this.concerns,
  });
}

_HealthEvaluation _evaluateHealth(VitalEntry? e) {
  if (e == null) {
    return const _HealthEvaluation(
      status: _HealthStatus.sinDatos,
      available: 0,
      concerns: [],
    );
  }

  final concerns = <String>[];
  var available = 0;

  if (e.heartRate != null) {
    available++;
    if (e.heartRate! < 55 || e.heartRate! > 100) {
      concerns.add('frecuencia cardíaca fuera del rango de referencia');
    }
  }
  if (e.bloodOxygen != null) {
    available++;
    if (e.bloodOxygen! < 95) {
      concerns.add('saturación de oxígeno menor al valor esperado');
    }
  }
  if (e.sleepHours != null) {
    available++;
    if (e.sleepHours! < 6 || e.sleepHours! > 12) {
      concerns.add('horas de sueño fuera del rango orientativo');
    }
  }
  if (e.weightKg != null) {
    available++;
    if (e.weightKg! <= 0) {
      concerns.add('peso inválido');
    }
  }
  if (e.steps != null) available++;
  if (e.calories != null) available++;
  if (e.stressLevel != null) {
    available++;
    if (e.stressLevel == StressLevel.alto) {
      concerns.add('nivel de estrés alto');
    }
  }

  return _HealthEvaluation(
    status: concerns.isEmpty ? _HealthStatus.optima : _HealthStatus.atencion,
    available: available,
    concerns: concerns,
  );
}

class HealthStatusCard extends StatelessWidget {
  final VitalEntry? latest;
  final VoidCallback? onTap;

  const HealthStatusCard({super.key, required this.latest, this.onTap});

  @override
  Widget build(BuildContext context) {
    final evaluation = _evaluateHealth(latest);
    final status = evaluation.status;
    final String headline = switch (status) {
      _HealthStatus.optima => 'Salud General:\nÓptima',
      _HealthStatus.atencion => 'Salud General:\nRequiere atención',
      _HealthStatus.sinDatos => 'Salud General:\nSin datos',
    };
    final String subtitle = switch (status) {
      _HealthStatus.optima => 'Tus últimos registros están en rangos normales.',
      _HealthStatus.atencion =>
      '${evaluation.concerns.join(', ')}. Revisalo con calma.',
      _HealthStatus.sinDatos =>
      'Todavía no hay datos. Tocá "Vincular wearable" o "Registrar" para empezar.',
    };
    final coverage = status == _HealthStatus.sinDatos
        ? ''
        : ' ${evaluation.available} de 7 métricas disponibles fueron revisadas.';

    final card = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220),
      decoration: BoxDecoration(
        color: SaluteColors.darkGreen,
        borderRadius: BorderRadius.circular(DsBorderRadius.full),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -10,
            child: Icon(
              Icons.eco,
              size: 220,
              color: SaluteColors.primaryGreen.withValues(alpha: 0.18),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(DsSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _StatusBadge(),
                const SizedBox(height: DsSpacing.lg),
                Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: DsFontSize.display,
                    fontWeight: DsFontWeight.w900,
                    height: DsLineHeight.tight,
                  ),
                ),
                const SizedBox(height: DsSpacing.lg),
                Text(
                  '$subtitle$coverage',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: DsFontSize.md,
                    height: DsLineHeight.normal,
                  ),
                ),
                const SizedBox(height: DsSpacing.lg),
                _SyncFooter(latest: latest),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: 'Ver métricas de salud general',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsBorderRadius.full),
        child: card,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.lg,
        vertical: DsSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: SaluteColors.primaryGreen.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(DsBorderRadius.lg),
        border: Border.all(
          color: SaluteColors.primaryGreen.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: const Text(
        'ESTADO ACTUAL',
        style: TextStyle(
          color: Colors.white,
          fontSize: DsFontSize.xs,
          fontWeight: DsFontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _SyncFooter extends StatelessWidget {
  final VitalEntry? latest;
  const _SyncFooter({required this.latest});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _IconBubble(icon: Icons.watch_outlined),
        const SizedBox(width: DsSpacing.lg),
        Flexible(
          child: Text(
            latest == null
                ? 'SIN REGISTROS TODAVÍA'
                : 'ÚLTIMO REGISTRO: ${_timeSince(latest!.date).toUpperCase()}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: DsFontSize.xs,
              fontWeight: DsFontWeight.w700,
              letterSpacing: 0.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;

  const _IconBubble({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: SaluteColors.primaryGreen.withValues(alpha: 0.35),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 16),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEALTH METRICS GRID (con mini historial de últimos registros)
// ─────────────────────────────────────────────────────────────────────────────

/// Últimos 7 días calendario, el más viejo primero (el último es hoy).
List<DateTime> _last7Days() {
  final now = DateTime.now();
  return List.generate(
    7,
        (i) => DateTime(now.year, now.month, now.day - (6 - i)),
  );
}

/// Tendencia de 7 días: un valor por día (el del registro más reciente de
/// ese día). Los días sin dato quedan en `null` — no se inventa un valor.
List<double?> _series(
    List<VitalEntry> entries, // más reciente primero
    double? Function(VitalEntry) f,
    ) {
  final porDia = <DateTime, double>{};
  for (final e in entries) {
    final v = f(e);
    if (v == null) continue;
    final d = DateTime(e.date.year, e.date.month, e.date.day);
    porDia.putIfAbsent(d, () => v); // el primero es el más reciente
  }
  return _last7Days().map((d) => porDia[d]).toList();
}

List<String?> _stressSeries(List<VitalEntry> entries) {
  final porDia = <DateTime, String>{};
  for (final e in entries) {
    final stress = e.stressLevel;
    if (stress == null) continue;
    final d = DateTime(e.date.year, e.date.month, e.date.day);
    porDia.putIfAbsent(d, () => stress.name);
  }
  return _last7Days().map((d) => porDia[d]).toList();
}

class _HealthMetricsGrid extends StatelessWidget {
  final List<VitalEntry> entries; // más reciente primero
  final VitalEntry? latest; // último valor no nulo de cada métrica
  const _HealthMetricsGrid({required this.entries, required this.latest});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HealthMetricCard(
          icon: Icons.favorite_border,
          title: 'FRECUENCIA CARDÍACA',
          value: latest?.heartRate?.toString() ?? '—',
          unit: 'BPM',
          iconColor: SaluteColors.brownOrange,
          bgColor: SaluteColors.lightBrown,
          sparkValues: _series(entries, (e) => e.heartRate?.toDouble()),
        ),
        const SizedBox(height: DsSpacing.lg),
        _HealthMetricCard(
          icon: Icons.nights_stay_outlined,
          title: 'SUEÑO',
          value: latest?.sleepHours?.toStringAsFixed(1) ?? '—',
          unit: 'HRS',
          iconColor: SaluteColors.darkGreen,
          bgColor: SaluteColors.lightGreen,
          sparkValues: _series(entries, (e) => e.sleepHours),
        ),
        const SizedBox(height: DsSpacing.lg),
        _HealthMetricCard(
          icon: Icons.air_outlined,
          title: 'OXÍGENO EN SANGRE',
          value: latest?.bloodOxygen?.toStringAsFixed(1) ?? '—',
          unit: '%',
          iconColor: SaluteColors.primaryGreen,
          bgColor: SaluteColors.lightGreen,
          sparkValues: _series(entries, (e) => e.bloodOxygen),
        ),
        const SizedBox(height: DsSpacing.lg),
        _HealthMetricCard(
          icon: Icons.monitor_weight_outlined,
          title: 'PESO',
          value: latest?.weightKg?.toStringAsFixed(1) ?? '—',
          unit: 'KG',
          iconColor: SaluteColors.primaryGreen,
          bgColor: SaluteColors.lightGreen,
          sparkValues: _series(entries, (e) => e.weightKg),
        ),
      ],
    );
  }
}

class _HealthMetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final Color iconColor;
  final Color bgColor;
  final List<double?> sparkValues;

  const _HealthMetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    required this.iconColor,
    required this.bgColor,
    required this.sparkValues,
  });

  @override
  Widget build(BuildContext context) {
    final withData = sparkValues.whereType<double>().toList();

    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DsIconContainer(
                icon: icon,
                iconColor: iconColor,
                backgroundColor: bgColor.withValues(alpha: 0.3),
                size: 44,
              ),
              const SizedBox(width: DsSpacing.lg),
              Text(title, style: DsTextStyles.labelSmall),
              const Spacer(),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: const TextStyle(
                        fontSize: DsFontSize.xxl,
                        fontWeight: DsFontWeight.w900,
                        color: Colors.black87,
                      ),
                    ),
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                        fontSize: DsFontSize.md,
                        fontWeight: DsFontWeight.w600,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpacing.xl),
          if (withData.length < 2)
            Container(
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: SaluteColors.bgColor,
                borderRadius: BorderRadius.circular(DsBorderRadius.md),
              ),
              child: Center(
                child: Text(
                  withData.isEmpty
                      ? 'Sin registros en los últimos 7 días'
                      : 'Se necesitan al menos 2 días con datos',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: DsFontSize.xs,
                    fontWeight: DsFontWeight.w600,
                  ),
                ),
              ),
            )
          else
            _MiniSparkline(values: sparkValues, color: iconColor),
        ],
      ),
    );
  }
}

/// Barras de los últimos 7 días (uno por día, hoy a la derecha). Los días
/// sin registro quedan como hueco gris. Debajo, la inicial de cada día.
class _MiniSparkline extends StatelessWidget {
  final List<double?> values; // 7 valores, del más viejo al más nuevo
  final Color color;
  const _MiniSparkline({required this.values, required this.color});

  static const _initials = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final withData = values.whereType<double>().toList();
    final maxV = withData.reduce((a, b) => a > b ? a : b);
    final minV = withData.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);
    final days = _last7Days();

    return Column(
      children: [
        SizedBox(
          height: 60,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: values.map((v) {
              final heightFactor = v == null
                  ? 0.08
                  : 0.15 + 0.85 * ((v - minV) / range);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    height: 60 * heightFactor,
                    decoration: BoxDecoration(
                      color: v == null
                          ? Colors.grey.shade200
                          : color.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: days.map((d) {
            final isToday = d == days.last;
            return Expanded(
              child: Center(
                child: Text(
                  _initials[d.weekday - 1],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    color: isToday ? Colors.black87 : Colors.grey.shade500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVIDAD (pasos / calorías)
// ─────────────────────────────────────────────────────────────────────────────

class _WearablesSection extends StatelessWidget {
  final List<VitalEntry> entries; // más reciente primero
  final VitalEntry? latest;
  const _WearablesSection({required this.entries, required this.latest});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DsSectionHeader(title: 'Actividad'),
        const SizedBox(height: DsSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.directions_walk_outlined,
                label: 'PASOS (ÚLTIMO REGISTRO)',
                value: latest?.steps?.toString() ?? '—',
                unit: '',
                sparkValues: _series(entries, (e) => e.steps?.toDouble()),
              ),
            ),
            const SizedBox(width: DsSpacing.lg),
            Expanded(
              child: _MetricCard(
                icon: Icons.local_fire_department_outlined,
                label: 'CALORÍAS (ÚLTIMO REGISTRO)',
                value: latest?.calories?.toString() ?? '—',
                unit: 'kcal',
                sparkValues: _series(entries, (e) => e.calories?.toDouble()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final List<double?> sparkValues; // 7 días

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.sparkValues,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrend = sparkValues.whereType<double>().length >= 2;

    return DsCard(
      padding: const EdgeInsets.all(DsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DsIconContainer(
                icon: icon,
                iconColor: SaluteColors.primaryGreen,
                backgroundColor: SaluteColors.lightGreen,
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: DsSpacing.lg),
          Text(label, style: DsTextStyles.labelSmall, maxLines: 2),
          const SizedBox(height: DsSpacing.sm),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: DsFontSize.display,
                    fontWeight: DsFontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      fontSize: DsFontSize.lg,
                      fontWeight: DsFontWeight.w500,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: DsSpacing.lg),
          if (hasTrend)
            _MiniSparkline(
              values: sparkValues,
              color: SaluteColors.primaryGreen,
            )
          else
            Text(
              'Tendencia: faltan días con datos',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: DsFontSize.xs,
                fontWeight: DsFontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STRESS LEVEL CARD
// (el estrés no existe en Health Connect/HealthKit: se carga a mano)
// ─────────────────────────────────────────────────────────────────────────────

class _StressCard extends StatelessWidget {
  final VitalEntry? latest;
  const _StressCard({required this.latest});

  static const _labels = {
    StressLevel.bajo: 'Bajo',
    StressLevel.medio: 'Medio',
    StressLevel.alto: 'Alto',
  };
  static const _segments = {
    StressLevel.bajo: 1,
    StressLevel.medio: 2,
    StressLevel.alto: 4,
  };
  static const _badgeColors = {
    StressLevel.bajo: SaluteColors.primaryGreen,
    StressLevel.medio: SaluteColors.brownOrange,
    StressLevel.alto: SaluteColors.terracotta,
  };

  @override
  Widget build(BuildContext context) {
    final level = latest?.stressLevel;

    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              DsIconContainer(
                icon: Icons.psychology_outlined,
                iconColor: SaluteColors.primaryGreen,
                backgroundColor: SaluteColors.lightGreen,
              ),
            ],
          ),
          const SizedBox(height: DsSpacing.lg),
          Text('NIVEL DE ESTRÉS', style: DsTextStyles.labelSmall),
          const SizedBox(height: DsSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                level != null ? _labels[level]! : 'Sin datos',
                style: const TextStyle(
                  fontSize: DsFontSize.display,
                  fontWeight: DsFontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              if (level != null) ...[
                const SizedBox(width: DsSpacing.lg),
                DsBadge(
                  label: level == StressLevel.bajo
                      ? 'Ideal'
                      : (level == StressLevel.medio ? 'Atención' : 'Alto'),
                  backgroundColor: _badgeColors[level]!.withValues(alpha: 0.15),
                  labelColor: _badgeColors[level]!,
                ),
              ],
            ],
          ),
          const SizedBox(height: DsSpacing.lg),
          DsSegmentedBar(
            activeSegments: level != null ? _segments[level]! : 0,
            totalSegments: 4,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LINK WEARABLE BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _LinkWearableButton extends StatelessWidget {
  final bool syncing;
  final VoidCallback onPressed;

  const _LinkWearableButton({required this.syncing, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DsButtonPrimary(
      label: syncing ? 'SINCRONIZANDO...' : 'SINCRONIZAR SMARTWATCH',
      icon: syncing ? Icons.sync : Icons.watch_outlined,
      onPressed: syncing ? () {} : onPressed,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORMULARIO DE CARGA MANUAL
// ─────────────────────────────────────────────────────────────────────────────

class _AddVitalsSheet extends StatefulWidget {
  final String profileId;
  const _AddVitalsSheet({required this.profileId});

  @override
  State<_AddVitalsSheet> createState() => _AddVitalsSheetState();
}

class _AddVitalsSheetState extends State<_AddVitalsSheet> {
  final _heartRateCtrl = TextEditingController();
  final _sleepCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _stepsCtrl = TextEditingController();
  final _caloriesCtrl = TextEditingController();
  StressLevel? _stress;
  bool _saving = false;

  @override
  void dispose() {
    _heartRateCtrl.dispose();
    _sleepCtrl.dispose();
    _weightCtrl.dispose();
    _stepsCtrl.dispose();
    _caloriesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final hasAnyValue =
        [
          _heartRateCtrl,
          _sleepCtrl,
          _weightCtrl,
          _stepsCtrl,
          _caloriesCtrl,
        ].any((c) => c.text.trim().isNotEmpty) ||
            _stress != null;
    if (!hasAnyValue) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cargá al menos un valor.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final entry = VitalEntry(
        id: '',
        ownerUid: '',
        profileId: widget.profileId,
        date: DateTime.now(),
        heartRate: int.tryParse(_heartRateCtrl.text.trim()),
        sleepHours: double.tryParse(_sleepCtrl.text.trim()),
        weightKg: double.tryParse(_weightCtrl.text.trim()),
        steps: int.tryParse(_stepsCtrl.text.trim()),
        calories: int.tryParse(_caloriesCtrl.text.trim()),
        stressLevel: _stress,
      );
      await VitalsService.instance.addEntry(entry);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Registrar métricas de hoy',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cargá solo lo que tengas a mano — todos los campos son opcionales.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _NumField(
                      controller: _heartRateCtrl,
                      label: 'FC (BPM)',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumField(
                      controller: _sleepCtrl,
                      label: 'Sueño (hs)',
                      decimal: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _NumField(
                      controller: _weightCtrl,
                      label: 'Peso (kg)',
                      decimal: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumField(controller: _stepsCtrl, label: 'Pasos'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _NumField(controller: _caloriesCtrl, label: 'Calorías (kcal)'),
              const SizedBox(height: 16),
              const Text(
                'Nivel de estrés',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Row(
                children: StressLevel.values.map((s) {
                  final selected = _stress == s;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _stress = selected ? null : s),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? SaluteColors.primaryGreen.withValues(
                              alpha: 0.12,
                            )
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? SaluteColors.primaryGreen
                                  : Colors.grey.shade300,
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Text(
                            s.name[0].toUpperCase() + s.name.substring(1),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? SaluteColors.primaryGreen
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SaluteColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                      : const Text(
                    'GUARDAR',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool decimal;
  const _NumField({
    required this.controller,
    required this.label,
    this.decimal = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SaluteColors.primaryGreen,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}