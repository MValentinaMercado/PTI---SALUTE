// lib/core/services/ai_adapters_service.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:saluteapp/core/models/chat_models.dart';

enum AiProvider { gemini, openAi, anthropic }

class AiModel {
  final String id;
  final String name;
  final AiProvider provider;

  const AiModel({required this.id, required this.name, required this.provider});
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

class BackendAiAdapter implements AiAdapter {
  final Uri endpoint;
  final AiModel model;
  final http.Client _client;

  BackendAiAdapter({
    required this.endpoint,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<String> sendMessage(
      List<AiMessage> history, {
        String? systemPrompt,
      }) async {
    final response = await _client.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': model.id,
        'provider': model.provider.name,
        if (systemPrompt != null) 'system': systemPrompt,
        'messages': history
            .map((m) => {'role': m.role, 'content': m.text})
            .toList(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Error del backend de IA: ${response.statusCode}');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic> || data['response'] is! String) {
      throw const FormatException('Respuesta inválida del backend de IA.');
    }
    return data['response'] as String;
  }

  /// El backend debe adjuntar `image` al último mensaje del usuario con el
  /// formato propio de cada proveedor.
  @override
  Future<String> sendImage(
      Uint8List bytes, {
        required String mimeType,
        required String prompt,
        String? systemPrompt,
      }) async {
    final response = await _client.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': model.id,
        'provider': model.provider.name,
        if (systemPrompt != null) 'system': systemPrompt,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'image': {'mimeType': mimeType, 'data': base64Encode(bytes)},
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Error del backend de IA: ${response.statusCode}');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic> || data['response'] is! String) {
      throw const FormatException('Respuesta inválida del backend de IA.');
    }
    return data['response'] as String;
  }
}

class GeminiAdapter implements AiAdapter {
  final String apiKey;
  final String model;

  GeminiAdapter({required this.apiKey, required this.model});

  @override
  Future<String> sendMessage(
      List<AiMessage> history, {
        String? systemPrompt,
      }) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
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

    if (response.statusCode != 200) {
      throw Exception('Error en Gemini: ${response.statusCode}');
    }
    final data =
    jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return data['candidates']?[0]?['content']?['parts']?[0]?['text']
    as String? ??
        'Sin respuesta';
  }

  @override
  Future<String> sendImage(
      Uint8List bytes, {
        required String mimeType,
        required String prompt,
        String? systemPrompt,
      }) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
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

    if (response.statusCode != 200) {
      throw Exception('Error en Gemini: ${response.statusCode}');
    }
    final data =
    jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return data['candidates']?[0]?['content']?['parts']?[0]?['text']
    as String? ??
        'Sin respuesta';
  }
}

class OpenAiAdapter implements AiAdapter {
  final String apiKey;
  final String model;

  OpenAiAdapter({required this.apiKey, required this.model});

  @override
  Future<String> sendMessage(
      List<AiMessage> history, {
        String? systemPrompt,
      }) async {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
          ...history.map((m) => {'role': m.role, 'content': m.text}),
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Error en OpenAI: ${response.statusCode}');
    }
    final data =
    jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return data['choices']?[0]?['message']?['content'] as String? ??
        'Sin respuesta';
  }

  @override
  Future<String> sendImage(
      Uint8List bytes, {
        required String mimeType,
        required String prompt,
        String? systemPrompt,
      }) async {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
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

    if (response.statusCode != 200) {
      throw Exception('Error en OpenAI: ${response.statusCode}');
    }
    final data =
    jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return data['choices']?[0]?['message']?['content'] as String? ??
        'Sin respuesta';
  }
}

class ClaudeAdapter implements AiAdapter {
  final String apiKey;
  final String model;

  ClaudeAdapter({required this.apiKey, required this.model});

  @override
  Future<String> sendMessage(
      List<AiMessage> history, {
        String? systemPrompt,
      }) async {
    final response = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 1024,
        if (systemPrompt != null) 'system': systemPrompt,
        // La API exige que el primer mensaje sea del usuario.
        'messages': history
            .skipWhile((m) => !m.isUser)
            .map((m) => {'role': m.role, 'content': m.text})
            .toList(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Error en Claude: ${response.statusCode}');
    }
    final data =
    jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final content = data['content'] as List?;
    return content?.isNotEmpty == true
        ? content!.first['text'] as String? ?? 'Sin respuesta'
        : 'Sin respuesta';
  }

  @override
  Future<String> sendImage(
      Uint8List bytes, {
        required String mimeType,
        required String prompt,
        String? systemPrompt,
      }) async {
    final response = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 2048, // las recetas largas necesitan más espacio
        if (systemPrompt != null) 'system': systemPrompt,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': mimeType,
                  'data': base64Encode(bytes),
                },
              },
              {'type': 'text', 'text': prompt},
            ],
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Error en Claude: ${response.statusCode}');
    }
    final data =
    jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final content = data['content'] as List?;
    return content?.isNotEmpty == true
        ? content!.first['text'] as String? ?? 'Sin respuesta'
        : 'Sin respuesta';
  }
}

class AiFactory {
  static const _geminiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _openAiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const _claudeKey = String.fromEnvironment('ANTHROPIC_API_KEY');
  static const _backendUrl = String.fromEnvironment('AI_BACKEND_URL');

  /// En producción usá siempre [AI_BACKEND_URL]: las claves compiladas con
  /// String.fromEnvironment quedan dentro del APK y pueden extraerse.
  static AiAdapter getAdapter(AiModel model) {
    if (_backendUrl.isNotEmpty) {
      return BackendAiAdapter(endpoint: Uri.parse(_backendUrl), model: model);
    }
    switch (model.provider) {
      case AiProvider.gemini:
        return GeminiAdapter(
          apiKey: _requiredKey(_geminiKey, model.name),
          model: model.id,
        );
      case AiProvider.openAi:
        return OpenAiAdapter(
          apiKey: _requiredKey(_openAiKey, model.name),
          model: model.id,
        );
      case AiProvider.anthropic:
        return ClaudeAdapter(
          apiKey: _requiredKey(_claudeKey, model.name),
          model: model.id,
        );
    }
  }

  static String _requiredKey(String key, String modelName) {
    if (key.isEmpty) {
      throw StateError(
        'No hay una clave configurada para $modelName. '
            'Configurá el backend de IA antes de usar este proveedor.',
      );
    }
    return key;
  }
}