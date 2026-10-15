import 'dart:ui' show Rect;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saluteapp/components/app_header.dart';
import 'package:saluteapp/core/colors.dart';
import 'package:saluteapp/core/models/medical_sheet.dart';
import 'package:saluteapp/core/services/medical_sheet_service.dart';

enum _ShareFormat { pdf, text }

/// Ficha médica de un perfil: vista previa, y desde ahí copiar, guardar
/// como PDF (pidiendo dónde) o compartir con un profesional.
///
/// Flujo pensado para no filtrar datos sin querer:
///  1. El usuario elige QUÉ secciones incluir (el historial arranca apagado).
///  2. La vista previa muestra exactamente lo que va a salir.
///  3. Antes de compartir, una hoja resume qué se envía y avisa que la
///     información sale de la app (deja de estar cifrada).
class MedicalSheetScreen extends StatefulWidget {
  final String profileId;
  final String profileName;

  /// `true` cuando se entra por "Compartir datos": apenas carga la ficha
  /// se abre directamente la hoja de compartir.
  final bool startWithShare;

  const MedicalSheetScreen({
    super.key,
    required this.profileId,
    required this.profileName,
    this.startWithShare = false,
  });

  @override
  State<MedicalSheetScreen> createState() => _MedicalSheetScreenState();
}

class _MedicalSheetScreenState extends State<MedicalSheetScreen> {
  MedicalSheetData? _data;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _autoShareDone = false;
  Set<MedicalSheetSection> _included = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await MedicalSheetService.instance.load(widget.profileId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _included = data.defaultSelection;
        _loading = false;
      });
      if (widget.startWithShare && !_autoShareDone) {
        _autoShareDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openShareSheet();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo armar la ficha.\n$e';
        _loading = false;
      });
    }
  }

  // ─────────────────────────── acciones ───────────────────────────

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Rectángulo desde el que se despliega la hoja de compartir en iPad.
  Rect? _originFor(BuildContext ctx) {
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _copy() async {
    final data = _data;
    if (data == null) return;
    await Clipboard.setData(ClipboardData(text: data.toPlainText(_included)));
    if (!mounted) return;
    _snack('Ficha copiada al portapapeles.');
  }

  Future<void> _savePdf() async {
    final data = _data;
    if (data == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await MedicalSheetService.instance.buildPdf(data, _included);
      // Abre el selector de ubicación del sistema: el usuario decide dónde
      // (y con qué nombre) queda el archivo.
      final saved = await MedicalSheetService.instance
          .savePdfWithPicker(bytes, MedicalSheetService.fileNameFor(data));
      if (!mounted) return;
      _snack(saved == null ? 'Guardado cancelado.' : 'PDF guardado.');
    } catch (_) {
      if (!mounted) return;
      _snack('No se pudo guardar el PDF. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openShareSheet() async {
    final data = _data;
    if (data == null || _busy) return;
    final labels = [
      data.identityLabel,
      ...MedicalSheetSection.values
          .where((s) => _included.contains(s) && data.applicableSections.contains(s))
          .map((s) => s.label),
    ];
    final choice = await showModalBottomSheet<_ShareFormat>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ShareSheet(sectionLabels: labels),
    );
    if (choice == null || !mounted) return;
    await _runShare(data, choice);
  }

  Future<void> _runShare(MedicalSheetData data, _ShareFormat format) async {
    final origin = _originFor(context);
    final subject = '${data.sheetTitle} - ${data.profile.fullName}';
    setState(() => _busy = true);
    try {
      if (format == _ShareFormat.pdf) {
        final bytes = await MedicalSheetService.instance.buildPdf(data, _included);
        await MedicalSheetService.instance.sharePdf(
          bytes,
          MedicalSheetService.fileNameFor(data),
          subject: subject,
          origin: origin,
        );
      } else {
        await MedicalSheetService.instance.shareText(
          data.toPlainText(_included),
          subject: subject,
          origin: origin,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _snack('No se pudo compartir la ficha. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────────────── UI ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaluteColors.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader.secondary(title: _data?.sheetTitle ?? 'Ficha médica'),
            if (_busy) const LinearProgressIndicator(minHeight: 2, color: SaluteColors.primaryGreen),
            Expanded(child: _buildBody()),
            if (_data != null) _buildActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: SaluteColors.primaryGreen));
    }
    final data = _data;
    if (_error != null || data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'No se pudo armar la ficha.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    final blocks = data.blocks(_included);
    final unavailable = data.unavailable.entries
        .where((e) => data.applicableSections.contains(e.key))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        Text(
          data.profile.fullName,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(data.generatedLabel, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        const Text(
          'QUÉ INCLUIR',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: SaluteColors.primaryGreen,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: Text(data.identityLabel),
              selected: true,
              onSelected: null,
            ),
            for (final section in MedicalSheetSection.values)
              if (data.applicableSections.contains(section))
                FilterChip(
                  label: Text(section.label),
                  selected: _included.contains(section),
                  selectedColor: SaluteColors.primaryGreen.withValues(alpha: 0.15),
                  checkmarkColor: SaluteColors.primaryGreen,
                  onSelected: data.unavailable.containsKey(section)
                      ? null
                      : (on) => setState(() {
                    if (on) {
                      _included.add(section);
                    } else {
                      _included.remove(section);
                    }
                  }),
                ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          data.isPet
              ? 'El historial viene desactivado: incluilo si el veterinario lo necesita.'
              : 'El historial viene desactivado: es la información más sensible, incluilo solo si hace falta.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        for (final e in unavailable)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${e.key.label}: ${e.value}',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),
        const SizedBox(height: 18),
        for (final block in blocks) _BlockCard(block: block),
        const SizedBox(height: 4),
        Text(
          MedicalSheetData.disclaimer,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _copy,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copiar'),
                  style: _outlinedStyle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _savePdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Guardar PDF'),
                  style: _outlinedStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _busy ? null : _openShareSheet,
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text(
                'Compartir con un profesional',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: SaluteColors.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle get _outlinedStyle => OutlinedButton.styleFrom(
    foregroundColor: SaluteColors.primaryGreen,
    side: const BorderSide(color: SaluteColors.primaryGreen),
    minimumSize: const Size.fromHeight(46),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

/// Un bloque de la vista previa (misma información que va al texto y al PDF).
class _BlockCard extends StatelessWidget {
  final MedicalSheetBlock block;
  const _BlockCard({required this.block});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            block.title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: SaluteColors.primaryGreen,
              letterSpacing: 0.8,
            ),
          ),
          for (final line in block.lines)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: line.label != null
                  ? Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                  children: [
                    TextSpan(
                      text: '${line.label}: ',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade700),
                    ),
                    TextSpan(text: line.value),
                  ],
                ),
              )
                  : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(fontSize: 14, color: SaluteColors.primaryGreen)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line.value, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                        if (line.detail != null)
                          Text(
                            line.detail!,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Hoja de confirmación previa a compartir: resume qué sale de la app,
/// avisa el riesgo y recién ahí deja elegir el formato.
class _ShareSheet extends StatelessWidget {
  final List<String> sectionLabels;
  const _ShareSheet({required this.sectionLabels});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Compartir con un profesional',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text('Vas a enviar:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in sectionLabels)
                  Chip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    backgroundColor: SaluteColors.lightGreen.withValues(alpha: 0.5),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange.shade800),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Al compartirla, esta información sale de Salute: deja de estar cifrada y ya no '
                          'la controlás. Enviala solo a profesionales o personas de confianza, y revisá '
                          'el destinatario antes de confirmar en la app que elijas.',
                      style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, _ShareFormat.pdf),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Compartir como PDF', style: TextStyle(fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(
                  backgroundColor: SaluteColors.primaryGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, _ShareFormat.text),
                icon: const Icon(Icons.notes_outlined, size: 18),
                label: const Text('Compartir como texto', style: TextStyle(fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SaluteColors.primaryGreen,
                  side: const BorderSide(color: SaluteColors.primaryGreen),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}