import 'package:flutter/material.dart';
import 'package:saluteapp/components/ai_insight_card.dart';
import 'package:saluteapp/components/design_patterns.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/medical_record.dart';
import 'package:saluteapp/core/services/ai_insight_service.dart';
import 'package:saluteapp/core/services/medical_record_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cada check-in de estado emocional es un MedicalRecord más (categoría `animo`),
// cifrado y guardado en `profiles/{profileId}/historial` vía la misma
// infraestructura que ya usa Triaje (MedicalRecordService + CryptoService).
//
// Lo que SÍ es real acá: el check-in en sí, el historial de 7 días y los
// "disparadores" (se calculan por correlación simple sobre los registros
// guardados: cuántas emociones difíciles aparecen según lo que el usuario
// marcó en la Matriz Cognitiva). No requieren ningún servicio externo.
//
// Estado emocional: el usuario elige UNA de las 6 emociones básicas
// (alegría, tristeza, miedo, enojo, sorpresa, asco). Se guarda en
// `details['emotion']` como clave de texto estable (`_Emotion.name`), no
// como índice, así reordenar el enum no cambia el significado de los
// registros ya guardados. Los check-ins viejos (escala 1–5, guardados en
// `details['mood']`) quedan intactos en Firestore pero no se muestran en el
// historial emocional, porque no se pueden convertir a una emoción sin
// inventar el dato.
//
// Insight de IA ("Salute AI Diagnóstico"): lo resuelve `AiInsightCard`
// (AiInsightService). Se alimenta con los check-ins con emoción de los
// últimos 30 días (`_buildAiData`) y se vuelve a ejecutar cada vez que se
// guarda un check-in. Hasta tener 3 check-ins muestra un aviso en vez de
// inventar un análisis.
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kFocoOptions = ['Concentrado', 'Distraído', 'Nublado'];
const List<String> kEnergiaOptions = ['Agotado', 'Funcional', 'Activo'];
const List<String> kAnsiedadOptions = ['Nula', 'Leve', 'Somática'];

/// Las 6 emociones básicas (Ekman). `difficult` marca las que se cuentan
/// como "emociones difíciles" en Patrones Detectados; sorpresa no es
/// ni buena ni mala por sí misma, así que no cuenta como difícil.
///
/// IMPORTANTE: `name` se guarda en Firestore (`details['emotion']`). No
/// renombrar valores sin migrar los registros ya guardados.
enum _Emotion {
  alegria('😊', 'Alegría', Color(0xFFF5B841), false),
  tristeza('😢', 'Tristeza', Color(0xFF5B8DEF), true),
  miedo('😨', 'Miedo', Color(0xFF8E6CC9), true),
  enojo('😠', 'Enojo', Color(0xFFE5533D), true),
  sorpresa('😮', 'Sorpresa', Color(0xFFF08A4B), false),
  asco('🤢', 'Asco', Color(0xFF6FAE4F), true);

  final String emoji;
  final String label;
  final Color color;
  final bool difficult;
  const _Emotion(this.emoji, this.label, this.color, this.difficult);

  static _Emotion? fromKey(Object? key) {
    for (final e in values) {
      if (e.name == key) return e;
    }
    return null;
  }
}

class _MoodEntry {
  final DateTime date;

  /// `null` = check-in viejo (escala 1–5), previo al selector de emociones.
  final _Emotion? emotion;
  final int foco; // índice en kFocoOptions
  final int energia; // índice en kEnergiaOptions
  final int ansiedad; // índice en kAnsiedadOptions

  const _MoodEntry({
    required this.date,
    required this.emotion,
    required this.foco,
    required this.energia,
    required this.ansiedad,
  });

  factory _MoodEntry.fromRecord(MedicalRecord r) {
    return _MoodEntry(
      date: r.date,
      emotion: _Emotion.fromKey(r.details['emotion']),
      foco: (r.details['foco'] as num?)?.toInt() ?? 0,
      energia: (r.details['energia'] as num?)?.toInt() ?? 2,
      ansiedad: (r.details['ansiedad'] as num?)?.toInt() ?? 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

class MoodTrackerScreen extends StatefulWidget {
  final String profileId;
  final String profileName;
  final VoidCallback? onBackToDashboard;

  const MoodTrackerScreen({
    super.key,
    required this.profileId,
    required this.profileName,
    this.onBackToDashboard,
  });

  @override
  State<MoodTrackerScreen> createState() => _MoodTrackerScreenState();
}

class _MoodTrackerScreenState extends State<MoodTrackerScreen> {
  _Emotion?
  _selectedEmotion; // null = todavía no eligió (hay que elegir una para guardar)
  int _selectedFoco = 0; // Concentrado
  int _selectedEnergia = 2; // Activo
  int _selectedAnsiedad = 0; // Nula

  bool _loadingHistory = true;
  bool _saving = false;
  List<_MoodEntry> _entries = [];
  final _insightCtrl = AiInsightController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final records = await MedicalRecordService.instance.fetchRecords(
        widget.profileId,
        limit: 60,
      );
      final moodRecords = records
          .where((r) => r.category == RecordCategory.animo)
          .toList();
      final entries = moodRecords.map(_MoodEntry.fromRecord).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      if (!mounted) return;
      setState(() {
        _entries = entries;
        if (entries.isNotEmpty) {
          final latest = entries.last;
          _selectedFoco = latest.foco;
          _selectedEnergia = latest.energia;
          _selectedAnsiedad = latest.ansiedad;
        }
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el historial emocional: $e')),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  static String _opt(List<String> options, int i) =>
      options[i < 0 ? 0 : (i > 2 ? 2 : i)];

  /// Check-ins con emoción de los últimos 30 días (los viejos, sin emoción,
  /// no se pueden interpretar).
  List<_MoodEntry> get _recentWithEmotion {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return _entries
        .where((e) => e.emotion != null && e.date.isAfter(cutoff))
        .toList();
  }

  Map<String, dynamic> _buildAiData() {
    final now = DateTime.now();
    final list = _recentWithEmotion;
    final recent = list.length > 30 ? list.sublist(list.length - 30) : list;
    return AiPayload.clean({
      'checkins': [
        for (final e in recent)
          {
            'diasAtras': now.difference(e.date).inDays,
            'emocion': e.emotion!.label,
            'emocionDificil': e.emotion!.difficult,
            'foco': _opt(kFocoOptions, e.foco),
            'energia': _opt(kEnergiaOptions, e.energia),
            'ansiedad': _opt(kAnsiedadOptions, e.ansiedad),
          },
      ],
    });
  }

  Future<void> _saveCheckIn() async {
    final emotion = _selectedEmotion;
    if (emotion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elegí cómo te sentís antes de guardar.')),
      );
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final details = {
      'emotion': emotion.name,
      'foco': _selectedFoco,
      'energia': _selectedEnergia,
      'ansiedad': _selectedAnsiedad,
    };
    try {
      await MedicalRecordService.instance.addRecord(
        widget.profileId,
        MedicalRecord(
          id: '',
          category: RecordCategory.animo,
          date: now,
          title: 'Check-in emocional — ${widget.profileName}',
          professional: '',
          details: details,
        ),
      );
      if (!mounted) return;
      setState(() {
        _entries = [
          ..._entries,
          _MoodEntry(
            date: now,
            emotion: emotion,
            foco: _selectedFoco,
            energia: _selectedEnergia,
            ansiedad: _selectedAnsiedad,
          ),
        ];
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Guardado: ${emotion.emoji} ${emotion.label} (cifrado).',
          ),
        ),
      );
      _insightCtrl.run();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── AppBar ──────────────────────────────────────────────────────
            DsScreenHeader(
              title: 'Estado emocional',
              subtitle: widget.profileName,
              onBack: widget.onBackToDashboard,
            ),
            // ── Contenido ────────────────────────────────────────────────────
            Expanded(
              child: _loadingHistory
                  ? const Center(
                child: CircularProgressIndicator(
                  color: SaluteColors.primaryGreen,
                ),
              )
                  : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    _TrendCard(entries: _entries),
                    const SizedBox(height: 24),
                    _EmotionPicker(
                      selected: _selectedEmotion,
                      onSelect: (v) =>
                          setState(() => _selectedEmotion = v),
                    ),
                    const SizedBox(height: 24),
                    _CognitiveMatrix(
                      selectedFoco: _selectedFoco,
                      selectedEnergia: _selectedEnergia,
                      selectedAnsiedad: _selectedAnsiedad,
                      onFoco: (v) => setState(() => _selectedFoco = v),
                      onEnergia: (v) =>
                          setState(() => _selectedEnergia = v),
                      onAnsiedad: (v) =>
                          setState(() => _selectedAnsiedad = v),
                    ),
                    const SizedBox(height: 24),
                    _TriggersDetected(entries: _entries),
                    const SizedBox(height: 24),
                    AiInsightCard(
                      key: ValueKey('ai-emocional-${widget.profileId}'),
                      kind: 'emocional',
                      profileId: widget.profileId,
                      controller: _insightCtrl,
                      buildData: _buildAiData,
                      ready: _recentWithEmotion.length >= 3,
                      notReadyHint:
                      'Guardá al menos 3 check-ins para que el análisis tenga de dónde partir.',
                    ),
                    const SizedBox(height: 24),
                    _SaveButton(saving: _saving, onTap: _saveCheckIn),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. HISTORIAL 7 DÍAS  —  la emoción de cada día (real, sobre check-ins guardados)
// ─────────────────────────────────────────────────────────────────────────────

class _TrendCard extends StatelessWidget {
  final List<_MoodEntry> entries;
  const _TrendCard({required this.entries});

  static const _weekdayAbbrev = [
    'LUN',
    'MAR',
    'MIE',
    'JUE',
    'VIE',
    'SAB',
    'DOM',
  ];

  /// Los últimos 7 días calendario, terminando hoy (índice 6 = hoy).
  /// BUG-005: la etiqueta de cada día se calcula a partir de la fecha real
  /// (`DateTime.weekday`), no de su posición en la lista, porque esta
  /// ventana es rodante y no arranca siempre en lunes.
  List<DateTime> _last7Days() {
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 6));
    return List.generate(7, (i) => start.add(Duration(days: i)));
  }

  /// Emoción del ÚLTIMO check-in de cada día (`null` si ese día no hubo
  /// ninguno con emoción registrada).
  List<_Emotion?> _emotionsFor(List<DateTime> days) {
    return days.map((day) {
      final dayEntries =
      entries
          .where(
            (e) =>
        e.emotion != null &&
            e.date.year == day.year &&
            e.date.month == day.month &&
            e.date.day == day.day,
      )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      return dayEntries.isEmpty ? null : dayEntries.last.emotion;
    }).toList();
  }

  /// Emoción que más se repitió en la ventana de 7 días, con su cantidad
  /// y el total de check-ins considerados. `null` si no hay ninguno.
  ({_Emotion emotion, int count, int total})? _predominant(
      DateTime windowStart,
      ) {
    final inWindow = entries
        .where((e) => e.emotion != null && !e.date.isBefore(windowStart))
        .toList();
    if (inWindow.isEmpty) return null;
    final counts = <_Emotion, int>{};
    for (final e in inWindow) {
      counts[e.emotion!] = (counts[e.emotion!] ?? 0) + 1;
    }
    final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    return (emotion: top.key, count: top.value, total: inWindow.length);
  }

  @override
  Widget build(BuildContext context) {
    final days = _last7Days();
    final emotions = _emotionsFor(days);
    final predominant = _predominant(days.first);
    final hasData = entries.any((e) => e.emotion != null);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Últimos 7 días',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      predominant == null
                          ? 'Todavía sin registros esta semana'
                          : 'Predominó: ${predominant.emotion.emoji} ${predominant.emotion.label} '
                          '(${predominant.count} de ${predominant.total} '
                          'check-in${predominant.total == 1 ? '' : 's'})',
                      style: const TextStyle(
                        color: SaluteColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.emoji_emotions_outlined,
                color: SaluteColors.primaryGreen,
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Registrá tu primer check-in emocional para empezar a ver tu historial acá.',
                style: TextStyle(color: SaluteColors.textMuted, fontSize: 13),
              ),
            )
          else
            Row(
              children: List.generate(7, (i) {
                final emotion = emotions[i];
                return Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: emotion == null
                              ? Colors.grey.shade100
                              : emotion.color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: emotion == null
                            ? Text(
                          '–',
                          style: TextStyle(
                            fontSize: 16,
                            color: SaluteColors.textMuted,
                          ),
                        )
                            : Text(
                          emotion.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _weekdayAbbrev[days[i].weekday - 1],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: SaluteColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. ESTADO EMOCIONAL  —  6 emociones básicas con carita, una seleccionable
// ─────────────────────────────────────────────────────────────────────────────

class _EmotionPicker extends StatelessWidget {
  final _Emotion? selected;
  final ValueChanged<_Emotion> onSelect;

  const _EmotionPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final all = _Emotion.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DsSectionHeader(title: 'Estado emocional'),
        const SizedBox(height: 4),
        Text(
          '¿Qué emoción describe mejor cómo te sentís ahora?',
          style: TextStyle(fontSize: 13, color: SaluteColors.textMuted),
        ),
        const SizedBox(height: 16),
        // 2 filas × 3 emociones.
        for (var r = 0; r < 2; r++) ...[
          if (r > 0) const SizedBox(height: 10),
          Row(
            children: [
              for (var c = 0; c < 3; c++) ...[
                if (c > 0) const SizedBox(width: 10),
                Expanded(
                  child: _EmotionTile(
                    emotion: all[r * 3 + c],
                    isSelected: selected == all[r * 3 + c],
                    onTap: () => onSelect(all[r * 3 + c]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _EmotionTile extends StatelessWidget {
  final _Emotion emotion;
  final bool isSelected;
  final VoidCallback onTap;

  const _EmotionTile({
    required this.emotion,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: emotion.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? emotion.color.withValues(alpha: 0.15)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            // Mismo ancho de borde seleccionado o no, para que no "salte" el layout.
            border: Border.all(
              color: isSelected ? emotion.color : Colors.grey.shade200,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              AnimatedScale(
                scale: isSelected ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 180),
                child: Text(
                  emotion.emoji,
                  style: const TextStyle(fontSize: 34),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                emotion.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.black87 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. MATRIZ COGNITIVA
// ─────────────────────────────────────────────────────────────────────────────

class _CognitiveMatrix extends StatelessWidget {
  final int selectedFoco, selectedEnergia, selectedAnsiedad;
  final ValueChanged<int> onFoco, onEnergia, onAnsiedad;

  const _CognitiveMatrix({
    required this.selectedFoco,
    required this.selectedEnergia,
    required this.selectedAnsiedad,
    required this.onFoco,
    required this.onEnergia,
    required this.onAnsiedad,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DsSectionHeader(title: 'Matriz Cognitiva'),
        const SizedBox(height: 16),
        _MatrixSection(
          title: 'FOCO & ATENCIÓN',
          options: kFocoOptions,
          current: selectedFoco,
          onSelect: onFoco,
        ),
        const SizedBox(height: 12),
        _MatrixSection(
          title: 'NIVELES DE ENERGÍA',
          options: kEnergiaOptions,
          current: selectedEnergia,
          onSelect: onEnergia,
        ),
        const SizedBox(height: 12),
        _MatrixSection(
          title: 'PERCEPCIÓN ANSIEDAD',
          options: kAnsiedadOptions,
          current: selectedAnsiedad,
          onSelect: onAnsiedad,
        ),
      ],
    );
  }
}

class _MatrixSection extends StatelessWidget {
  final String title;
  final List<String> options;
  final int current;
  final ValueChanged<int> onSelect;

  const _MatrixSection({
    required this.title,
    required this.options,
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SaluteColors.lightGreen.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: SaluteColors.primaryGreen,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(3, (i) {
              final isSelected = current == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(right: i == 2 ? 0 : 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? SaluteColors.primaryGreen
                          : SaluteColors.lightGreen,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(
                        color: SaluteColors.darkGreen,
                        width: 1.5,
                      )
                          : null,
                      boxShadow: isSelected
                          ? [
                        BoxShadow(
                          color: SaluteColors.primaryGreen.withValues(
                            alpha: 0.3,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        options[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white
                              : SaluteColors.primaryGreen,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. DISPARADORES DETECTADOS
//    Correlación simple sobre los check-ins guardados: para cada eje de la
//    Matriz Cognitiva, compara qué porcentaje de check-ins fueron
//    "emociones difíciles" (tristeza, miedo, enojo, asco) cuando ese eje
//    estaba en su nivel "negativo" (Nublado / Agotado / Somática) contra
//    cuando estaba en el "positivo" (Concentrado / Activo / Nula). Es
//    agregación sobre datos propios del usuario, no un modelo de IA.
//    Los check-ins viejos (sin emoción) no cuentan.
// ─────────────────────────────────────────────────────────────────────────────

class _TriggerStat {
  final String title;
  final String subtitle;
  final IconData icon;

  /// Diferencia en PUNTOS PORCENTUALES de emociones difíciles entre el nivel
  /// negativo y el positivo del eje. > 0 → con el nivel negativo aparecen
  /// más emociones difíciles (lo esperable para un disparador real).
  /// `null` = datos insuficientes.
  final double? diffPts;
  const _TriggerStat({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.diffPts,
  });
}

class _TriggersDetected extends StatelessWidget {
  final List<_MoodEntry> entries;
  const _TriggersDetected({required this.entries});

  static double _difficultShare(List<_MoodEntry> list) =>
      list.where((e) => e.emotion!.difficult).length / list.length;

  _TriggerStat _statFor({
    required String title,
    required IconData icon,
    required int Function(_MoodEntry) axisValue,
    required int negativeIndex,
    required int positiveIndex,
  }) {
    final withEmotion = entries.where((e) => e.emotion != null).toList();
    final negative = withEmotion
        .where((e) => axisValue(e) == negativeIndex)
        .toList();
    final positive = withEmotion
        .where((e) => axisValue(e) == positiveIndex)
        .toList();
    if (negative.length < 2 || positive.length < 2) {
      return _TriggerStat(
        title: title,
        subtitle: 'Necesitás más check-ins para detectar un patrón acá',
        icon: icon,
      );
    }
    final negShare = _difficultShare(negative);
    final posShare = _difficultShare(positive);
    return _TriggerStat(
      title: title,
      subtitle:
      'Emociones difíciles según el nivel: '
          '${(negShare * 100).round()} % vs. ${(posShare * 100).round()} %',
      icon: icon,
      diffPts: (negShare - posShare) * 100,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = [
      _statFor(
        title: 'Percepción Ansiedad',
        icon: Icons.bolt_outlined,
        axisValue: (e) => e.ansiedad,
        negativeIndex: 2, // Somática
        positiveIndex: 0, // Nula
      ),
      _statFor(
        title: 'Niveles de Energía',
        icon: Icons.battery_alert_outlined,
        axisValue: (e) => e.energia,
        negativeIndex: 0, // Agotado
        positiveIndex: 2, // Activo
      ),
      _statFor(
        title: 'Foco & Atención',
        icon: Icons.blur_on,
        axisValue: (e) => e.foco,
        negativeIndex: 2, // Nublado
        positiveIndex: 0, // Concentrado
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SaluteColors.lightGreen.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(
                Icons.insights_outlined,
                color: SaluteColors.primaryGreen,
                size: 22,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Patrones Detectados',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: SaluteColors.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Calculado sobre tus check-ins guardados, no es un diagnóstico.',
              style: TextStyle(fontSize: 12, color: SaluteColors.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < stats.length; i++) ...[
            _TriggerItem(stat: stats[i]),
            if (i != stats.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _TriggerItem extends StatelessWidget {
  final _TriggerStat stat;
  const _TriggerItem({required this.stat});

  @override
  Widget build(BuildContext context) {
    final diff = stat.diffPts;
    final isAlert = diff != null && diff > 10;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SaluteColors.lightGreen, width: 1),
      ),
      child: Row(
        children: [
          Icon(stat.icon, size: 28, color: SaluteColors.primaryGreen),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: SaluteColors.primaryGreen,
                  ),
                ),
                Text(
                  stat.subtitle,
                  style: TextStyle(fontSize: 12, color: SaluteColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            diff == null
                ? '—'
                : '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(0)} pts',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: diff == null
                  ? SaluteColors.textMuted
                  : (isAlert ? SaluteColors.danger : SaluteColors.primaryGreen),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTÓN GUARDAR CHECK-IN
// ─────────────────────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  final bool saving;
  final VoidCallback onTap;
  const _SaveButton({required this.saving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: double.infinity,
        minHeight: 52,
      ),
      child: ElevatedButton(
        onPressed: saving ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: SaluteColors.primaryGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: saving
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        )
            : const Text(
          'GUARDAR CHECK-IN DE HOY',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}