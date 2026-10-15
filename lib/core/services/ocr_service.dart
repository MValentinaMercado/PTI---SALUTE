import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:saluteapp/core/models/medical_record.dart';

/// Resultado del OCR + sugerencias extraídas del texto.
/// Todo es SUGERENCIA: el usuario siempre revisa antes de guardar.
class OcrResult {
  final String text;
  final DateTime? date;
  final String? professional;
  final String? institution;
  final String? title;
  final RecordCategory? category;

  const OcrResult({
    required this.text,
    this.date,
    this.professional,
    this.institution,
    this.title,
    this.category,
  });

  bool get isEmpty => text.trim().isEmpty;
}

/// OCR en el dispositivo con Google ML Kit (gratis, sin internet).
/// Solo lee imágenes; para PDFs no se hace OCR (se adjuntan tal cual).
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  Future<OcrResult> scanImage(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(input);
      return parse(recognized.text);
    } catch (e) {
      debugPrint('OcrService: falló el reconocimiento. $e');
      rethrow;
    } finally {
      await recognizer.close();
    }
  }

  /// Solo el texto reconocido, sin aplicar el parser de órdenes médicas.
  /// Lo usan los flujos con su propio parser (ej: certificado de vacunas).
  Future<String> readText(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return recognized.text.trim();
    } catch (e) {
      debugPrint('OcrService: falló el reconocimiento. $e');
      rethrow;
    } finally {
      await recognizer.close();
    }
  }

  // ── Extracción de campos ────────────────────────────────────────────────

  static const _labKeywords = [
    'hemograma', 'glucemia', 'colesterol', 'trigliceridos', 'orina',
    'laboratorio', 'bioquimica', 'eritrosedimentacion', 'uremia', 'creatinina',
    'hepatograma', 'tsh', 'perfil lipidico',
  ];
  // palabra clave (sin tildes) -> título sugerido
  static const _cardioKeywords = {
    'electrocardiograma': 'Electrocardiograma',
    'ecocardiograma': 'Ecocardiograma',
    'ergometria': 'Ergometría',
    'holter': 'Holter',
    'ecg': 'Electrocardiograma',
  };
  static const _studyKeywords = {
    'ecografia': 'Ecografía',
    'radiografia': 'Radiografía',
    'resonancia': 'Resonancia magnética',
    'tomografia': 'Tomografía',
    'mamografia': 'Mamografía',
    'densitometria': 'Densitometría',
    'espirometria': 'Espirometría',
    'endoscopia': 'Endoscopia',
    'colonoscopia': 'Colonoscopía',
    'papanicolau': 'Papanicolau',
  };
  static const _institutionWords = [
    'hospital', 'clinica', 'sanatorio', 'laboratorio', 'instituto', 'centro',
    'policlinico', 'diagnostico',
  ];

  @visibleForTesting
  OcrResult parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const OcrResult(text: '');

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final normalized = _norm(text);

    // Categoría + título según palabras clave.
    RecordCategory? category;
    String? title;

    bool hasAny(Iterable<String> keys) => keys.any(normalized.contains);
    String? firstKey(Iterable<String> keys) {
      for (final k in keys) {
        if (normalized.contains(k)) return k;
      }
      return null;
    }

    final cardio = firstKey(_cardioKeywords.keys);
    final study = firstKey(_studyKeywords.keys);
    if (cardio != null) {
      category = RecordCategory.cardiologia;
      title = _cardioKeywords[cardio];
    } else if (study != null) {
      category = RecordCategory.estudio;
      title = _studyKeywords[study];
    } else if (hasAny(_labKeywords)) {
      category = RecordCategory.laboratorio;
      title = 'Análisis de laboratorio';
    }

    return OcrResult(
      text: text,
      date: _findDate(text),
      professional: _findProfessional(lines),
      institution: _findInstitution(lines),
      title: title,
      category: category,
    );
  }

  /// Busca dd/mm/aaaa, dd-mm-aa, dd.mm.aaaa (formato argentino).
  DateTime? _findDate(String text) {
    final re = RegExp(r'\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b');
    for (final m in re.allMatches(text)) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      if (mo < 1 || mo > 12 || d < 1 || d > 31) continue;
      if (y < 2000 || y > DateTime.now().year + 2) continue;
      try {
        final date = DateTime(y, mo, d);
        if (date.month == mo) return date; // descarta 31/02, etc.
      } catch (_) {}
    }
    return null;
  }

  String? _findProfessional(List<String> lines) {
    final re = RegExp(
      r'\b(?:dr|dra|doctor|doctora)\b\.?\s+(\p{L}{2,}(?:\s\p{L}{2,}){0,2})',
      caseSensitive: false,
      unicode: true,
    );
    for (final line in lines) {
      final m = re.firstMatch(line);
      if (m != null) {
        final prefix = line.substring(m.start, m.start + 3).toLowerCase() == 'dra' ? 'Dra.' : 'Dr.';
        return '$prefix ${m.group(1)!.trim()}';
      }
    }
    return null;
  }

  String? _findInstitution(List<String> lines) {
    for (final line in lines) {
      final n = _norm(line);
      if (line.length <= 60 && _institutionWords.any(n.contains)) return line;
    }
    return null;
  }

  // ── Utilidades ──────────────────────────────────────────────────────────

  String _norm(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}