import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELO
// ─────────────────────────────────────────────────────────────────────────────

/// Orientación generada por la IA. No es un diagnóstico.
class AiInsight {
  /// Orden de menor a mayor gravedad.
  static const levels = ['info', 'vigilar', 'consultar', 'urgente'];

  final String resumen;
  final String nivel; // uno de [levels]
  final List<String> hallazgos;
  final List<String> recomendaciones;
  final List<String> cuandoConsultar;

  const AiInsight({
    required this.resumen,
    required this.nivel,
    required this.hallazgos,
    required this.recomendaciones,
    required this.cuandoConsultar,
  });

  factory AiInsight.fromMap(Map<String, dynamic> m) {
    List<String> list(Object? v) =>
        v is List ? v.whereType<String>().toList() : <String>[];
    final nivel = m['nivel'];
    return AiInsight(
      resumen: (m['resumen'] as String?) ?? '',
      nivel: levels.contains(nivel) ? nivel as String : 'info',
      hallazgos: list(m['hallazgos']),
      recomendaciones: list(m['recomendaciones']),
      cuandoConsultar: list(m['cuando_consultar']),
    );
  }
}

class AiInsightException implements Exception {
  final String message;
  const AiInsightException(this.message);

  @override
  String toString() => message;
}

// ─────────────────────────────────────────────────────────────────────────────
// LIMPIEZA DEL PAYLOAD
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AiPayload {
  /// Quita nulos, textos vacíos y colecciones vacías (recursivo) para no
  /// gastar tokens ni enviar basura. En las listas se conservan los `null`
  /// internos porque la posición importa (series de 7 días), salvo que la
  /// lista entera esté vacía de datos.
  static Map<String, dynamic> clean(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      final cleaned = _cleanValue(value);
      if (cleaned != null) out[key] = cleaned;
    });
    return out;
  }

  static dynamic _cleanValue(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    if (v is double && (v.isNaN || v.isInfinite)) return null;
    if (v is Map) {
      final m = clean(Map<String, dynamic>.from(v));
      return m.isEmpty ? null : m;
    }
    if (v is Iterable) {
      final l = v.map(_cleanValue).toList();
      return l.every((e) => e == null) ? null : l;
    }
    return v;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICIO
// ─────────────────────────────────────────────────────────────────────────────

/// Llama a la Cloud Function `analyzeHealth`. Las claves de los proveedores
/// viven solo en el backend: la app nunca las ve.
class AiInsightService {
  AiInsightService._();
  static final AiInsightService instance = AiInsightService._();

  static const _maxPayloadChars = 8000;
  static const _maxCacheEntries = 20;

  /// Cache en memoria: los mismos datos no se vuelven a analizar (ahorra
  /// costo y cuota diaria).
  final Map<String, AiInsight> _cache = {};

  /// [kind]: 'triaje' | 'emocional' | 'metricas'.
  /// [subject]: datos mínimos de contexto (ej. `{'tipo': 'persona'}`); no
  /// mandes el nombre.
  /// [redFlags]: alertas detectadas por reglas fijas de la app. El servidor
  /// fuerza el nivel "urgente" si vienen.
  Future<AiInsight> analyze({
    required String kind,
    required String profileId,
    required Map<String, dynamic> subject,
    required Map<String, dynamic> data,
    List<String> redFlags = const [],
  }) async {
    final payload = AiPayload.clean(data);
    final encoded = jsonEncode(payload);
    if (encoded.length > _maxPayloadChars) {
      throw const AiInsightException(
        'Hay demasiada información para analizar de una vez.',
      );
    }

    final cacheKey = '$kind|$profileId|$encoded|${redFlags.join(';')}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'analyzeHealth',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      final res = await callable.call({
        'kind': kind,
        'profileId': profileId,
        'subject': subject,
        'data': payload,
        'redFlags': redFlags,
      });
      final insight = AiInsight.fromMap(
        Map<String, dynamic>.from(res.data as Map),
      );

      if (_cache.length >= _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      _cache[cacheKey] = insight;
      return insight;
    } on FirebaseFunctionsException catch (e) {
      throw AiInsightException(_messageFor(e.code));
    } catch (_) {
      throw const AiInsightException(
        'No se pudo generar la orientación. Probá de nuevo en un rato.',
      );
    }
  }

  static String _messageFor(String code) {
    switch (code) {
      case 'unauthenticated':
        return 'Iniciá sesión para usar la orientación con IA.';
      case 'permission-denied':
        return 'No tenés permiso para analizar este perfil.';
      case 'resource-exhausted':
        return 'Llegaste al límite diario de análisis. Probá mañana.';
      case 'deadline-exceeded':
      case 'unavailable':
        return 'No hay conexión con el servicio. Revisá tu internet y probá de nuevo.';
      default:
        return 'No se pudo generar la orientación. Probá de nuevo en un rato.';
    }
  }
}