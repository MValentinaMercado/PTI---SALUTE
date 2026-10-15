// lib/core/services/chat_history_repository.dart
import 'dart:convert';

import 'package:saluteapp/core/models/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatHistoryRepository {
  static const _key = 'chat_conversations_v1';

  Future<List<Conversation>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      // Datos corruptos: se ignoran en lugar de romper la pantalla.
      return [];
    }
  }

  Future<void> save(Conversation c) async {
    final all = await loadAll();
    all.removeWhere((x) => x.id == c.id);
    all.add(c);
    await _write(all);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((x) => x.id == id);
    await _write(all);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> _write(List<Conversation> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(all.map((c) => c.toJson()).toList()),
    );
  }
}