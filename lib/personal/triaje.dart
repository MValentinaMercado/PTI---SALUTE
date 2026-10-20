import 'package:flutter/material.dart';
import 'package:saluteapp/components/ai_insight_card.dart';
import 'package:saluteapp/components/design_patterns.dart';
import 'package:saluteapp/components/voice_buttons.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/medical_record.dart';
import 'package:saluteapp/core/services/ai_insight_service.dart';
import 'package:saluteapp/core/services/health_red_flags.dart';
import 'package:saluteapp/core/services/medical_record_service.dart';
import 'package:saluteapp/map_screen.dart';

/// Bitácora de triaje de un perfil puntual (persona o mascota).
/// Cada "GUARDAR EN DIARIO PRIVADO" crea un [MedicalRecord] cifrado en
/// `profiles/{profileId}/historial` (categoría `triaje`, ver
/// MedicalRecordService). La cronología y los signos vitales que se ven
/// acá salen de esos registros reales, no de datos de ejemplo.
class BitacoraTriajeScreen extends StatefulWidget {
  final String profileId;
  final String profileName;
  final VoidCallback? onBackToDashboard;

  const BitacoraTriajeScreen({
    super.key,
    required this.profileId,
    required this.profileName,
    this.onBackToDashboard,
  });

  @override
  State<BitacoraTriajeScreen> createState() => _BitacoraTriajeScreenState();
}

class _BitacoraTriajeScreenState extends State<BitacoraTriajeScreen> {
  int _triajeLevel = 3;
  double _evaDolor = 0;
  bool _loadingHistory = true;
  bool _saving = false;
  List<_TriageEntry> _triageTimeline = [];
  DateTime? _lastSavedAt;

  // Signos vitales: null hasta que el usuario los carga a mano (no hay
  // integración con wearables todavía). Se muestran como "—" en ese caso.
  double? _heartRate;
  double? _temperature;
  double? _oxygenSat;
  String? _bloodPressure;

  final Set<String> _selectedSymptoms = {};
  final Set<String> _expandedSystems = {'Respiratorio'};
  final Map<String, String> _selectedPrimaryBySystem = {};
  final Map<String, String> _selectedSpecifierByPrimary = {};

  final _subjectiveCtrl = TextEditingController();
  final _objectiveCtrl = TextEditingController();
  final _assessmentCtrl = TextEditingController();
  final _planCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _insightCtrl = AiInsightController();

  /// {sistema: {sintoma, especificador}} con lo elegido en "Sistemas de
  /// síntomas". Antes no se guardaba ni se usaba.
  Map<String, Map<String, String>> _principalSymptoms() {
    return {
      for (final e in _selectedPrimaryBySystem.entries)
        e.key: {
          'sintoma': e.value,
          if (_selectedSpecifierByPrimary[e.value] != null)
            'especificador': _selectedSpecifierByPrimary[e.value]!,
        },
    };
  }

  Map<String, dynamic> _triageAiData() => AiPayload.clean({
    'nivelAutoclasificado': _triajeLevel,
    'eva_0_a_10': _evaDolor.round(),
    'vitales': {
      'frecuenciaCardiacaBpm': _heartRate,
      'temperaturaC': _temperature,
      'saturacionO2Pct': _oxygenSat,
      'presionArterialMmHg': _bloodPressure,
    },
    'sintomasPrincipales': _principalSymptoms(),
    'otrosSintomas': _selectedSymptoms.toList(),
    'soap': {
      'subjetivo': _subjectiveCtrl.text,
      'objetivo': _objectiveCtrl.text,
      'apreciacion': _assessmentCtrl.text,
      'plan': _planCtrl.text,
    },
  });

  bool get _triageAiReady =>
      _selectedSymptoms.isNotEmpty ||
          _selectedPrimaryBySystem.isNotEmpty ||
          _subjectiveCtrl.text.trim().isNotEmpty;

  List<String> get _triageRedFlags => HealthRedFlags.triage(
    level: _triajeLevel,
    eva: _evaDolor,
    heartRate: _heartRate,
    temperature: _temperature,
    oxygenSat: _oxygenSat,
    bloodPressure: _bloodPressure,
    primaryBySystem: _selectedPrimaryBySystem,
    specifierByPrimary: _selectedSpecifierByPrimary,
  );

  void _scrollToInsight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

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
      final triageRecords = records
          .where((r) => r.category == RecordCategory.triaje)
          .toList();
      if (!mounted) return;
      setState(() {
        _triageTimeline = triageRecords
            .map(
              (r) => _TriageEntry(
            timestamp: r.date,
            level: (r.details['nivel'] as num?)?.toInt() ?? 3,
          ),
        )
            .toList();
        if (triageRecords.isNotEmpty) {
          final latest =
              triageRecords.first; // fetchRecords viene ordenado desc por fecha
          _lastSavedAt = latest.date;
          _triajeLevel =
              (latest.details['nivel'] as num?)?.toInt() ?? _triajeLevel;
          _evaDolor = (latest.details['eva'] as num?)?.toDouble() ?? _evaDolor;
          _heartRate = (latest.details['heartRate'] as num?)?.toDouble();
          _temperature = (latest.details['temperature'] as num?)?.toDouble();
          _oxygenSat = (latest.details['oxygenSat'] as num?)?.toDouble();
          _bloodPressure = latest.details['bloodPressure'] as String?;
          final symptoms = (latest.details['sintomas'] as List?)
              ?.cast<String>();
          if (symptoms != null) _selectedSymptoms.addAll(symptoms);
        }
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el historial de triaje: $e')),
      );
    }
  }

  @override
  void dispose() {
    _subjectiveCtrl.dispose();
    _objectiveCtrl.dispose();
    _assessmentCtrl.dispose();
    _planCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _toggleSystem(String name) {
    setState(() {
      if (_expandedSystems.contains(name)) {
        _expandedSystems.remove(name);
      } else {
        _expandedSystems.add(name);
      }
    });
  }

  void _toggleSymptom(String name) {
    setState(() {
      if (_selectedSymptoms.contains(name)) {
        _selectedSymptoms.remove(name);
      } else {
        _selectedSymptoms.add(name);
      }
    });
  }

  void _togglePrimarySymptom(String systemName, String symptomName) {
    setState(() {
      final current = _selectedPrimaryBySystem[systemName];
      if (current == symptomName) {
        _selectedPrimaryBySystem.remove(systemName);
        _selectedSpecifierByPrimary.remove(symptomName);
      } else {
        if (current != null) {
          _selectedSpecifierByPrimary.remove(current);
        }
        _selectedPrimaryBySystem[systemName] = symptomName;
      }
    });
  }

  void _toggleSpecifier(String symptomName, String specifier) {
    setState(() {
      if (_selectedSpecifierByPrimary[symptomName] == specifier) {
        _selectedSpecifierByPrimary.remove(symptomName);
      } else {
        _selectedSpecifierByPrimary[symptomName] = specifier;
      }
    });
  }

  void _setTriageLevel(int level) {
    if (level == _triajeLevel) return;
    setState(() => _triajeLevel = level);
  }

  void _cycleTriageLevel() {
    final next = _triajeLevel == 3 ? 1 : _triajeLevel + 1;
    setState(() => _triajeLevel = next);
  }

  Future<void> _editVital({
    required String title,
    required String hint,
    required String? initialValue,
    required ValueChanged<String> onSaved,
    TextInputType keyboardType = const TextInputType.numberWithOptions(
      decimal: true,
    ),
  }) async {
    final ctrl = TextEditingController(text: initialValue ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      onSaved(result);
    }
  }

  List<_TriageEntry> get _entries48h {
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));
    final list =
    _triageTimeline.where((e) => e.timestamp.isAfter(cutoff)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  Map<String, dynamic> _buildTriageDetails() {
    return {
      'nivel': _triajeLevel,
      'eva': _evaDolor,
      'sintomas': _selectedSymptoms.toList(),
      'heartRate': _heartRate,
      'temperature': _temperature,
      'oxygenSat': _oxygenSat,
      'bloodPressure': _bloodPressure,
      'subjetivo': _subjectiveCtrl.text,
      'objetivo': _objectiveCtrl.text,
      'apreciacion': _assessmentCtrl.text,
      'plan': _planCtrl.text,
      'sintomasPrincipales': _principalSymptoms(),
    };
  }

  Future<void> _saveInPrivateDiary() async {
    setState(() => _saving = true);
    final now = DateTime.now();
    try {
      await MedicalRecordService.instance.addRecord(
        widget.profileId,
        MedicalRecord(
          id: '',
          category: RecordCategory.triaje,
          date: now,
          title: 'Triaje nivel $_triajeLevel — ${widget.profileName}',
          professional: '',
          details: _buildTriageDetails(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _triageTimeline = [
          ..._triageTimeline,
          _TriageEntry(timestamp: now, level: _triajeLevel),
        ];
        _lastSavedAt = now;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guardado en el diario privado (cifrado).'),
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

  void _generateGuardShiftSheet() {
    final d = _buildTriageDetails();
    final resumen =
        'Nivel ${d['nivel']} · EVA ${(_evaDolor).toStringAsFixed(0)}/10'
        '${_selectedSymptoms.isNotEmpty ? ' · ${_selectedSymptoms.first}' : ''}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ficha para guardia de ${widget.profileName}: $resumen'),
      ),
    );
  }

  void _goToGuardMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SaluteMapScreen(onBackToDashboard: widget.onBackToDashboard),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F5),
      body: SafeArea(
        child: Column(
          children: [
            DsScreenHeader(
              title: 'Bitácora de Triaje',
              subtitle: widget.profileName,
              onBack: widget.onBackToDashboard,
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ClasificacionSection(
                      selectedLevel: _triajeLevel,
                      onLevelChanged: _setTriageLevel,
                      onSwap: _cycleTriageLevel,
                    ),
                    const SizedBox(height: 16),
                    if (_loadingHistory)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      _TimelineTrendSection(entries: _entries48h),
                    const SizedBox(height: 16),
                    _PacienteInfoRow(
                      profileName: widget.profileName,
                      lastSavedAt: _lastSavedAt,
                    ),
                    const SizedBox(height: 16),
                    _VitalesGrid(
                      heartRate: _heartRate,
                      temperature: _temperature,
                      oxygenSat: _oxygenSat,
                      bloodPressure: _bloodPressure,
                      onEditHeartRate: () => _editVital(
                        title: 'Frecuencia cardíaca (BPM)',
                        hint: 'Ej: 78',
                        initialValue: _heartRate?.toStringAsFixed(0),
                        onSaved: (v) =>
                            setState(() => _heartRate = double.tryParse(v)),
                      ),
                      onEditTemperature: () => _editVital(
                        title: 'Temperatura (°C)',
                        hint: 'Ej: 36.8',
                        initialValue: _temperature?.toStringAsFixed(1),
                        onSaved: (v) =>
                            setState(() => _temperature = double.tryParse(v)),
                      ),
                      onEditOxygenSat: () => _editVital(
                        title: 'Saturación de oxígeno (%)',
                        hint: 'Ej: 98',
                        initialValue: _oxygenSat?.toStringAsFixed(0),
                        onSaved: (v) =>
                            setState(() => _oxygenSat = double.tryParse(v)),
                      ),
                      onEditBloodPressure: () => _editVital(
                        title: 'Presión arterial (mmHg)',
                        hint: 'Ej: 120/80',
                        initialValue: _bloodPressure,
                        keyboardType: TextInputType.text,
                        onSaved: (v) => setState(() => _bloodPressure = v),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _EVASection(
                      value: _evaDolor,
                      onChanged: (value) => setState(() => _evaDolor = value),
                    ),
                    const SizedBox(height: 20),
                    _SistemasSection(
                      expandedSystems: _expandedSystems,
                      selectedSymptoms: _selectedSymptoms,
                      selectedPrimaryBySystem: _selectedPrimaryBySystem,
                      selectedSpecifierByPrimary: _selectedSpecifierByPrimary,
                      onToggleSystem: _toggleSystem,
                      onToggleSymptom: _toggleSymptom,
                      onTogglePrimarySymptom: _togglePrimarySymptom,
                      onToggleSpecifier: _toggleSpecifier,
                    ),
                    const SizedBox(height: 24),
                    _SOAPSection(
                      triajeLevel: _triajeLevel,
                      evaDolor: _evaDolor,
                      subjectiveCtrl: _subjectiveCtrl,
                      objectiveCtrl: _objectiveCtrl,
                      assessmentCtrl: _assessmentCtrl,
                      planCtrl: _planCtrl,
                    ),
                    const SizedBox(height: 20),
                    ListenableBuilder(
                      // Se reconstruye mientras escribís: actualiza "listo" y
                      // las señales de alarma en vivo.
                      listenable: Listenable.merge([
                        _subjectiveCtrl,
                        _objectiveCtrl,
                        _assessmentCtrl,
                        _planCtrl,
                      ]),
                      builder: (context, _) => AiInsightCard(
                        key: ValueKey('ai-triaje-${widget.profileId}'),
                        kind: 'triaje',
                        profileId: widget.profileId,
                        controller: _insightCtrl,
                        buildData: _triageAiData,
                        redFlags: _triageRedFlags,
                        ready: _triageAiReady,
                        notReadyHint:
                        'Cargá al menos un síntoma o describí qué sentís para poder analizar.',
                        onStateChanged: _scrollToInsight,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _BottomBar(
              triageLevel: _triajeLevel,
              saving: _saving,
              onSavePrivateDiary: _saveInPrivateDiary,
              onGenerateGuardSheet: _generateGuardShiftSheet,
              onGoToGuardMap: _goToGuardMap,
            ),
          ],
        ),
      ),
    );
  }
}

class _TriageEntry {
  final DateTime timestamp;
  final int level;

  const _TriageEntry({required this.timestamp, required this.level});
}

class _TimelineTrendSection extends StatelessWidget {
  final List<_TriageEntry> entries;

  const _TimelineTrendSection({required this.entries});

  String _trendText() {
    if (entries.length < 2) return 'Sin tendencia';
    final delta = entries.last.level - entries.first.level;
    if (delta > 0) return 'Tendencia: nivel subio';
    if (delta < 0) return 'Tendencia: nivel bajo';
    return 'Tendencia: estable';
  }

  String _fmt(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$d/$m $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final recent = entries.length > 5
        ? entries.sublist(entries.length - 5)
        : entries;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: const Text(
                  'CRONOLOGIA (ULTIMAS 48H)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _trendText(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            width: double.infinity,
            child: CustomPaint(painter: _TrendPainter(entries: entries)),
          ),
          const SizedBox(height: 12),
          ...recent.map(
                (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: e.level == 1
                          ? const Color(0xFFCC2929)
                          : e.level == 2
                          ? SaluteColors.warning
                          : SaluteColors.primaryGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: e.level == 1
                              ? const Color(0xFFCC2929).withValues(alpha: 0.3)
                              : e.level == 2
                              ? SaluteColors.warning.withValues(alpha: 0.3)
                              : SaluteColors.primaryGreen.withValues(
                            alpha: 0.3,
                          ),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fmt(e.timestamp),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Nivel ${e.level}',
                          style: TextStyle(
                            fontSize: 12,
                            color: SaluteColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: e.level == 1
                          ? const Color(0xFFCC2929).withValues(alpha: 0.1)
                          : e.level == 2
                          ? SaluteColors.warning.withValues(alpha: 0.1)
                          : SaluteColors.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      e.level == 1
                          ? 'EMERGENCIA'
                          : e.level == 2
                          ? 'URGENCIA'
                          : 'ESTABLE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: e.level == 1
                            ? const Color(0xFFCC2929)
                            : e.level == 2
                            ? SaluteColors.warning
                            : SaluteColors.primaryGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<_TriageEntry> entries;

  const _TrendPainter({required this.entries});

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      axisPaint,
    );

    if (entries.length < 2) return;

    final sorted = [...entries]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final first = sorted.first.timestamp.millisecondsSinceEpoch.toDouble();
    final last = sorted.last.timestamp.millisecondsSinceEpoch.toDouble();
    final span = (last - first).abs() < 1 ? 1 : (last - first);

    final path = Path();
    for (var i = 0; i < sorted.length; i++) {
      final item = sorted[i];
      final t = (item.timestamp.millisecondsSinceEpoch - first) / span;
      final x = t * size.width;
      final y = ((3 - item.level) / 2) * (size.height - 8) + 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = SaluteColors.primaryGreen
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.entries != entries;
}

class _ClasificacionSection extends StatelessWidget {
  final int selectedLevel;
  final ValueChanged<int> onLevelChanged;
  final VoidCallback onSwap;

  const _ClasificacionSection({
    required this.selectedLevel,
    required this.onLevelChanged,
    required this.onSwap,
  });

  Color get _levelColor {
    switch (selectedLevel) {
      case 1:
        return const Color(0xFFCC2929);
      case 2:
        return SaluteColors.warning;
      default:
        return SaluteColors.primaryGreen;
    }
  }

  String get _levelText {
    switch (selectedLevel) {
      case 1:
        return 'NIVEL 1: EMERGENCIA';
      case 2:
        return 'NIVEL 2: URGENCIA';
      default:
        return 'NIVEL 3: ESTABLE';
    }
  }

  IconData get _levelIcon {
    switch (selectedLevel) {
      case 1:
        return Icons.error_rounded;
      case 2:
        return Icons.warning_amber_rounded;
      default:
        return Icons.check_circle_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CLASIFICACION ACTUAL',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: SaluteColors.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: _levelColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _levelColor.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(_levelIcon, color: Colors.white, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _levelText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedLevel == 1
                          ? 'Requiere atención inmediata'
                          : selectedLevel == 2
                          ? 'Requiere atención urgente'
                          : 'Paciente estable',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cambiar',
                onPressed: onSwap,
                icon: const Icon(
                  Icons.swap_horiz,
                  color: Colors.white,
                  size: 22,
                ),
                splashRadius: 24,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _LevelChip(
                label: '1: EMERGENCIA',
                selected: selectedLevel == 1,
                onTap: () => onLevelChanged(1),
                selectedColor: const Color(0xFFCC2929),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LevelChip(
                label: '2: URGENCIA',
                selected: selectedLevel == 2,
                onTap: () => onLevelChanged(2),
                selectedColor: SaluteColors.warning,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LevelChip(
                label: '3: ESTABLE',
                selected: selectedLevel == 3,
                onTap: () => onLevelChanged(3),
                selectedColor: SaluteColors.primaryGreen,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LevelChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;

  const _LevelChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? selectedColor : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? selectedColor : const Color(0xFFE0E0E0),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.black87,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PacienteInfoRow extends StatelessWidget {
  final String profileName;
  final DateTime? lastSavedAt;

  const _PacienteInfoRow({
    required this.profileName,
    required this.lastSavedAt,
  });

  String get _lastSavedLabel {
    if (lastSavedAt == null) return 'Sin registros';
    final diff = DateTime.now().difference(lastSavedAt!);
    if (diff.inMinutes < 1) return 'Recién';
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} día(s)';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _InfoCell(
            label: 'PACIENTE',
            value: profileName,
            valueStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          Container(width: 1, height: 36, color: const Color(0xFFEEEEEE)),
          _InfoCell(
            label: 'ÚLTIMO REGISTRO',
            value: _lastSavedLabel,
            valueStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: SaluteColors.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle valueStyle;

  const _InfoCell({
    required this.label,
    required this.value,
    required this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: SaluteColors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(value, style: valueStyle),
          ],
        ),
      ),
    );
  }
}

/// Grilla de signos vitales. Son datos cargados a mano por el usuario
/// (no hay integración con wearables todavía) — null hasta que se editan
/// una vez, y se muestran como "—" mientras tanto.
class _VitalesGrid extends StatelessWidget {
  final double? heartRate;
  final double? temperature;
  final double? oxygenSat;
  final String? bloodPressure;
  final VoidCallback onEditHeartRate;
  final VoidCallback onEditTemperature;
  final VoidCallback onEditOxygenSat;
  final VoidCallback onEditBloodPressure;

  const _VitalesGrid({
    required this.heartRate,
    required this.temperature,
    required this.oxygenSat,
    required this.bloodPressure,
    required this.onEditHeartRate,
    required this.onEditTemperature,
    required this.onEditOxygenSat,
    required this.onEditBloodPressure,
  });

  // Umbrales simples de referencia, solo para dar una pista visual.
  // No reemplaza criterio médico.
  (String, Color) get _heartRateStatus {
    if (heartRate == null) return ('Sin datos', SaluteColors.textMuted);
    if (heartRate! < 60 || heartRate! > 100) {
      return ('Fuera de rango', SaluteColors.warning);
    }
    return ('Normal (Estable)', SaluteColors.textMuted);
  }

  (String, Color) get _temperatureStatus {
    if (temperature == null) return ('Sin datos', SaluteColors.textMuted);
    if (temperature! >= 37.8) return ('Febrícula', SaluteColors.warning);
    if (temperature! < 35.5) return ('Hipotermia', SaluteColors.warning);
    return ('Normal', SaluteColors.textMuted);
  }

  (String, Color) get _oxygenStatus {
    if (oxygenSat == null) return ('Sin datos', SaluteColors.textMuted);
    if (oxygenSat! < 95) return ('Bajo', SaluteColors.warning);
    return ('Óptimo', SaluteColors.textMuted);
  }

  @override
  Widget build(BuildContext context) {
    final hrStatus = _heartRateStatus;
    final tempStatus = _temperatureStatus;
    final o2Status = _oxygenStatus;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _VitalCard(
                icon: Icons.favorite,
                iconColor: SaluteColors.primaryGreen,
                unit: 'BPM',
                value: heartRate != null ? heartRate!.toStringAsFixed(0) : '—',
                label: hrStatus.$1,
                labelColor: hrStatus.$2,
                unitColor: SaluteColors.primaryGreen,
                onTap: onEditHeartRate,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _VitalCard(
                icon: Icons.thermostat_outlined,
                iconColor: SaluteColors.warning,
                unit: '°C',
                value: temperature != null
                    ? temperature!.toStringAsFixed(1)
                    : '—',
                label: tempStatus.$1,
                labelColor: tempStatus.$2,
                unitColor: SaluteColors.warning,
                valueColor: tempStatus.$2 == SaluteColors.warning
                    ? SaluteColors.warning
                    : null,
                onTap: onEditTemperature,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _VitalCard(
                icon: Icons.air,
                iconColor: SaluteColors.primaryGreen,
                unit: 'O2%',
                value: oxygenSat != null ? oxygenSat!.toStringAsFixed(0) : '—',
                label: o2Status.$1,
                labelColor: o2Status.$2,
                unitColor: SaluteColors.primaryGreen,
                onTap: onEditOxygenSat,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _VitalCard(
                icon: Icons.monitor_heart_outlined,
                iconColor: SaluteColors.primaryGreen,
                unit: 'mmHg',
                value: bloodPressure?.isNotEmpty == true ? bloodPressure! : '—',
                label: bloodPressure?.isNotEmpty == true
                    ? 'Cargada'
                    : 'Sin datos',
                labelColor: SaluteColors.textMuted,
                unitColor: SaluteColors.primaryGreen,
                onTap: onEditBloodPressure,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VitalCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String unit;
  final String value;
  final String label;
  final Color labelColor;
  final Color unitColor;
  final Color? valueColor;
  final VoidCallback? onTap;

  const _VitalCard({
    required this.icon,
    required this.iconColor,
    required this.unit,
    required this.value,
    required this.label,
    required this.labelColor,
    required this.unitColor,
    this.valueColor,
    this.onTap,
  });

  bool get _isAbnormal =>
      labelColor == SaluteColors.warning || labelColor == SaluteColors.danger;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isAbnormal
                ? SaluteColors.warning.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 16),
                ),
                if (_isAbnormal)
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: SaluteColors.warning.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_outlined,
                      size: 12,
                      color: SaluteColors.warning,
                    ),
                  )
                else
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 12,
                      color: SaluteColors.primaryGreen,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: valueColor ?? Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              unit,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: unitColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: labelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EVASection extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _EVASection({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'ESCALA EVA (DOLOR)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: SaluteColors.textMuted,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  value.round().toString(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: SaluteColors.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: 10,
            divisions: 10,
            label: value.round().toString(),
            activeColor: SaluteColors.primaryGreen,
            inactiveColor: SaluteColors.lightGreen,
            onChanged: onChanged,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '0: Sin dolor',
                  style: TextStyle(
                    fontSize: 12,
                    color: SaluteColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  '5: Moderado',
                  style: TextStyle(
                    fontSize: 12,
                    color: SaluteColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  '10: Insoportable',
                  style: TextStyle(
                    fontSize: 12,
                    color: SaluteColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SistemasSection extends StatelessWidget {
  final Set<String> expandedSystems;
  final Set<String> selectedSymptoms;
  final Map<String, String> selectedPrimaryBySystem;
  final Map<String, String> selectedSpecifierByPrimary;
  final ValueChanged<String> onToggleSystem;
  final ValueChanged<String> onToggleSymptom;
  final void Function(String systemName, String symptomName)
  onTogglePrimarySymptom;
  final void Function(String symptomName, String specifier) onToggleSpecifier;

  const _SistemasSection({
    required this.expandedSystems,
    required this.selectedSymptoms,
    required this.selectedPrimaryBySystem,
    required this.selectedSpecifierByPrimary,
    required this.onToggleSystem,
    required this.onToggleSymptom,
    required this.onTogglePrimarySymptom,
    required this.onToggleSpecifier,
  });

  static const _systems = [
    _SystemData(
      name: 'Respiratorio',
      icon: Icons.air,
      primarySymptoms: [
        _PrimarySymptom(
          name: 'Dificultad para respirar (Disnea)',
          specifiers: ['En reposo', 'Al caminar', 'Al acostarse'],
        ),
        _PrimarySymptom(
          name: 'Tos',
          specifiers: ['Seca', 'Con flemas', 'Con sangre'],
        ),
        _PrimarySymptom(
          name: 'Dolor al respirar',
          specifiers: ['Puntada en la espalda', 'Presion en el pecho'],
        ),
      ],
      otherSymptoms: [
        'Sibilancias (silbidos)',
        'Congestion nasal',
        'Estornudos',
      ],
    ),
    _SystemData(
      name: 'Neurologico y Salud Mental',
      icon: Icons.psychology_outlined,
      primarySymptoms: [
        _PrimarySymptom(
          name: 'Cefaleas (Dolor de cabeza)',
          specifiers: ['Pulsatil', 'Opresivo', 'Localizado en un ojo'],
        ),
        _PrimarySymptom(
          name: 'Nivel de conciencia',
          specifiers: ['Somnolencia', 'Desorientacion', 'Mareo'],
        ),
        _PrimarySymptom(
          name: 'Estado afectivo',
          specifiers: ['Ansiedad aguda', 'Apatia', 'Irritabilidad'],
        ),
      ],
      otherSymptoms: [
        'Hormigueo en extremidades',
        'Vision borrosa',
        'Perdida de equilibrio',
      ],
    ),
    _SystemData(
      name: 'Cardiovascular',
      icon: Icons.favorite_border,
      primarySymptoms: [
        _PrimarySymptom(
          name: 'Palpitaciones',
          specifiers: ['Ritmo rapido', 'Salto en el latido', 'Fuertes'],
        ),
        _PrimarySymptom(
          name: 'Dolor precordial',
          specifiers: [
            'Opresion',
            'Irradiado al brazo izquierdo',
            'Irradiado a la mandibula',
          ],
        ),
        _PrimarySymptom(
          name: 'Circulacion',
          specifiers: [
            'Pies hinchados (Edema)',
            'Manos frias',
            'Coloracion azulada',
          ],
        ),
      ],
      otherSymptoms: [],
    ),
    _SystemData(
      name: 'Digestivo',
      icon: Icons.local_pizza_outlined,
      primarySymptoms: [
        _PrimarySymptom(
          name: 'Dolor abdominal',
          specifiers: ['Colico', 'Ardor', 'Pesadez'],
        ),
        _PrimarySymptom(
          name: 'Nauseas / Vomitos',
          specifiers: ['Frecuencia', 'Contenido (bilis, comida, sangre)'],
        ),
        _PrimarySymptom(
          name: 'Transito',
          specifiers: ['Estrenimiento', 'Diarrea', 'Acidez'],
        ),
      ],
      otherSymptoms: ['Falta de apetito', 'Hinchazon'],
    ),
    _SystemData(
      name: 'Musculo-Esqueletico',
      icon: Icons.accessibility_new_outlined,
      primarySymptoms: [
        _PrimarySymptom(
          name: 'Localizacion',
          specifiers: ['Espalda', 'Cuello', 'Articulaciones', 'Musculos'],
        ),
        _PrimarySymptom(
          name: 'Tipo de dolor',
          specifiers: ['Punzado', 'Inflamacion', 'Rigidez matutina'],
        ),
        _PrimarySymptom(
          name: 'Limitacion',
          specifiers: ['Dificultad para moverse', 'Perdida de fuerza'],
        ),
      ],
      otherSymptoms: [],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SISTEMAS DE SINTOMAS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: SaluteColors.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        ..._systems.map(
              (sys) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SystemAccordion(
              system: sys,
              isExpanded: expandedSystems.contains(sys.name),
              selectedSymptoms: selectedSymptoms,
              selectedPrimary: selectedPrimaryBySystem[sys.name],
              selectedSpecifierByPrimary: selectedSpecifierByPrimary,
              onToggle: () => onToggleSystem(sys.name),
              onToggleSymptom: onToggleSymptom,
              onTogglePrimarySymptom: (symptomName) =>
                  onTogglePrimarySymptom(sys.name, symptomName),
              onToggleSpecifier: onToggleSpecifier,
            ),
          ),
        ),
      ],
    );
  }
}

class _SystemData {
  final String name;
  final IconData icon;
  final List<_PrimarySymptom> primarySymptoms;
  final List<String> otherSymptoms;

  const _SystemData({
    required this.name,
    required this.icon,
    required this.primarySymptoms,
    required this.otherSymptoms,
  });
}

class _PrimarySymptom {
  final String name;
  final List<String> specifiers;

  const _PrimarySymptom({required this.name, required this.specifiers});
}

class _SystemAccordion extends StatelessWidget {
  final _SystemData system;
  final bool isExpanded;
  final Set<String> selectedSymptoms;
  final String? selectedPrimary;
  final Map<String, String> selectedSpecifierByPrimary;
  final VoidCallback onToggle;
  final ValueChanged<String> onToggleSymptom;
  final ValueChanged<String> onTogglePrimarySymptom;
  final void Function(String symptomName, String specifier) onToggleSpecifier;

  const _SystemAccordion({
    required this.system,
    required this.isExpanded,
    required this.selectedSymptoms,
    required this.selectedPrimary,
    required this.selectedSpecifierByPrimary,
    required this.onToggle,
    required this.onToggleSymptom,
    required this.onTogglePrimarySymptom,
    required this.onToggleSpecifier,
  });

  @override
  Widget build(BuildContext context) {
    final selectedPrimarySymptom = system.primarySymptoms.firstWhere(
          (s) => s.name == selectedPrimary,
      orElse: () => const _PrimarySymptom(name: '', specifiers: []),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: SaluteColors.lightGreen,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      system.icon,
                      color: SaluteColors.primaryGreen,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      system.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: SaluteColors.textMuted,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: isExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sintomas principales',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: SaluteColors.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: system.primarySymptoms
                        .map(
                          (s) => _SymptomChip(
                        label: s.name,
                        selected: selectedPrimary == s.name,
                        onTap: () => onTogglePrimarySymptom(s.name),
                      ),
                    )
                        .toList(),
                  ),
                  if (selectedPrimarySymptom.name.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Especificadores tecnicos',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SaluteColors.textMuted,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: selectedPrimarySymptom.specifiers
                          .map(
                            (specifier) => _SymptomChip(
                          label: specifier,
                          selected:
                          selectedSpecifierByPrimary[selectedPrimarySymptom
                              .name] ==
                              specifier,
                          onTap: () => onToggleSpecifier(
                            selectedPrimarySymptom.name,
                            specifier,
                          ),
                        ),
                      )
                          .toList(),
                    ),
                  ],
                  if (system.otherSymptoms.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Otros',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SaluteColors.textMuted,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: system.otherSymptoms
                          .map(
                            (s) => _SymptomChip(
                          label: s,
                          selected: selectedSymptoms.contains(s),
                          onTap: () => onToggleSymptom(s),
                        ),
                      )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SymptomChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SymptomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? SaluteColors.lightGreen : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? SaluteColors.primaryGreen.withValues(alpha: 0.3)
                  : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14,
                color: selected
                    ? SaluteColors.primaryGreen
                    : SaluteColors.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? SaluteColors.primaryGreen
                        : Colors.black87,
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

class _SOAPSection extends StatelessWidget {
  final int triajeLevel;
  final double evaDolor;
  final TextEditingController subjectiveCtrl;
  final TextEditingController objectiveCtrl;
  final TextEditingController assessmentCtrl;
  final TextEditingController planCtrl;

  const _SOAPSection({
    required this.triajeLevel,
    required this.evaDolor,
    required this.subjectiveCtrl,
    required this.objectiveCtrl,
    required this.assessmentCtrl,
    required this.planCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Text(
                'Registro Clinico SOAP\nEvolutivo',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: SaluteColors.lightGreen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: SaluteColors.primaryGreen,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'EN CURSO',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: SaluteColors.primaryGreen,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _SoapTagChip(label: '🌀 Mareo'),
            _SoapTagChip(label: '🤢 Nauseas'),
            _SoapTagChip(label: '😴 Fatiga'),
          ],
        ),
        const SizedBox(height: 16),
        _SOAPField(
          label: 'S (SUBJETIVO)',
          controller: subjectiveCtrl,
          hint:
          'Que siente el usuario? Texto libre o etiquetas: mareo, nauseas, fatiga.',
          icon: Icons.sentiment_satisfied_alt_outlined,
        ),
        const SizedBox(height: 14),
        _SOAPField(
          label: 'O (OBJETIVO)',
          controller: objectiveCtrl,
          hint: 'Datos medibles observados (vitales, EVA, signos).',
          icon: Icons.assessment_outlined,
        ),
        const SizedBox(height: 14),
        _SOAPField(
          label: 'A (APRECIACION)',
          controller: assessmentCtrl,
          hint:
          'Como evoluciono? Ej: Mejor que ayer / Empeoro despues de comer.',
          icon: Icons.trending_up_outlined,
        ),
        const SizedBox(height: 14),
        _SOAPField(
          label: 'P (PLAN)',
          controller: planCtrl,
          hint: 'Accion tomada. Ej: Tome paracetamol / Reposo.',
          icon: Icons.assignment_outlined,
        ),
      ],
    );
  }
}

class _SoapTagChip extends StatelessWidget {
  final String label;

  const _SoapTagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SaluteColors.lightGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: SaluteColors.primaryGreen,
        ),
      ),
    );
  }
}

class _SOAPField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData? icon;

  const _SOAPField({
    required this.label,
    required this.controller,
    required this.hint,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: SaluteColors.primaryGreen),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: SaluteColors.primaryGreen,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 3,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          decoration: InputDecoration(
            hintText: hint,
            // Dictado por voz: describir síntomas hablando es más fácil.
            suffixIcon: Align(
              alignment: Alignment.topRight,
              widthFactor: 1,
              heightFactor: 1,
              child: DictationButton(controller: controller),
            ),
            hintStyle: TextStyle(
              color: SaluteColors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
            filled: true,
            fillColor: const Color(0xFFF0F5F0),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: SaluteColors.primaryGreen.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SecurityFooter extends StatelessWidget {
  const _SecurityFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: SaluteColors.lightGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield,
              color: SaluteColors.primaryGreen,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  color: SaluteColors.textMuted,
                  height: 1.5,
                ),
                children: const [
                  TextSpan(text: 'Esta sesion esta protegida con '),
                  TextSpan(
                    text: 'cifrado de extremo a extremo',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  TextSpan(
                    text:
                    '. Los datos clinicos solo son visibles para personal autorizado. ',
                  ),
                  TextSpan(
                    text: 'Ver certificado de seguridad.',
                    style: TextStyle(
                      color: SaluteColors.primaryGreen,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int triageLevel;
  final bool saving;
  final VoidCallback onSavePrivateDiary;
  final VoidCallback onGenerateGuardSheet;
  final VoidCallback onGoToGuardMap;

  const _BottomBar({
    required this.triageLevel,
    required this.saving,
    required this.onSavePrivateDiary,
    required this.onGenerateGuardSheet,
    required this.onGoToGuardMap,
  });

  @override
  Widget build(BuildContext context) {
    final isCodeRed = triageLevel == 1;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: double.infinity,
              minHeight: 52,
            ),
            child: FilledButton.icon(
              onPressed: saving ? null : onSavePrivateDiary,
              icon: saving
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.lock_outline),
              style: FilledButton.styleFrom(
                backgroundColor: SaluteColors.primaryGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              label: Text(
                saving ? 'GUARDANDO...' : 'GUARDAR EN DIARIO PRIVADO',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (triageLevel != 3)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onGenerateGuardSheet,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('GENERAR FICHA PARA GUARDIA'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (isCodeRed) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onGoToGuardMap,
                      icon: const Icon(Icons.local_hospital_outlined),
                      label: const Text('IR A MAPA DE GUARDIAS'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        backgroundColor: const Color(0xFFCC2929),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}