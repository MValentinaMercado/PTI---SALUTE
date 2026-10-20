import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/agenda_event.dart';
import 'package:saluteapp/core/services/agenda_service.dart';

/// Alta rápida de un turno/estudio/vacuna/control para un perfil,
/// que va a aparecer en la agenda familiar y en las alertas de su perfil.
/// Con [existing] la misma pantalla edita un evento ya cargado.
class AgendaEventFormScreen extends StatefulWidget {
  final String profileId;
  final String profileName;
  final AgendaEvent? existing;

  const AgendaEventFormScreen({
    super.key,
    required this.profileId,
    required this.profileName,
    this.existing,
  });

  /// Textos de las opciones de alarma (se reusan en el detalle del evento).
  static const reminderLabels = <int?, String>{
    null: 'Sin alarma',
    15: '15 min antes',
    60: '1 hora antes',
    180: '3 horas antes',
    1440: '1 día antes',
  };

  @override
  State<AgendaEventFormScreen> createState() => _AgendaEventFormScreenState();
}

class _AgendaEventFormScreenState extends State<AgendaEventFormScreen> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  AgendaEventType _type = AgendaEventType.turno;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  int? _reminderMinutesBefore;
  AgendaEventStatus _status = AgendaEventStatus.pendiente;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleController.text = e.title;
      _locationController.text = e.location;
      _type = e.type;
      _date = DateTime(e.date.year, e.date.month, e.date.day);
      _time = TimeOfDay(hour: e.date.hour, minute: e.date.minute);
      _reminderMinutesBefore = e.reminderMinutesBefore;
      _status = e.status;
    }
  }

  static const _typeLabels = {
    AgendaEventType.turno: 'Turno',
    AgendaEventType.estudio: 'Estudio',
    AgendaEventType.vacuna: 'Vacuna',
    AgendaEventType.control: 'Control',
  };

  /// Tipos elegibles. Al editar un evento de un tipo que no se ofrece para
  /// cargar nuevos (ej. medicación), se muestra también para no perderlo.
  Map<AgendaEventType, String> get _typeChoices => {
        ..._typeLabels,
        if (!_typeLabels.containsKey(_type)) _type: _type == AgendaEventType.medicacion ? 'Medicación' : 'Otro',
      };

  static const _reminderOptions = AgendaEventFormScreen.reminderLabels;

  static const _statusLabels = {
    AgendaEventStatus.pendiente: 'Pendiente',
    AgendaEventStatus.completado: 'Completado',
    AgendaEventStatus.cancelado: 'Cancelado',
  };

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _isEditing && _date.isBefore(DateTime.now())
          ? _date
          : DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresá un título, ej: Control anual.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final fullDate = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
      final existing = widget.existing;
      final event = AgendaEvent(
        id: existing?.id ?? '',
        ownerUid: existing?.ownerUid ?? '',
        profileId: widget.profileId,
        profileName: widget.profileName,
        type: _type,
        status: _status,
        title: title,
        location: _locationController.text.trim(),
        date: fullDate,
        reminderMinutesBefore: _reminderMinutesBefore,
      );
      if (existing != null) {
        await AgendaService.instance.updateEvent(event);
      } else {
        await AgendaService.instance.addEvent(event);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo guardar. Intentá de nuevo.')));
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
        title: Text('${_isEditing ? 'Editar evento' : 'Nuevo evento'} · ${widget.profileName}'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('TIPO'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _typeChoices.entries.map((entry) {
                  final selected = _type == entry.key;
                  return ChoiceChip(
                    label: Text(entry.value),
                    selected: selected,
                    onSelected: (_) => setState(() => _type = entry.key),
                    selectedColor: SaluteColors.primaryGreen,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(color: selected ? SaluteColors.primaryGreen : Colors.grey[300]!),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              const _FieldLabel('TÍTULO'),
              const SizedBox(height: 10),
              _textField(_titleController, hint: 'Ej: Control con clínico'),
              const SizedBox(height: 20),
              const _FieldLabel('LUGAR (OPCIONAL)'),
              const SizedBox(height: 10),
              _textField(_locationController, hint: 'Ej: Hospital Italiano'),
              const SizedBox(height: 20),
              const _FieldLabel('FECHA Y HORA'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _pickerTile(icon: Icons.calendar_today_outlined, label: '${_date.day}/${_date.month}/${_date.year}', onTap: _pickDate)),
                  const SizedBox(width: 12),
                  Expanded(child: _pickerTile(icon: Icons.access_time, label: _time.format(context), onTap: _pickTime)),
                ],
              ),
              const SizedBox(height: 20),
              if (_isEditing) ...[
                const _FieldLabel('ESTADO'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _statusLabels.entries.map((entry) {
                    final selected = _status == entry.key;
                    return ChoiceChip(
                      label: Text(entry.value),
                      selected: selected,
                      onSelected: (_) => setState(() => _status = entry.key),
                      selectedColor: SaluteColors.primaryGreen,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(color: selected ? SaluteColors.primaryGreen : Colors.grey[300]!),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
              ],
              const _FieldLabel('CONFIGURAR ALARMA'),
              const SizedBox(height: 4),
              Text(
                'Te llega como notificación al celular, aunque tengas la app cerrada.',
                style: TextStyle(fontSize: 12, color: SaluteColors.textMuted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _reminderOptions.entries.map((entry) {
                  final selected = _reminderMinutesBefore == entry.key;
                  return ChoiceChip(
                    label: Text(entry.value),
                    selected: selected,
                    onSelected: (_) => setState(() => _reminderMinutesBefore = entry.key),
                    selectedColor: SaluteColors.primaryGreen,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(color: selected ? SaluteColors.primaryGreen : Colors.grey[300]!),
                  );
                }).toList(),
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

  Widget _pickerTile({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: SaluteColors.textMuted),
            const SizedBox(width: 10),
            Flexible(child: Text(label, style: const TextStyle(color: Colors.black87, fontSize: 15))),
          ],
        ),
      ),
    );
  }

  Widget _textField(TextEditingController controller, {required String hint}) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: SaluteColors.textMuted, fontSize: 15),
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
    return ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 56), child: FilledButton(
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
            : Text(_isEditing ? 'Guardar cambios' : 'Agregar a la agenda', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
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
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: SaluteColors.primaryGreen,
        letterSpacing: 1,
      ),
    );
  }
}