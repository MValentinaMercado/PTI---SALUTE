import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:cross_file/cross_file.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:saluteapp/core/models/family_profile.dart';
import 'package:saluteapp/core/models/medical_record.dart';
import 'package:saluteapp/core/models/medical_sheet.dart';
import 'package:saluteapp/core/models/medication.dart';
import 'package:saluteapp/core/models/sos_contact.dart';
import 'package:saluteapp/core/services/medical_record_service.dart';
import 'package:saluteapp/core/services/medication_service.dart';
import 'package:saluteapp/core/services/profile_service.dart';
import 'package:saluteapp/core/services/sos_contact_service.dart';
import 'package:share_plus/share_plus.dart';

/// Arma la ficha médica de un perfil y la saca de la app: PDF, texto,
/// compartir y guardar en el dispositivo.
///
/// Ojo con esto: apenas la ficha sale por cualquiera de esas vías deja de
/// estar cifrada y de estar bajo control de la app. Por eso la pantalla
/// obliga a elegir qué se incluye y avisa antes de compartir.
class MedicalSheetService {
  MedicalSheetService._();
  static final MedicalSheetService instance = MedicalSheetService._();

  /// Lee el perfil (fresco, no la copia del perfil activo, que puede estar
  /// desactualizada), su medicación, su historial y el contacto de
  /// emergencia. Si una parte falla —típicamente `permission-denied` porque
  /// el titular no compartió sus datos clínicos— esa sección queda marcada
  /// como no disponible en vez de tirar abajo toda la ficha.
  Future<MedicalSheetData> load(String profileId) async {
    final profile = await ProfileService.instance.getProfile(profileId);
    if (profile == null) {
      throw StateError('No se encontró el perfil.');
    }

    final unavailable = <MedicalSheetSection, String>{};
    var medications = const <Medication>[];
    var history = const <MedicalRecord>[];
    SosContact? sos;

    try {
      medications = await MedicationService.instance
          .watchMedications(profileId, onlyActive: true)
          .first;
    } catch (e) {
      unavailable[MedicalSheetSection.medication] = _reason(e);
    }

    try {
      final records = await MedicalRecordService.instance.fetchRecords(profileId, limit: 40);
      history = records
          .where((r) =>
      kSheetHistoryCategories.contains(r.category) && r.status == RecordStatus.completado)
          .take(10)
          .toList();
    } catch (e) {
      unavailable[MedicalSheetSection.history] = _reason(e);
    }

    // El contacto SOS es un dato de la CUENTA (users/{uid}), no del perfil.
    // Solo es "el contacto de emergencia de esta ficha" cuando la ficha es
    // de una PERSONA: del propio usuario o de un dependiente suyo. En el
    // perfil de otro familiar con cuenta propia no lo podemos leer ni
    // corresponde, y en una mascota es un dato de su dueño que no hace
    // falta para el veterinario.
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final emergencyApplicable =
        myUid != null &&
            profile.ownerUid == myUid &&
            profile.type == ProfileType.persona &&
            (profile.isSelf || profile.isDependent);
    if (emergencyApplicable) {
      try {
        sos = await SosContactService.instance.getSosContact();
      } catch (e) {
        debugPrint('MedicalSheetService: no se pudo leer el contacto SOS. $e');
      }
    }

    return MedicalSheetData(
      profile: profile,
      medications: medications,
      history: history,
      sosContact: sos,
      emergencyApplicable: emergencyApplicable,
      unavailable: unavailable,
      generatedAt: DateTime.now(),
    );
  }

  String _reason(Object e) {
    if (e is FirebaseException && e.code == 'permission-denied') {
      return 'Este perfil no compartió estos datos con vos.';
    }
    return 'No se pudieron cargar.';
  }

  // ───────────────────────────── PDF ─────────────────────────────

  static final PdfColor _green = PdfColor.fromInt(0xFF1A5C3A);
  static final PdfColor _grey = PdfColor.fromInt(0xFF666666);

  Future<Uint8List> buildPdf(MedicalSheetData data, Set<MedicalSheetSection> included) async {
    final blocks = data.blocks(included);

    final doc = pw.Document(
      title: _pdfSafe('${data.sheetTitle} - ${data.profile.fullName}'),
      author: 'Salute',
      creator: 'Salute',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Salute', style: pw.TextStyle(fontSize: 9, color: _grey)),
            pw.Text(
              'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 9, color: _grey),
            ),
          ],
        ),
        build: (ctx) => [
          pw.Text(
            _pdfSafe(data.sheetTitle),
            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: _green),
          ),
          pw.SizedBox(height: 2),
          pw.Text(_pdfSafe(data.generatedLabel), style: pw.TextStyle(fontSize: 10, color: _grey)),
          for (final block in blocks) ..._blockWidgets(block),
          pw.SizedBox(height: 22),
          pw.Text(
            _pdfSafe(MedicalSheetData.disclaimer),
            style: pw.TextStyle(fontSize: 9, color: _grey),
          ),
        ],
      ),
    );

    return doc.save();
  }

  List<pw.Widget> _blockWidgets(MedicalSheetBlock block) {
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
        padding: const pw.EdgeInsets.only(bottom: 3),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _green, width: 1)),
        ),
        child: pw.Text(
          _pdfSafe(block.title.toUpperCase()),
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _green),
        ),
      ),
      for (final line in block.lines)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: line.label != null
              ? pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 11),
              children: [
                pw.TextSpan(
                  text: _pdfSafe('${line.label}: '),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(text: _pdfSafe(line.value)),
              ],
            ),
          )
              : pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('-  ', style: const pw.TextStyle(fontSize: 11)),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_pdfSafe(line.value), style: const pw.TextStyle(fontSize: 11)),
                    if (line.detail != null)
                      pw.Text(
                        _pdfSafe(line.detail!),
                        style: pw.TextStyle(fontSize: 10, color: _grey),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
  }

  /// El PDF usa la fuente estándar (Helvetica), que solo dibuja Latin-1:
  /// acentos, ñ y ü andan, pero rayas largas, viñetas, comillas
  /// tipográficas, ≥, emojis, etc. no. Esos se reemplazan por su
  /// equivalente simple (o se sacan) para que no salgan en blanco.
  static String _pdfSafe(String input) {
    const replacements = {
      '–': '-', '—': '-', '•': '-', '·': '-', '…': '...',
      '“': '"', '”': '"', '‘': "'", '’': "'",
      '≥': '>=', '≤': '<=', '×': 'x', '\u00A0': ' ', '\t': ' ',
    };
    final buf = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final mapped = replacements[ch];
      if (mapped != null) {
        buf.write(mapped);
      } else if (rune == 0x0A || (rune >= 0x20 && rune <= 0x7E) || (rune >= 0xA1 && rune <= 0xFF)) {
        buf.write(ch);
      } else if ((rune >= 0x1F000 && rune <= 0x1FAFF) ||
          (rune >= 0x2600 && rune <= 0x27BF) ||
          rune == 0xFE0F ||
          rune == 0x200D) {
        // emojis y símbolos: se descartan
      } else {
        buf.write('?');
      }
    }
    return buf.toString();
  }

  // ─────────────────────── Compartir / guardar ───────────────────────

  static String fileNameFor(MedicalSheetData data) {
    final d = data.generatedAt;
    final stamp =
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final slug = _slug(data.profile.fullName);
    final base = data.isPet ? 'ficha-veterinaria' : 'ficha-medica';
    return '$base-${slug.isEmpty ? 'perfil' : slug}-$stamp.pdf';
  }

  static String _slug(String s) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    final buf = StringBuffer();
    for (final rune in s.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final i = from.indexOf(ch);
      buf.write(i >= 0 ? to[i] : ch);
    }
    return buf
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// Abre la hoja de compartir del sistema con el texto de la ficha.
  /// [origin] es el rectángulo del que se despliega en iPad.
  Future<ShareResultStatus> shareText(String text, {String? subject, Rect? origin}) async {
    final result = await SharePlus.instance.share(
      ShareParams(text: text, subject: subject, sharePositionOrigin: origin),
    );
    return result.status;
  }

  /// Abre la hoja de compartir del sistema con el PDF adjunto.
  Future<ShareResultStatus> sharePdf(
      Uint8List bytes,
      String fileName, {
        String? subject,
        Rect? origin,
      }) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
        fileNameOverrides: [fileName],
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );
    return result.status;
  }

  /// Le pide al usuario DÓNDE guardar el PDF (selector de ubicación del
  /// sistema: Descargas, Drive, etc.). Devuelve la ubicación elegida, o
  /// `null` si canceló. No necesita permisos de almacenamiento: es el
  /// propio sistema el que escribe en la ubicación que el usuario eligió.
  Future<String?> savePdfWithPicker(Uint8List bytes, String fileName) {
    return FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: bytes,
        fileName: fileName,
        mimeTypesFilter: const ['application/pdf'],
      ),
    );
  }
}