import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/vaccine_record.dart';
import 'package:saluteapp/core/services/attachment_service.dart';
import 'package:saluteapp/core/services/ocr_service.dart';
import 'package:saluteapp/core/services/vaccine_ocr_parser.dart';
import 'package:saluteapp/core/services/vaccine_service.dart';
import 'package:saluteapp/profile/vaccine_form_screen.dart';
import 'package:saluteapp/profile/vaccine_widgets.dart';

class _Row {
  VaccineDraft draft;
  bool include;
  _Row(this.draft) : include = draft.isComplete;
}

/// Escaneo del certificado de vacunación de una persona o una mascota:
///
///  1. se adjunta una foto (o un PDF) del certificado,
///  2. el OCR del dispositivo lee el texto y `VaccineOcrParser` arma una
///     fila por cada vacuna que reconoce,
///  3. el usuario REVISA y corrige cada fila (nada se guarda solo; las
///     filas sin fecha quedan sin marcar porque la fecha no se inventa),
///  4. recién al confirmar se guardan las dosis en `vacunas`, y las que
///     tienen próxima dosis crean su recordatorio en la agenda.
class VaccineScanScreen extends StatefulWidget {
  final FamilyProfile profile;
  final List<VaccineRecord> existingRecords;

  const VaccineScanScreen({super.key, required this.profile, this.existingRecords = const []});

  @override
  State<VaccineScanScreen> createState() => _VaccineScanScreenState();
}

class _VaccineScanScreenState extends State<VaccineScanScreen> {
  OrderAttachment? _attachment;
  String _ocrText = '';
  bool _processing = false;
  bool _scanned = false; // ya se intentó leer un archivo
  bool _saving = false;
  bool _saved = false; // si se cierra sin guardar, se borra el archivo
  final List<_Row> _rows = [];

  @override
  void dispose() {
    if (!_saved && _attachment != null) {
      AttachmentService.instance.delete(_attachment!.path);
    }
    super.dispose();
  }

  void _msg(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _attach(Future<String?> Function() picker) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final picked = await picker();
      if (picked == null) return;

      final saved = await AttachmentService.instance.saveToPrivateStorage(
        profileId: widget.profile.id,
        sourcePath: picked,
        folder: 'vacunas',
      );
      final old = _attachment;
      if (old != null) await AttachmentService.instance.delete(old.path);

      var text = '';
      var drafts = <VaccineDraft>[];
      if (saved.isImage) {
        try {
          final file = await AttachmentService.instance.resolve(saved.path);
          if (file != null) {
            text = await OcrService.instance.readText(file.path);
            drafts = VaccineOcrParser.parse(
              text,
              person: widget.profile.type == ProfileType.persona,
            );
          }
        } catch (_) {
          // El OCR es opcional: si falla, se carga a mano.
        }
      }

      if (!mounted) return;
      setState(() {
        _attachment = saved;
        _ocrText = text;
        _scanned = true;
        _rows
          ..clear()
          ..addAll(drafts.map(_Row.new));
      });

      if (saved.isPdf) {
        _msg('PDF guardado. No lo podemos leer automáticamente: cargá las vacunas a mano.');
      } else if (text.isEmpty) {
        _msg('No se pudo leer texto de la imagen. Probá con más luz o cargá las vacunas a mano.');
      } else if (drafts.isEmpty) {
        _msg('Leímos el texto pero no reconocimos vacunas. Podés agregarlas a mano.');
      } else {
        _msg('Encontramos ${drafts.length} vacuna(s). Revisalas: la lectura puede tener errores.');
      }
    } catch (e) {
      if (mounted) _msg('No se pudo adjuntar el archivo: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _removeAttachment() async {
    final old = _attachment;
    if (old == null) return;
    setState(() {
      _attachment = null;
      _ocrText = '';
      _scanned = false;
      _rows.clear();
    });
    await AttachmentService.instance.delete(old.path);
  }

  Future<void> _editRow(_Row row) async {
    final result = await Navigator.of(context).push<VaccineDraft>(
      MaterialPageRoute(
        builder: (_) => VaccineFormScreen(
          profile: widget.profile,
          draft: row.draft.copy(),
          returnDraft: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      row.draft = result;
      row.include = result.isComplete;
    });
  }

  Future<void> _addManualRow() async {
    final result = await Navigator.of(context).push<VaccineDraft>(
      MaterialPageRoute(
        builder: (_) => VaccineFormScreen(
          profile: widget.profile,
          draft: VaccineDraft(),
          returnDraft: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _rows.add(_Row(result)));
  }

  Future<void> _saveAll() async {
    final chosen = _rows.where((r) => r.include).toList();
    if (chosen.isEmpty) return _msg('Marcá al menos una vacuna para guardar.');
    if (chosen.any((r) => !r.draft.isComplete)) {
      return _msg('Hay vacunas marcadas sin fecha. Tocalas para completarlas.');
    }

    setState(() => _saving = true);
    var failed = 0;
    var withReminder = 0;
    for (var i = 0; i < chosen.length; i++) {
      final row = chosen[i];
      final d = row.draft;
      try {
        final result = await VaccineService.instance.add(
          widget.profile,
          VaccineRecord(
            id: '',
            name: d.name.trim(),
            date: d.date!,
            nextDoseDate: d.nextDoseDate,
            professional: d.professional,
            source: d.source,
            lot: d.lot,
            notes: d.notes,
            attachment: _attachment,
            ocrText: i == 0 ? _ocrText : '',
          ),
          existing: widget.existingRecords,
        );
        _saved = true; // al menos una dosis ya referencia el archivo
        if (result.reminderCreated == true) withReminder++;
        _rows.remove(row);
      } catch (e) {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (failed > 0) {
      _msg('No se pudieron guardar $failed vacuna(s). Quedaron en la lista para reintentar.');
      return;
    }
    _msg(withReminder > 0
        ? 'Carné actualizado. Creamos $withReminder recordatorio(s) de próxima dosis.'
        : 'Carné actualizado.');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _rows.where((r) => r.include).length;

    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      appBar: AppBar(
        backgroundColor: SaluteColors.bgColor,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text('Escanear certificado · ${widget.profile.name}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _AttachCard(
              isPet: widget.profile.type == ProfileType.mascota,
              attachment: _attachment,
              processing: _processing,
              ocrText: _ocrText,
              onCamera: () => _attach(AttachmentService.instance.pickFromCamera),
              onGallery: () => _attach(AttachmentService.instance.pickFromGallery),
              onFile: () => _attach(AttachmentService.instance.pickDocument),
              onRemove: _removeAttachment,
            ),
            if (_scanned) ...[
              const SizedBox(height: 20),
              const _ReviewBanner(),
              const SizedBox(height: 14),
              if (_rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Todavía no hay vacunas para guardar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: SaluteColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                ),
              for (final row in _rows) ...[
                _DraftTile(
                  row: row,
                  onToggle: (v) => setState(() => row.include = v),
                  onEdit: () => _editRow(row),
                  onRemove: () => setState(() => _rows.remove(row)),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: _addManualRow,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar otra vacuna a mano'),
              ),
              const SizedBox(height: 22),
              ConstrainedBox(constraints: const BoxConstraints(minHeight: 52), child: ElevatedButton(
                  onPressed: (_saving || selected == 0) ? null : _saveAll,
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
                          selected == 0 ? 'GUARDAR' : 'GUARDAR $selected VACUNA${selected == 1 ? '' : 'S'}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SaluteColors.cardBeige,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.fact_check_outlined, size: 20, color: SaluteColors.brownOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Revisá cada vacuna: la lectura automática puede tener errores. '
              'No se guarda nada que no marques, y las que no tienen fecha '
              'quedan sin marcar hasta que las completes.',
              style: TextStyle(fontSize: 12, color: Colors.grey[800], height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  final _Row row;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _DraftTile({
    required this.row,
    required this.onToggle,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final d = row.draft;
    final missingDate = d.date == null;
    final lines = <String>[
      if (d.date != null) 'Aplicada: ${fmtVaccineDate(d.date!)}',
      if (d.nextDoseDate != null) 'Próxima: ${fmtVaccineDate(d.nextDoseDate!)}',
      if (d.professional.isNotEmpty) d.professional,
      if (d.lot.isNotEmpty) 'Lote ${d.lot}',
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: missingDate ? SaluteColors.brownOrange.withValues(alpha: 0.6) : Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
          child: Row(
            children: [
              Semantics(
                label: 'Incluir ${d.name.isEmpty ? 'vacuna sin nombre' : d.name}',
                child: Checkbox(
                  value: row.include,
                  activeColor: SaluteColors.primaryGreen,
                  onChanged: d.isComplete ? (v) => onToggle(v ?? false) : null,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name.isEmpty ? 'Sin nombre' : d.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    if (missingDate)
                      const Text(
                        'Falta la fecha de aplicación. Tocá para completarla.',
                        style: TextStyle(fontSize: 12, color: SaluteColors.brownOrange, fontWeight: FontWeight.w700),
                      ),
                    if (lines.isNotEmpty)
                      Text(
                        lines.join(' · '),
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Descartar',
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, color: SaluteColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachCard extends StatelessWidget {
  final OrderAttachment? attachment;
  final bool isPet;
  final bool processing;
  final String ocrText;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;
  final VoidCallback onRemove;

  const _AttachCard({
    required this.isPet,
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
          const VaccineLabel('Certificado de vacunación'),
          Text(
            '${isPet ? 'Sacale una foto a la libreta sanitaria o al certificado del veterinario.' : 'Sacale una foto al carné o a la libreta de vacunación.'} '
            'Se lee en tu teléfono y el archivo se guarda solo en este dispositivo.',
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
                  Expanded(child: Text('Leyendo el certificado…')),
                ],
              ),
            )
          else if (attachment == null)
            Row(
              children: [
                Expanded(child: _PickButton(icon: Icons.photo_camera_outlined, label: 'Cámara', onTap: onCamera)),
                const SizedBox(width: 8),
                Expanded(child: _PickButton(icon: Icons.photo_library_outlined, label: 'Galería', onTap: onGallery)),
                const SizedBox(width: 8),
                Expanded(child: _PickButton(icon: Icons.picture_as_pdf_outlined, label: 'PDF', onTap: onFile)),
              ],
            )
          else ...[
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: attachment!.isImage
                        ? FutureBuilder<Uint8List?>(
                            future: AttachmentService.instance.readBytes(attachment!.path),
                            builder: (_, snap) {
                              final bytes = snap.data;
                              if (bytes == null) return const ColoredBox(color: Colors.black12);
                              return Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 200, semanticLabel: 'Foto del carné de vacunación adjunta');
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
                    attachment!.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar y volver a escanear',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
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

class _PickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickButton({required this.icon, required this.label, required this.onTap});

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
