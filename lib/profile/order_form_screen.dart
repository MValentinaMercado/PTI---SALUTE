import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/medical_record.dart';
import 'package:saluteapp/core/services/attachment_service.dart';
import 'package:saluteapp/core/services/medical_record_service.dart';
import 'package:saluteapp/core/services/ocr_service.dart';

/// Alta de una orden médica (estudio, análisis, imagen) para un perfil.
/// Técnicamente crea un `MedicalRecord` más — misma infraestructura que
/// Triaje/Ánimo (ver `MedicalRecordService`), con `category` restringida
/// a los tipos que tienen sentido como "orden": estudio, laboratorio,
/// cardiología. Consultas (`ConsultaFormScreen`), vacunas u odontología
/// tienen sus propias pantallas de carga.
class OrderFormScreen extends StatefulWidget {
  final String profileId;
  final String profileName;

  /// Mascota → el selector ofrece especialidades veterinarias.
  final bool isPet;

  /// Si viene, el formulario edita esa orden en vez de crear una nueva.
  final MedicalRecord? existing;

  const OrderFormScreen({
    super.key,
    required this.profileId,
    required this.profileName,
    this.isPet = false,
    this.existing,
  });

  /// Atajo para abrir el formulario a partir de un perfil.
  factory OrderFormScreen.forProfile(FamilyProfile p, {MedicalRecord? existing}) => OrderFormScreen(
        profileId: p.id,
        profileName: p.name,
        isPet: p.type == ProfileType.mascota,
        existing: existing,
      );

  @override
  State<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends State<OrderFormScreen> {
  final _titleController = TextEditingController();
  final _professionalController = TextEditingController();
  final _institutionController = TextEditingController();
  final _otherSpecialtyController = TextEditingController();
  String? _specialty; // null = todavía sin elegir
  RecordStatus _status = RecordStatus.pendiente;
  DateTime _date = DateTime.now();
  bool _saving = false;

  // ── Adjunto + OCR ──
  OrderAttachment? _attachment;
  String _ocrText = '';
  bool _processing = false;
  bool _saved = false; // si el form se cierra sin guardar, se borra el archivo

  // Edición: el adjunto que ya tenía la orden NO se borra del disco hasta
  // que se guardan los cambios (si el usuario cancela, tiene que seguir ahí).
  String? _originalAttachmentPath;
  final List<String> _deferredDeletes = [];

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e == null) return;
    _titleController.text = e.title;
    _professionalController.text = e.professional;
    _institutionController.text = e.institution;
    _status = e.status;
    _date = e.date;
    final saved = (e.details['specialty'] as String?)?.trim() ?? '';
    if (saved.isNotEmpty) {
      if (_specialties.contains(saved)) {
        _specialty = saved;
      } else {
        _specialty = _otherValue;
        _otherSpecialtyController.text = saved;
      }
    }
    _attachment = OrderAttachment.fromDetails(e.details);
    _originalAttachmentPath = _attachment?.path;
    _ocrText = (e.details['ocrText'] as String?) ?? '';
  }

  /// Descarta un archivo adjunto: los nuevos (cargados en esta sesión) se
  /// borran ya; el original de una orden en edición espera al guardado.
  Future<void> _discard(String path) async {
    if (path == _originalAttachmentPath) {
      _deferredDeletes.add(path);
    } else {
      await AttachmentService.instance.delete(path);
    }
  }

  /// Valor reservado del selector: muestra un campo de texto libre. Lo que
  /// se escribe ahí queda SOLO en esta orden; no se agrega a la lista.
  static const _otherValue = 'Otra';

  static const _humanSpecialties = [
    'Análisis de laboratorio',
    'Diagnóstico por imágenes',
    'Cardiología',
    'Clínica médica',
    'Pediatría',
    'Ginecología',
    'Obstetricia',
    'Traumatología',
    'Dermatología',
    'Oftalmología',
    'Otorrinolaringología',
    'Odontología',
    'Neurología',
    'Gastroenterología',
    'Endocrinología',
    'Urología',
    'Nefrología',
    'Neumología',
    'Reumatología',
    'Oncología',
    'Hematología',
    'Psiquiatría',
    'Psicología',
    'Nutrición',
    'Kinesiología / Rehabilitación',
    'Alergia e inmunología',
    'Infectología',
    'Cirugía general',
  ];

  static const _petSpecialties = [
    'Análisis de laboratorio',
    'Radiografía / Ecografía',
    'Clínica general',
    'Vacunación y desparasitación',
    'Cardiología',
    'Dermatología',
    'Oftalmología',
    'Odontología veterinaria',
    'Traumatología y ortopedia',
    'Neurología',
    'Gastroenterología',
    'Endocrinología',
    'Oncología',
    'Nutrición',
    'Etología (comportamiento)',
    'Reproducción / Castración',
    'Cirugía',
    'Rehabilitación / Fisioterapia',
    'Animales exóticos',
  ];

  List<String> get _specialties => widget.isPet ? _petSpecialties : _humanSpecialties;

  /// Categoría "técnica" del historial según la especialidad elegida: se
  /// sigue usando para filtrar (Laboratorio / Estudios) en la lista de órdenes.
  static RecordCategory _categoryFor(String? specialty) {
    switch (specialty) {
      case 'Análisis de laboratorio':
        return RecordCategory.laboratorio;
      case 'Cardiología':
        return RecordCategory.cardiologia;
      default:
        return RecordCategory.estudio;
    }
  }

  /// Especialidad final que se guarda: la elegida o, con "Otra", el texto
  /// escrito. Vacía si todavía no se eligió nada.
  String get _specialtyValue {
    if (_specialty == _otherValue) return _otherSpecialtyController.text.trim();
    return _specialty ?? '';
  }

  @override
  void dispose() {
    // Sin guardar: se borra solo el adjunto cargado en esta sesión, nunca el
    // que la orden ya tenía.
    if (!_saved && _attachment != null && _attachment!.path != _originalAttachmentPath) {
      AttachmentService.instance.delete(_attachment!.path);
    }
    _titleController.dispose();
    _professionalController.dispose();
    _institutionController.dispose();
    _otherSpecialtyController.dispose();
    super.dispose();
  }

  /// Elige un archivo, lo copia al almacenamiento privado, y si es imagen
  /// corre el OCR y autocompleta los campos VACÍOS del formulario.
  Future<void> _attach(Future<String?> Function() picker) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final picked = await picker();
      if (picked == null) return; // canceló

      final saved = await AttachmentService.instance.saveToPrivateStorage(
        profileId: widget.profileId,
        sourcePath: picked,
      );

      // Si ya había un adjunto, se reemplaza y se borra el anterior.
      final old = _attachment;
      if (old != null) await _discard(old.path);

      var ocrText = '';
      OcrResult? ocr;
      if (saved.isImage) {
        try {
          final file = await AttachmentService.instance.resolve(saved.path);
          if (file != null) {
            ocr = await OcrService.instance.scanImage(file.path);
            ocrText = ocr.text;
          }
        } catch (_) {
          // El OCR es opcional: si falla, igual queda el adjunto.
        }
      }

      if (!mounted) return;
      setState(() {
        _attachment = saved;
        _ocrText = ocrText;
        if (ocr != null) _autofill(ocr);
      });

      final msg = saved.isPdf
          ? 'PDF adjuntado. Completá los datos de la orden.'
          : (ocr == null || ocr.isEmpty)
          ? 'Imagen adjuntada, pero no se pudo leer texto. Completá los datos a mano.'
          : 'Leímos la orden. Revisá los datos: la lectura automática puede tener errores.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo adjuntar el archivo: $e')),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Solo completa lo que el usuario todavía no escribió.
  void _autofill(OcrResult r) {
    if (_titleController.text.trim().isEmpty && r.title != null) {
      _titleController.text = r.title!;
    }
    if (_professionalController.text.trim().isEmpty && r.professional != null) {
      _professionalController.text = r.professional!;
    }
    if (_institutionController.text.trim().isEmpty && r.institution != null) {
      _institutionController.text = r.institution!;
    }
    if (_specialty == null) {
      if (r.category == RecordCategory.laboratorio) {
        _specialty = 'Análisis de laboratorio';
      } else if (r.category == RecordCategory.cardiologia) {
        _specialty = 'Cardiología';
      }
    }
    if (r.date != null) _date = r.date!;
  }

  Future<void> _removeAttachment() async {
    final old = _attachment;
    if (old == null) return;
    setState(() {
      _attachment = null;
      _ocrText = '';
    });
    await _discard(old.path);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _date.isBefore(DateTime.now().subtract(const Duration(days: 730)))
          ? _date
          : DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poné al menos un título (ej: "Análisis de Sangre").')),
      );
      return;
    }
    if (_specialty == _otherValue && _otherSpecialtyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribí la especialidad de la orden.')),
      );
      return;
    }
    final specialty = _specialtyValue;
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final record = MedicalRecord(
        id: existing?.id ?? '',
        // Una orden vieja sin especialidad conserva su categoría.
        category: (existing != null && _specialty == null) ? existing.category : _categoryFor(_specialty),
        date: _date,
        title: _titleController.text.trim(),
        professional: _professionalController.text.trim(),
        institution: _institutionController.text.trim(),
        status: _status,
        details: {
          // Al editar se conserva cualquier otro dato guardado en la orden.
          if (existing != null)
            for (final e in existing.details.entries)
              if (!const {'specialty', 'ocrText', 'attachmentPath', 'attachmentName', 'attachmentType'}
                  .contains(e.key))
                e.key: e.value,
          if (specialty.isNotEmpty) 'specialty': specialty,
          if (_attachment != null) ..._attachment!.toDetails(),
          if (_ocrText.trim().isNotEmpty)
            'ocrText': _ocrText.length > 6000 ? _ocrText.substring(0, 6000) : _ocrText,
        },
      );
      if (existing != null) {
        await MedicalRecordService.instance.updateRecord(widget.profileId, record);
      } else {
        await MedicalRecordService.instance.addRecord(widget.profileId, record);
      }
      _saved = true;
      // Recién ahora que se guardó se borran los adjuntos reemplazados/quitados.
      for (final path in _deferredDeletes) {
        if (path != _attachment?.path) await AttachmentService.instance.delete(path);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la orden: $e')),
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
        title: Text('${_isEditing ? 'Editar orden' : 'Nueva orden'} · ${widget.profileName}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _AttachmentSection(
              attachment: _attachment,
              processing: _processing,
              ocrText: _ocrText,
              onCamera: () => _attach(AttachmentService.instance.pickFromCamera),
              onGallery: () => _attach(AttachmentService.instance.pickFromGallery),
              onFile: () => _attach(AttachmentService.instance.pickDocument),
              onRemove: _removeAttachment,
            ),
            const SizedBox(height: 22),
            _Label('Título'),
            TextField(
              controller: _titleController,
              decoration: _decoration('Ej: Análisis de Sangre'),
            ),
            const SizedBox(height: 18),
            _Label('Especialidad'),
            DropdownButtonFormField<String>(
              initialValue: _specialty,
              isExpanded: true,
              hint: const Text('Elegí una especialidad'),
              decoration: _decoration('Elegí una especialidad'),
              borderRadius: BorderRadius.circular(14),
              items: [
                ..._specialties.map((e) => DropdownMenuItem(value: e, child: Text(e))),
                const DropdownMenuItem(value: _otherValue, child: Text('Otra…')),
              ],
              onChanged: (v) => setState(() => _specialty = v),
            ),
            if (_specialty == _otherValue) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _otherSpecialtyController,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration('Escribí la especialidad'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'Se guarda solo en esta orden.',
                  style: TextStyle(fontSize: 12, color: SaluteColors.textMuted),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _Label('Médico (opcional)'),
            TextField(
              controller: _professionalController,
              decoration: _decoration('Ej: Dr. Fontana'),
            ),
            const SizedBox(height: 18),
            _Label('Institución (opcional)'),
            TextField(
              controller: _institutionController,
              decoration: _decoration('Ej: Lab Central'),
            ),
            const SizedBox(height: 18),
            _Label('Fecha'),
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
                    Flexible(
                      child: Text(
                        '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _Label('Estado'),
            Row(
              children: [
                Expanded(
                  child: _StatusChip(
                    label: 'Pendiente',
                    selected: _status == RecordStatus.pendiente,
                    color: SaluteColors.brownOrange,
                    onTap: () => setState(() => _status = RecordStatus.pendiente),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatusChip(
                    label: 'Completado',
                    selected: _status == RecordStatus.completado,
                    color: SaluteColors.primaryGreen,
                    onTap: () => setState(() => _status = RecordStatus.completado),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            ConstrainedBox(constraints: const BoxConstraints(minHeight: 52), child: ElevatedButton(
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
                    : Text(_isEditing ? 'GUARDAR CAMBIOS' : 'GUARDAR ORDEN', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
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

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : Colors.grey.shade300, width: selected ? 1.5 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? color : SaluteColors.textMuted,
          ),
        ),
      ),
    );
  }
}


/// Bloque "Adjuntar orden": cámara / galería / PDF + vista previa.
class _AttachmentSection extends StatelessWidget {
  final OrderAttachment? attachment;
  final bool processing;
  final String ocrText;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;
  final VoidCallback onRemove;

  const _AttachmentSection({
    required this.attachment,
    required this.processing,
    required this.ocrText,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('Adjuntar orden (opcional)'),
          Text(
            'Sacá una foto y completamos los datos por vos. Se guarda solo en este dispositivo.',
            style: TextStyle(fontSize: 12, color: SaluteColors.textMuted),
          ),
          const SizedBox(height: 12),
          if (processing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: SaluteColors.primaryGreen),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Leyendo la orden…')),
                ],
              ),
            )
          else if (attachment == null)
            Row(
              children: [
                Expanded(child: _AttachButton(icon: Icons.photo_camera_outlined, label: 'Cámara', onTap: onCamera)),
                const SizedBox(width: 8),
                Expanded(child: _AttachButton(icon: Icons.photo_library_outlined, label: 'Galería', onTap: onGallery)),
                const SizedBox(width: 8),
                Expanded(child: _AttachButton(icon: Icons.picture_as_pdf_outlined, label: 'PDF', onTap: onFile)),
              ],
            )
          else ...[
              _Preview(attachment: attachment!, onRemove: onRemove),
              if (ocrText.trim().isNotEmpty)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Texto reconocido', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(ocrText, style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AttachButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: SaluteColors.bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, color: SaluteColors.primaryGreen),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final OrderAttachment attachment;
  final VoidCallback onRemove;
  const _Preview({required this.attachment, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 64,
            height: 64,
            child: attachment.isImage
                ? FutureBuilder<Uint8List?>(
              future: AttachmentService.instance.readBytes(attachment.path),
              builder: (_, snap) {
                final bytes = snap.data;
                if (bytes == null) return const ColoredBox(color: Colors.black12);
                return Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 200, semanticLabel: 'Foto de la orden médica adjunta');
              },
            )
                : const ColoredBox(
              color: Color(0x14000000),
              child: Icon(Icons.picture_as_pdf, color: SaluteColors.terracotta, size: 32, semanticLabel: 'Archivo PDF adjunto'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            attachment.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        IconButton(
          tooltip: 'Quitar adjunto',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}