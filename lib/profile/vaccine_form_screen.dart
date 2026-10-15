import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/vaccine_record.dart';
import 'package:saluteapp/core/services/person_vaccine_catalog.dart';
import 'package:saluteapp/core/services/vaccine_catalog.dart';
import 'package:saluteapp/core/services/vaccine_service.dart';
import 'package:saluteapp/profile/vaccine_widgets.dart';

/// Alta / edición de UNA dosis del carné.
///
/// Tres usos:
///  - alta manual: sin [existing] ni [draft].
///  - edición: con [existing] (guarda con `VaccineService.update`).
///  - revisión de una dosis leída por OCR (o una fila del esquema sin
///    registro): con [draft] y `returnDraft: true`, NO guarda nada, solo
///    devuelve el [VaccineDraft] corregido a quien lo abrió.
class VaccineFormScreen extends StatefulWidget {
  final FamilyProfile profile;
  final VaccineRecord? existing;
  final VaccineDraft? draft;
  final bool returnDraft;
  final List<VaccineRecord>? existingRecords;

  const VaccineFormScreen({
    super.key,
    required this.profile,
    this.existing,
    this.draft,
    this.returnDraft = false,
    this.existingRecords,
  });

  @override
  State<VaccineFormScreen> createState() => _VaccineFormScreenState();
}

class _VaccineFormScreenState extends State<VaccineFormScreen> {
  final _nameCtrl = TextEditingController();
  final _vetCtrl = TextEditingController();
  final _lotCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _date;
  DateTime? _next;
  bool _nextTouched = false;
  bool _nextSuggested = false;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  bool get _isPet => widget.profile.type == ProfileType.mascota;

  /// Fecha más antigua que se puede elegir: las personas pueden tener dosis de
  /// décadas atrás (libreta de la infancia), así que el piso es su nacimiento.
  DateTime get _minDate => _isPet ? DateTime(2000) : (widget.profile.birthDate ?? DateTime(1930));

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final VaccineDraft? d = e != null ? VaccineDraft.fromRecord(e) : widget.draft;
    if (d != null) {
      _nameCtrl.text = d.name;
      _vetCtrl.text = d.professional;
      _lotCtrl.text = d.lot;
      _notesCtrl.text = d.notes;
      _date = d.date;
      _next = d.nextDoseDate;
      // Si ya venía con próxima dosis, no se la pisa con sugerencias.
      _nextTouched = d.nextDoseDate != null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _vetCtrl.dispose();
    _lotCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _msg(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// `showDatePicker` lanza una excepción si `initialDate` queda fuera de
  /// [first, last] (pasa con registros viejos de fechas contradictorias).
  DateTime _clamp(DateTime d, DateTime first, DateTime last) =>
      d.isBefore(first) ? first : (d.isAfter(last) ? last : d);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = _minDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: _clamp(_date ?? now, first, now),
      firstDate: first,
      lastDate: now,
    );
    if (picked == null) return;
    setState(() => _date = picked);
    _maybeSuggestNext();
  }

  Future<void> _pickNext() async {
    final now = DateTime.now();
    final first = _date ?? _minDate;
    final last = DateTime(now.year + 20); // p. ej. refuerzo de los 11 años de un bebé
    final base = _next ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _clamp(base.isBefore(now) ? now : base, first, last),
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    setState(() {
      _next = picked;
      _nextTouched = true;
      _nextSuggested = false;
    });
  }

  /// Sugiere el refuerzo habitual de la plantilla, SOLO si todavía no
  /// hay próxima dosis y el usuario no tocó el campo. Es editable y se
  /// avisa que hay que confirmarlo con el veterinario.
  void _maybeSuggestNext() {
    if (_nextTouched || _isEditing || _date == null) return;
    final suggested = _isPet
        ? VaccineCatalog.suggestedNextDose(_nameCtrl.text, _date!)
        : PersonVaccines.suggestedNextDose(
            name: _nameCtrl.text,
            appliedOn: _date!,
            birthDate: widget.profile.birthDate,
            records: widget.existingRecords ?? const [],
          );
    setState(() {
      _next = suggested;
      _nextSuggested = suggested != null;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return _msg('Poné el nombre de la vacuna.');
    if (_date == null) return _msg('Elegí la fecha en que se aplicó.');
    if (_next != null && !_next!.isAfter(_date!)) {
      return _msg('La próxima dosis tiene que ser posterior a la fecha de aplicación.');
    }

    final draft = VaccineDraft(
      name: name,
      date: _date,
      nextDoseDate: _next,
      professional: _vetCtrl.text.trim(),
      lot: _lotCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      source: widget.existing?.source ?? widget.draft?.source ?? VaccineSource.manual,
    );

    if (widget.returnDraft) {
      Navigator.of(context).pop(draft);
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final old = widget.existing;
      final record = VaccineRecord(
        id: old?.id ?? '',
        name: draft.name,
        date: draft.date!,
        nextDoseDate: draft.nextDoseDate,
        professional: draft.professional,
        source: draft.source,
        agendaEventId: old?.agendaEventId,
        lot: draft.lot,
        notes: draft.notes,
        attachment: old?.attachment,
        ocrText: old?.ocrText ?? '',
      );
      final result = old != null
          ? await VaccineService.instance.update(widget.profile, record)
          : await VaccineService.instance.add(
              widget.profile,
              record,
              existing: widget.existingRecords,
            );
      messenger.showSnackBar(SnackBar(content: Text(_savedMessage(result.reminderCreated))));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _msg('No se pudo guardar la vacuna: $e');
    }
  }

  String _savedMessage(bool? reminder) {
    if (reminder == true) return 'Vacuna guardada. Te vamos a avisar de la próxima dosis.';
    if (reminder == false) {
      return 'Vacuna guardada, pero no se pudo crear el recordatorio en la agenda.';
    }
    return 'Vacuna guardada.';
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _isPet
        ? [
            for (final t in VaccineCatalog.forSpecies(petSpeciesFrom(widget.profile.species))) ...t.suggestions,
          ]
        : PersonVaccines.suggestionsFor(widget.profile.birthDate, DateTime.now());

    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      appBar: AppBar(
        backgroundColor: SaluteColors.bgColor,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(_isEditing ? 'Editar vacuna' : 'Vacuna · ${widget.profile.name}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const VaccineLabel('Vacuna'),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: vaccineInputDecoration(_isPet ? 'Ej: Antirrábica' : 'Ej: Triple viral'),
              onChanged: (_) => setState(() {}),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in suggestions)
                    ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey.shade300),
                      onPressed: () {
                        _nameCtrl.text = s;
                        _maybeSuggestNext();
                        setState(() {});
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            const VaccineLabel('Fecha de aplicación'),
            VaccineDateField(value: _date, placeholder: 'Elegir fecha', onTap: _pickDate),
            const SizedBox(height: 18),
            const VaccineLabel('Próxima dosis (opcional)'),
            VaccineDateField(
              value: _next,
              placeholder: 'Sin próxima dosis',
              onTap: _pickNext,
              onClear: () => setState(() {
                _next = null;
                _nextTouched = true;
                _nextSuggested = false;
              }),
            ),
            if (_nextSuggested)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _isPet
                      ? 'Fecha sugerida según el refuerzo habitual. Confirmala con tu veterinario: '
                          'puede cambiar según la edad y el esquema de ${widget.profile.name}.'
                      : 'Fecha sugerida según el Calendario Nacional. Confirmala con tu médico o en el '
                          'vacunatorio: puede cambiar según los antecedentes y el esquema de ${widget.profile.name}.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            if (_next != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active_outlined, size: 16, color: SaluteColors.primaryGreen),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Se agrega a la agenda con aviso.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            VaccineLabel(_isPet ? 'Veterinario (opcional)' : 'Profesional o vacunatorio (opcional)'),
            TextField(
              controller: _vetCtrl,
              decoration: vaccineInputDecoration(_isPet ? 'Ej: Dra. Gómez' : 'Ej: Dra. Gómez o Vacunatorio central'),
            ),
            const SizedBox(height: 18),
            const VaccineLabel('Lote (opcional)'),
            TextField(controller: _lotCtrl, decoration: vaccineInputDecoration('Ej: A1234')),
            const SizedBox(height: 18),
            const VaccineLabel('Notas (opcional)'),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: vaccineInputDecoration(
                _isPet ? 'Reacciones, indicaciones del veterinario...' : 'Reacciones, indicaciones del médico...',
              ),
            ),
            const SizedBox(height: 28),
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
                        widget.returnDraft ? 'LISTO' : 'GUARDAR VACUNA',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
