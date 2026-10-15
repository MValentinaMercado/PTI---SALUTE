// lib/core/models/chat_models.dart

class AiMessage {
  /// 'user' | 'assistant'
  final String role;
  final String text;
  final DateTime createdAt;

  const AiMessage({
    required this.role,
    required this.text,
    required this.createdAt,
  });

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
    role: j['role'] as String,
    text: j['text'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

class Conversation {
  final String id;

  /// Corresponde a AiModel.id (por ejemplo 'gemini-2.5-flash').
  final String aiId;
  String title;
  DateTime updatedAt;
  final List<AiMessage> messages;

  Conversation({
    required this.id,
    required this.aiId,
    required this.title,
    required this.updatedAt,
    List<AiMessage>? messages,
  }) : messages = messages ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'aiId': aiId,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    id: j['id'] as String,
    aiId: j['aiId'] as String,
    title: j['title'] as String,
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    messages: (j['messages'] as List)
        .map((m) => AiMessage.fromJson(m as Map<String, dynamic>))
        .toList(),
  );
}