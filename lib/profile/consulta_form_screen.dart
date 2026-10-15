import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/medical_record.dart';
import 'package:saluteapp/core/services/medical_record_service.dart';

/// Claves de `details` (se guardan CIFRADAS, ver MedicalRecordService).
/// Públicas porque `ConsultasScreen` las usa para mostrar el detalle.
const String kConsultaDiagnosisKey = 'diagnostico';
const String kConsultaTreatmentKey = 'indicaciones';
const String kConsultaNotesKey = 'notas';

/// Alta / edición de una consulta (veterinaria si el perfil es una mascota).
///
/// Es un `MedicalRecord` con `category: consulta`, misma infraestructura que
/// las órdenes (`OrderFormScreen`), Triaje o Ánimo. Va siempre como
/// `completado`: se registra algo que ya pasó. Lo no sensible (fecha, motivo,
/// profesional, clínica) queda en claro para poder listar y para la ficha;
/// diagnóstico, indicaciones y notas van cifrados dentro de `details`.
///
/// Con [record] edita esa consulta; sin él, crea una nueva. Hace `pop(true)`
/// si guardó algo.
class ConsultaFormScreen extends StatefulWidget {
  final String profileId;
  final String profileName;
  final bool isPet;
  final MedicalRecord? record;

  const ConsultaFormScreen({
    super.key,
    required this.profileId,
    required this.profileName,
    this.isPet = false,
    this.record,
  });

  @override
  State<ConsultaFormScreen> createState() => _ConsultaFormScreenState();
}

class _ConsultaFormScreenState extends State<ConsultaFormScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _professionalCtrl;
  late final TextEditingController _institutionCtrl;
  late final TextEditingController _diagnosisCtrl;
  late final TextEditingController _treatmentCtrl;
  late final TextEditingController _notesCtrl;
  late DateTime _date;
  bool _saving = false;

  bool get _isEditing => widget.record != null;
  String get _proLabel => widget.isPet ? 'Veterinario/a' : 'Médico/a';
  String get _placeLabel => widget.isPet ? 'Clínica veterinaria' : 'Institución';

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _titleCtrl = TextEditingController(text: r?.title ?? '');
    _professionalCtrl = TextEditingController(text: r?.professional ?? '');
    _institutionCtrl = TextEditingController(text: r?.institution ?? '');
    _diagnosisCtrl = TextEditingController(text: (r?.details[kConsultaDiagnosisKey] as String?) ?? '');
    _treatmentCtrl = TextEditingController(text: (r?.details[kConsultaTreatmentKey] as String?) ?? '');
    _notesCtrl = TextEditingController(text: (r?.details[kConsultaNotesKey] as String?) ?? '');
    _date = r?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _professionalCtrl.dispose();
    _institutionCtrl.dispose();
    _diagnosisCtrl.dispose();
    _treatmentCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(now.year - 30),
      // Se registra algo que ya pasó. Lo futuro va en la Agenda.
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poné el motivo de la consulta (ej: "Control anual").')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      // Parte de lo que ya tenía el registro, por si guarda otras claves
      // (así editar no pisa datos que esta pantalla no conoce).
      final details = Map<String, dynamic>.of(widget.record?.details ?? const <String, dynamic>{});
      void put(String key, String value) {
        final v = value.trim();
        if (v.isEmpty) {
          details.remove(key);
        } else {
          details[key] = v;
        }
      }

      put(kConsultaDiagnosisKey, _diagnosisCtrl.text);
      put(kConsultaTreatmentKey, _treatmentCtrl.text);
      put(kConsultaNotesKey, _notesCtrl.text);

      final record = MedicalRecord(
        id: widget.record?.id ?? '',
        category: RecordCategory.consulta,
        date: _date,
        title: _titleCtrl.text.trim(),
        professional: _professionalCtrl.text.trim(),
        institution: _institutionCtrl.text.trim(),
        status: widget.record?.status ?? RecordStatus.completado,
        details: details,
      );

      if (_isEditing) {
        await MedicalRecordService.instance.updateRecord(widget.profileId, record);
      } else {
        await MedicalRecordService.instance.addRecord(widget.profileId, record);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la consulta: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      appBar: AppBar(
        backgroundColor: SaluteColors.bgColor,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(_isEditing ? 'Editar consulta · ${widget.profileName}' : 'Nueva consulta · ${widget.profileName}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const _Label('Motivo'),
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration(widget.isPet ? 'Ej: Control anual, vómitos, castración' : 'Ej: Control anual'),
            ),
            const SizedBox(height: 18),
            const _Label('Fecha'),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 18, color: SaluteColors.primaryGreen),
                    const SizedBox(width: 10),
                    Text(
                      '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _Label('$_proLabel (opcional)'),
            TextField(
              controller: _professionalCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration(widget.isPet ? 'Ej: Dra. Fontana' : 'Ej: Dr. Fontana'),
            ),
            const SizedBox(height: 18),
            _Label('$_placeLabel (opcional)'),
            TextField(
              controller: _institutionCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration(widget.isPet ? 'Ej: Veterinaria del Parque' : 'Ej: Clínica Central'),
            ),
            const SizedBox(height: 18),
            const _Label('Diagnóstico (opcional)'),
            _multiline(_diagnosisCtrl, 'Qué encontró o concluyó'),
            const SizedBox(height: 18),
            const _Label('Tratamiento / indicaciones (opcional)'),
            _multiline(_treatmentCtrl, 'Medicación, dieta, cuidados, próximos controles'),
            const SizedBox(height: 18),
            const _Label('Notas (opcional)'),
            _multiline(_notesCtrl, 'Cualquier otra cosa que quieras recordar'),
            const SizedBox(height: 8),
            Text(
              'El diagnóstico, las indicaciones y las notas se guardan cifrados.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SaluteColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text(
                        _isEditing ? 'GUARDAR CAMBIOS' : 'GUARDAR CONSULTA',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _multiline(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      minLines: 2,
      maxLines: 6,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      decoration: _decoration(hint),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SaluteColors.primaryGreen, width: 1.5),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
      ),
    );
  }
}
