// lib/core/services/ai_adapters_service.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:saluteapp/core/models/chat_models.dart';

enum AiProvider { gemini, openAi }

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

class AiFactory {
  static const _geminiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _openAiKey = String.fromEnvironment('OPENAI_API_KEY');

  static AiAdapter getAdapter(AiModel model) {
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