import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/medicine_item.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/services/local_alarm_service.dart';
import 'package:saluteapp/core/services/medication_botiquin_link.dart';
import 'package:saluteapp/core/services/medication_reminder_service.dart';
import 'package:saluteapp/core/services/medication_service.dart';
import 'package:saluteapp/core/services/medicine_item_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';

/// Duraciones típicas de un tratamiento con fecha de fin.
const _quickDurations = [3, 5, 7, 10, 14, 21, 30];

/// Alta o edición de una medicación para un perfil puntual.
/// Si [existingMedication] viene null, es alta; si viene con valor, edita.
///
/// [profileName] es opcional: se usa para el texto de las alertas
/// ("Juana · 1 comprimido"). Si no viene, se busca por [profileId].
class MedicationFormScreen extends StatefulWidget {
  final String profileId;
  final String? profileName;
  final Medication? existingMedication;

  const MedicationFormScreen({
    super.key,
    required this.profileId,
    this.profileName,
    this.existingMedication,
  });

  @override
  State<MedicationFormScreen> createState() => _MedicationFormScreenState();
}

class _MedicationFormScreenState extends State<MedicationFormScreen> {
  final _nameController = TextEditingController();
  final _doseController = TextEditingController();
  final _notesController = TextEditingController();
  final List<TimeOfDay> _times = [];
  DateTime _startDate = DateTime.now();
  bool _isChronic = true;
  int _durationDays = 7;
  bool _remindersEnabled = true;
  int _unitsPerDose = 1;
  String? _linkedItemId;
  List<MedicineItem> _botiquin = const [];
  bool _saving = false;

  bool get _isEditing => widget.existingMedication != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existingMedication;
    if (m != null) {
      _nameController.text = m.name;
      _doseController.text = m.dose;
      _notesController.text = m.notes;
      _startDate = m.startDate;
      _isChronic = m.durationDays == null;
      _durationDays = m.durationDays ?? 7;
      _remindersEnabled = m.remindersEnabled;
      _unitsPerDose = m.unitsPerDose;
      _linkedItemId = m.botiquinItemId;
      for (final t in m.timesOfDay) {
        final hm = parseTimeOfDay(t);
        if (hm != null) _times.add(TimeOfDay(hour: hm.$1, minute: hm.$2));
      }
    }
    _loadBotiquin();
  }

  Future<void> _loadBotiquin() async {
    try {
      final items = await MedicineItemService.instance.watchAll().first;
      if (mounted) setState(() => _botiquin = items);
    } catch (_) {
      // Sin botiquín simplemente no se ofrece vincular; no bloquea el form.
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _doseController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null && !_times.any((t) => t.hour == picked.hour && t.minute == picked.minute)) {
      setState(() => _times.add(picked));
    }
  }

  /// Atajo "cada N horas": arma los horarios a partir del primero ya
  /// cargado (o las 08:00) y reemplaza los actuales.
  void _applyEveryHours(int hours) {
    final first = _times.isNotEmpty
        ? ([..._times]..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute))).first
        : const TimeOfDay(hour: 8, minute: 0);
    final startMinutes = first.hour * 60 + first.minute;
    final result = <TimeOfDay>[];
    for (var minutes = startMinutes; minutes < startMinutes + 24 * 60; minutes += hours * 60) {
      final m = minutes % (24 * 60);
      result.add(TimeOfDay(hour: m ~/ 60, minute: m % 60));
    }
    setState(() {
      _times
        ..clear()
        ..addAll(result);
    });
  }

  String _formatTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Ingresá el nombre de la medicación.');
      return;
    }
    final dose = _doseController.text.trim();
    if (dose.isEmpty) {
      _showMessage('Ingresá la dosis (ej: 1 comprimido).');
      return;
    }

    setState(() => _saving = true);
    try {
      final sortedTimes = [..._times]..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
      final linkedExists = _botiquin.any((i) => i.id == _linkedItemId);
      var medication = Medication(
        id: widget.existingMedication?.id ?? '',
        name: name,
        dose: dose,
        timesOfDay: sortedTimes.map(_formatTime).toList(),
        // Solo la fecha: el tratamiento arranca a las 00:00 de ese día.
        startDate: DateTime(_startDate.year, _startDate.month, _startDate.day),
        durationDays: _isChronic ? null : _durationDays,
        // Editar no debe reactivar una medicación que estaba pausada.
        active: widget.existingMedication?.active ?? true,
        notes: _notesController.text.trim(),
        remindersEnabled: _remindersEnabled,
        unitsPerDose: _unitsPerDose,
        botiquinItemId: linkedExists ? _linkedItemId : null,
      );
      if (_isEditing) {
        await MedicationService.instance.updateMedication(widget.profileId, medication);
      } else {
        final newId = await MedicationService.instance.addMedication(widget.profileId, medication);
        medication = medication.copyWith(id: newId);
      }

      // Alertas: si falla, la medicación ya quedó guardada; se avisa
      // pero no se pierde el alta.
      var alertsFailed = false;
      try {
        final profileName = widget.profileName ??
            (await ProfileService.instance.getProfile(widget.profileId))?.name ??
            '';
        await MedicationReminderService.instance.scheduleFor(
          profileId: widget.profileId,
          profileName: profileName,
          medication: medication,
        );
      } catch (_) {
        alertsFailed = true;
      }

      final notificationsOff = medication.remindersEnabled &&
          medication.timesOfDay.isNotEmpty &&
          !await LocalAlarmService.instance.notificationsAllowed();

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      if (alertsFailed) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Se guardó la medicación, pero no se pudieron programar las alertas.'),
        ));
      } else if (notificationsOff) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Se guardó, pero las notificaciones están desactivadas en el teléfono: no vas a recibir las alertas.'),
        ));
      }
    } catch (_) {
      _showMessage('No se pudo guardar. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar medicación'),
        content: Text('¿Seguro que querés eliminar "${widget.existingMedication!.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await MedicationService.instance.deleteMedication(widget.profileId, widget.existingMedication!.id);
      // Sin esto, las alertas ya programadas seguirían sonando.
      await MedicationReminderService.instance.cancelFor(widget.existingMedication!.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      _showMessage('No se pudo eliminar. Intentá de nuevo.');
      setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      appBar: AppBar(
        backgroundColor: SaluteColors.bgColor,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(_isEditing ? 'Editar medicación' : 'Nueva medicación'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('NOMBRE DE LA MEDICACIÓN'),
              const SizedBox(height: 10),
              _textField(_nameController, hint: 'Ej: Losartán', onChanged: (_) => setState(() {})),
              const SizedBox(height: 20),
              const _FieldLabel('DOSIS'),
              const SizedBox(height: 10),
              _textField(_doseController, hint: 'Ej: 1 comprimido, 10 ml'),
              const SizedBox(height: 20),
              const _FieldLabel('HORARIOS DE TOMA'),
              const SizedBox(height: 10),
              _buildTimesPicker(),
              const SizedBox(height: 12),
              _buildFrequencyShortcuts(),
              const SizedBox(height: 8),
              _buildRemindersSwitch(),
              const SizedBox(height: 12),
              const _FieldLabel('FECHA DE INICIO'),
              const SizedBox(height: 10),
              _buildDatePicker(),
              const SizedBox(height: 20),
              const _FieldLabel('DURACIÓN DEL TRATAMIENTO'),
              const SizedBox(height: 10),
              _buildDurationSelector(),
              const SizedBox(height: 20),
              const _FieldLabel('MI BOTIQUÍN'),
              const SizedBox(height: 10),
              _buildBotiquinSection(),
              const SizedBox(height: 20),
              const _FieldLabel('INDICACIONES (OPCIONAL)'),
              const SizedBox(height: 10),
              _textField(_notesController, hint: 'Indicaciones del médico, motivo…', maxLines: 3),
              const SizedBox(height: 8),
              Text(
                'Este campo se guarda cifrado en el dispositivo.',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 32),
              _buildSaveButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimesPicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (int i = 0; i < _times.length; i++)
          Chip(
            label: Text(_formatTime(_times[i]), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            backgroundColor: SaluteColors.primaryGreen,
            deleteIconColor: Colors.white70,
            onDeleted: () => setState(() => _times.removeAt(i)),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18, color: SaluteColors.primaryGreen),
          label: const Text('Agregar horario', style: TextStyle(color: SaluteColors.primaryGreen, fontWeight: FontWeight.w600)),
          backgroundColor: SaluteColors.lightGreen.withValues(alpha: 0.4),
          onPressed: _addTime,
        ),
      ],
    );
  }

  Widget _buildFrequencyShortcuts() {
    Widget chip(String label, int hours) => ActionChip(
          label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          backgroundColor: Colors.white,
          side: BorderSide(color: Colors.grey.shade300),
          onPressed: () => _applyEveryHours(hours),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Atajos:', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        chip('1 vez al día', 24),
        chip('Cada 12 h', 12),
        chip('Cada 8 h', 8),
        chip('Cada 6 h', 6),
      ],
    );
  }

  Widget _buildRemindersSwitch() {
    final hasTimes = _times.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: const Text('Avisarme en cada toma', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(
          hasTimes
              ? 'Recibís una alerta en el celular a cada horario.'
              : 'Agregá al menos un horario para recibir alertas.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        value: _remindersEnabled,
        onChanged: (v) => setState(() => _remindersEnabled = v),
      ),
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: _pickStartDate,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey[500]),
            const SizedBox(width: 10),
            Text(_formatDate(_startDate), style: const TextStyle(color: Colors.black87, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationSelector() {
    final startDay = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final lastDay = DateTime(startDay.year, startDay.month, startDay.day + _durationDays - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _durationChip('Crónico / sin fecha de fin', true)),
            const SizedBox(width: 12),
            Expanded(child: _durationChip('Por cantidad de días', false)),
          ],
        ),
        if (_isChronic) ...[
          const SizedBox(height: 8),
          Text(
            'Se repite todos los días hasta que lo pauses o lo elimines.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ] else ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in _quickDurations)
                ChoiceChip(
                  label: Text('$d días'),
                  selected: _durationDays == d,
                  selectedColor: SaluteColors.primaryGreen,
                  labelStyle: TextStyle(
                    color: _durationDays == d ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  onSelected: (_) => setState(() => _durationDays = d),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: _durationDays > 1 ? () => setState(() => _durationDays--) : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: SaluteColors.primaryGreen,
              ),
              Text('$_durationDays días', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: _durationDays < 365 ? () => setState(() => _durationDays++) : null,
                icon: const Icon(Icons.add_circle_outline),
                color: SaluteColors.primaryGreen,
              ),
            ],
          ),
          Text(
            'Última toma: ${_formatDate(lastDay)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ],
    );
  }

  Widget _durationChip(String label, bool value) {
    final selected = _isChronic == value;
    return GestureDetector(
      onTap: () => setState(() => _isChronic = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? SaluteColors.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? SaluteColors.primaryGreen : Colors.grey[300]!),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey[700],
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildBotiquinSection() {
    if (_botiquin.isEmpty) {
      return Text(
        'Todavía no tenés medicamentos en Mi Botiquín. Cuando los cargues vas a poder vincularlos '
        'acá para que el stock se descuente solo al marcar cada toma.',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      );
    }

    final validLinked = _botiquin.any((i) => i.id == _linkedItemId) ? _linkedItemId : null;
    final suggestion = validLinked == null
        ? MedicationBotiquinLink.findMatch(_nameController.text, _botiquin)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: validLinked,
              hint: const Text('Sin vincular'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Sin vincular')),
                for (final i in _botiquin)
                  DropdownMenuItem<String?>(
                    value: i.id,
                    child: Text(
                      '${i.name}${i.dosage.isNotEmpty ? ' · ${i.dosage}' : ''} (${i.currentStock} u.)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _linkedItemId = v),
            ),
          ),
        ),
        if (suggestion != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            decoration: BoxDecoration(
              color: SaluteColors.lightGreen.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 18, color: SaluteColors.primaryGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Encontramos "${suggestion.name}" en tu botiquín.',
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _linkedItemId = suggestion.id),
                  child: const Text('Vincular'),
                ),
              ],
            ),
          ),
        ],
        if (validLinked != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Unidades por toma (se descuentan del botiquín)',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
              IconButton(
                onPressed: _unitsPerDose > 1 ? () => setState(() => _unitsPerDose--) : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: SaluteColors.primaryGreen,
              ),
              Text('$_unitsPerDose', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: _unitsPerDose < 20 ? () => setState(() => _unitsPerDose++) : null,
                icon: const Icon(Icons.add_circle_outline),
                color: SaluteColors.primaryGreen,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _textField(
    TextEditingController controller, {
    required String hint,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SaluteColors.primaryGreen, width: 2),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(
          backgroundColor: SaluteColors.primaryGreen,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _saving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation(Colors.white)),
              )
            : Text(
                _isEditing ? 'Guardar cambios' : 'Agregar medicación',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: SaluteColors.primaryGreen,
        letterSpacing: 1,
      ),
    );
  }
}
