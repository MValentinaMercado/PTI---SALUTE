// lib/core/services/ai_adapters_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:saluteapp/core/models/chat_models.dart';

enum AiProvider { gemini, openAi }

class AiModel {
  final String id;
  final String name;
  final AiProvider provider;

  const AiModel({required this.id, required this.name, required this.provider});
}

/// Error de IA con información útil para distinguir la causa
/// (401 clave inválida, 404 modelo inexistente, 429 cuota, etc.).
/// Nunca incluye claves.
class AiException implements Exception {
  final String message;
  final int? statusCode;

  const AiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

abstract class AiAdapter {
  /// [history] incluye todos los mensajes de la conversación, con el último
  /// mensaje del usuario al final.
  Future<String> sendMessage(List<AiMessage> history, {String? systemPrompt});

  /// Envía una imagen (por ejemplo una receta) junto con una instrucción y
  /// devuelve el texto de la respuesta.
  Future<String> sendImage(
      Uint8List bytes, {
        required String mimeType,
        required String prompt,
        String? systemPrompt,
      });
}

const _requestTimeout = Duration(seconds: 60);

/// Extrae el mensaje de error que devuelven OpenAI y Gemini:
/// `{"error": {"message": "..."}}`.
String _extractApiError(http.Response response) {
  try {
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is Map) {
      final error = body['error'];
      if (error is Map) {
        final msg = error['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
    }
  } catch (_) {}
  return 'sin detalle';
}

Never _throwHttpError(String provider, http.Response response) {
  final detail = _extractApiError(response);
  debugPrint('[$provider] HTTP ${response.statusCode}: $detail');

  final hint = switch (response.statusCode) {
    400 => 'solicitud inválida',
    401 || 403 => 'clave inválida o sin permisos',
    404 => 'modelo inexistente',
    429 => 'cuota agotada o demasiadas solicitudes',
    503 => 'el modelo está saturado, probá de nuevo en un momento',
    >= 500 => 'el proveedor tiene problemas',
    _ => 'error',
  };
  throw AiException(
    'Error en $provider (${response.statusCode}): $hint. $detail',
    statusCode: response.statusCode,
  );
}

Future<http.Response> _post(
    String provider,
    Uri url, {
      required Map<String, String> headers,
      required Object body,
    }) async {
  // Reintenta cuando el proveedor está saturado (503) o falla temporalmente.
  const retryable = {500, 502, 503, 504};
  const maxAttempts = 3;

  for (var attempt = 1; ; attempt++) {
    try {
      final response = await http
          .post(url, headers: headers, body: body)
          .timeout(_requestTimeout);
      if (retryable.contains(response.statusCode) && attempt < maxAttempts) {
        debugPrint(
          '[$provider] HTTP ${response.statusCode}, reintento $attempt/$maxAttempts',
        );
        await Future<void>.delayed(Duration(seconds: attempt * 2));
        continue;
      }
      return response;
    } on TimeoutException {
      throw const AiException('La consulta tardó demasiado. Intentá de nuevo.');
    } catch (e) {
      debugPrint('[$provider] error de red: $e');
      throw const AiException('No se pudo conectar. Revisá tu conexión.');
    }
  }
}

class GeminiAdapter implements AiAdapter {
  final String apiKey;
  final String model;

  GeminiAdapter({required this.apiKey, required this.model});

  Uri get _url => Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
  );

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'x-goog-api-key': apiKey,
  };

  String _parse(http.Response response) {
    if (response.statusCode != 200) _throwHttpError('Gemini', response);
    final data =
    jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    final text =
    data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    if (text != null) return text;

    final blocked = data['promptFeedback']?['blockReason'];
    if (blocked != null) {
      throw AiException('Gemini bloqueó la consulta ($blocked).');
    }
    return 'Sin respuesta';
  }

  @override
  Future<String> sendMessage(
      List<AiMessage> history, {
        String? systemPrompt,
      }) async {
    final response = await _post(
      'Gemini',
      _url,
      headers: _headers,
      body: jsonEncode({
        if (systemPrompt != null)
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
        'contents': history
            .map(
              (m) => {
            'role': m.isUser ? 'user' : 'model',
            'parts': [
              {'text': m.text},
            ],
          },
        )
            .toList(),
      }),
    );
    return _parse(response);
  }

  @override
  Future<String> sendImage(
      Uint8List bytes, {
        required String mimeType,
        required String prompt,
        String? systemPrompt,
      }) async {
    final response = await _post(
      'Gemini',
      _url,
      headers: _headers,
      body: jsonEncode({
        if (systemPrompt != null)
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'inline_data': {
                  'mime_type': mimeType,
                  'data': base64Encode(bytes),
                },
              },
              {'text': prompt},
            ],
          },
        ],
      }),
    );
    return _parse(response);
  }
}

class OpenAiAdapter implements AiAdapter {
  final String apiKey;
  final String model;

  OpenAiAdapter({required this.apiKey, required this.model});

  static final _url = Uri.parse('https://api.openai.com/v1/chat/completions');

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $apiKey',
  };

  String _parse(http.Response response) {
    if (response.statusCode != 200) _throwHttpError('OpenAI', response);
    final data =
    jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return data['choices']?[0]?['message']?['content'] as String? ??
        'Sin respuesta';
  }

  @override
  Future<String> sendMessage(
      List<AiMessage> history, {
        String? systemPrompt,
      }) async {
    final response = await _post(
      'OpenAI',
      _url,
      headers: _headers,
      body: jsonEncode({
        'model': model,
        'messages': [
          if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
          ...history.map((m) => {'role': m.role, 'content': m.text}),
        ],
      }),
    );
    return _parse(response);
  }

  @override
  Future<String> sendImage(
      Uint8List bytes, {
        required String mimeType,
        required String prompt,
        String? systemPrompt,
      }) async {
    final response = await _post(
      'OpenAI',
      _url,
      headers: _headers,
      body: jsonEncode({
        'model': model,
        'messages': [
          if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:$mimeType;base64,${base64Encode(bytes)}',
                },
              },
            ],
          },
        ],
      }),
    );
    return _parse(response);
  }
}

/// Adaptador que delega en la Cloud Function `aiProxy`.
/// Las claves viven solo en el servidor (Firebase Secrets).
class BackendAdapter implements AiAdapter {
  final AiModel model;

  BackendAdapter({required this.model});

  String get _provider => model.provider == AiProvider.gemini ? 'gemini' : 'openai';

  Future<String> _call(Map<String, dynamic> payload) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'aiProxy',
        options: HttpsCallableOptions(timeout: _requestTimeout),
      );
      final result = await callable.call<Map<Object?, Object?>>({
        'provider': _provider,
        'model': model.id,
        ...payload,
      });
      return result.data['text'] as String? ?? 'Sin respuesta';
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[aiProxy] ${e.code}: ${e.message}');
      final hint = switch (e.code) {
        'unauthenticated' => 'Iniciá sesión para usar la IA.',
        'not-found' => 'La función de IA no está desplegada.',
        'resource-exhausted' => 'Cuota agotada o demasiadas solicitudes.',
        'deadline-exceeded' => 'La consulta tardó demasiado.',
        _ => e.message ?? 'Error del servidor de IA.',
      };
      throw AiException('Error del servidor de IA (${e.code}): $hint');
    }
  }

  @override
  Future<String> sendMessage(
      List<AiMessage> history, {
        String? systemPrompt,
      }) {
    return _call({
      if (systemPrompt != null) 'systemPrompt': systemPrompt,
      'messages': history
          .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'text': m.text})
          .toList(),
    });
  }

  @override
  Future<String> sendImage(
      Uint8List bytes, {
        required String mimeType,
        required String prompt,
        String? systemPrompt,
      }) {
    return _call({
      if (systemPrompt != null) 'systemPrompt': systemPrompt,
      'prompt': prompt,
      'image': {'mimeType': mimeType, 'base64': base64Encode(bytes)},
    });
  }
}

class AiFactory {
  // Solo para desarrollo local:
  //   flutter run --dart-define-from-file=env.json
  // En producción dejalas vacías: se usa el backend (Cloud Functions).
  static const _geminiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _openAiKey = String.fromEnvironment('OPENAI_API_KEY');

  // Fuerza el backend aunque haya claves locales:
  //   --dart-define=AI_USE_BACKEND=true
  static const _forceBackend = bool.fromEnvironment('AI_USE_BACKEND');

  static AiAdapter getAdapter(AiModel model) {
    if (_forceBackend) return BackendAdapter(model: model);

    switch (model.provider) {
      case AiProvider.gemini:
        return _geminiKey.isEmpty
            ? BackendAdapter(model: model)
            : GeminiAdapter(apiKey: _geminiKey, model: model.id);
      case AiProvider.openAi:
        return _openAiKey.isEmpty
            ? BackendAdapter(model: model)
            : OpenAiAdapter(apiKey: _openAiKey, model: model.id);
    }
  }
}