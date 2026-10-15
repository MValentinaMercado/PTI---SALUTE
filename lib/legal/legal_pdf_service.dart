import 'dart:typed_data';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:saluteapp/legal/legal_content.dart';

/// Genera el PDF de Privacidad y Términos y deja elegir dónde guardarlo.
class LegalPdfService {
  LegalPdfService._();
  static final LegalPdfService instance = LegalPdfService._();

  static const _green = PdfColor.fromInt(0xFF1A5C3A);
  static const _grey = PdfColor.fromInt(0xFF666666);

  static const fileName = 'salute-privacidad-y-terminos.pdf';

  Future<Uint8List> buildPdf() async {
    final doc = pw.Document(title: 'SALUTE - Privacidad y Términos de Servicio');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'SALUTE - Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 9, color: _grey),
          ),
        ),
        build: (_) => [
          pw.Text(
            'SALUTE',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _green),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            _safe('Privacidad y Términos de Servicio'),
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: _green),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _safe('Última actualización: $kLegalLastUpdate (versión $kTermsVersion)'),
            style: pw.TextStyle(fontSize: 10, color: _grey),
          ),
          ..._section('Aviso de Privacidad', kPrivacyItems),
          ..._section('Términos de Servicio', kTermsItems),
        ],
      ),
    );

    return doc.save();
  }

  List<pw.Widget> _section(String title, List<LegalItem> items) {
    return [
      pw.SizedBox(height: 22),
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _green, width: 1)),
        ),
        child: pw.Text(
          _safe(title),
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _green),
        ),
      ),
      pw.SizedBox(height: 10),
      for (var i = 0; i < items.length; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _safe('${(i + 1).toString().padLeft(2, '0')}  ${items[i].title}'),
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                _safe(items[i].body),
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
              ),
            ],
          ),
        ),
    ];
  }

  /// Abre el selector del sistema para elegir dónde guardarlo (no necesita
  /// permisos de almacenamiento). Devuelve la ubicación, o null si canceló.
  Future<String?> savePdf() async {
    final bytes = await buildPdf();
    return FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: bytes,
        fileName: fileName,
        mimeTypesFilter: const ['application/pdf'],
      ),
    );
  }

  /// La fuente estándar del PDF solo dibuja Latin-1 (acentos y ñ andan).
  /// Símbolos como rayas largas o comillas tipográficas se reemplazan.
  static String _safe(String input) {
    const map = {
      '–': '-', '—': '-', '•': '-', '·': '-', '…': '...',
      '“': '"', '”': '"', '‘': "'", '’': "'", '\u00A0': ' ',
    };
    final b = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final m = map[ch];
      if (m != null) {
        b.write(m);
      } else if (rune == 0x0A || (rune >= 0x20 && rune <= 0x7E) || (rune >= 0xA1 && rune <= 0xFF)) {
        b.write(ch);
      } else {
        b.write('?');
      }
    }
    return b.toString();
  }
}