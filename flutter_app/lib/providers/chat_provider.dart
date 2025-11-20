import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

class Conversation {
  final int id;
  final String phone;
  final String? title;
  final String? lastMessage;
  final DateTime? updatedAt;

  Conversation({
    required this.id,
    required this.phone,
    this.title,
    this.lastMessage,
    this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    id: j['id'] as int,
    phone: j['phone'] as String,
    title: j['title'] as String?,
    lastMessage: j['lastMessage'] as String?,
    updatedAt: j['updatedAt'] != null ? DateTime.tryParse(j['updatedAt']) : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'phone': phone,
    'title': title,
    'lastMessage': lastMessage,
    'updatedAt': updatedAt?.toIso8601String(),
  };
}

class ChatProvider extends ChangeNotifier {
  final String apiBase; // ex: http://localhost:3000
  ChatProvider({required this.apiBase});

  List<Conversation> _items = [];
  List<Conversation> get items => List.unmodifiable(_items);

  static const _kKey = 'ca_conversations';

  Future<void> init() async {
    await _loadLocal();      // 1) on affiche tout de suite le cache
    unawaited(refreshFromServer()); // 2) puis on rafraîchit depuis l’API
  }

  Future<void> refreshFromServer() async {
    try {
      final r = await http.get(Uri.parse('$apiBase/api/chat/conversations'));
      if (r.statusCode == 200) {
        final List list = jsonDecode(r.body);
        _items = list.map((e) => Conversation.fromJson(e)).toList();
        await _saveLocal();
        notifyListeners();
      }
    } catch (_) {/* ignore réseau */}
  }

  Future<Conversation?> addByPhone(String rawPhone) async {
    try {
      final r = await http.post(
        Uri.parse('$apiBase/api/chat/conversations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': rawPhone}),
      );
      if (r.statusCode == 200 || r.statusCode == 201) {
        final conv = Conversation.fromJson(jsonDecode(r.body));
        final exists = _items.any((c) => c.id == conv.id);
        if (!exists) {
          _items.insert(0, conv);          // ✅ on AJOUTE sans écraser
        } else {
          // met à jour l’existante (ex: lastMessage, updatedAt)
          final i = _items.indexWhere((c) => c.id == conv.id);
          _items[i] = conv;
        }
        await _saveLocal();
        notifyListeners();
        return conv;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kKey,
      jsonEncode(_items.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kKey);
    if (s != null) {
      final List list = jsonDecode(s);
      _items = list.map((e) => Conversation.fromJson(e)).toList();
      notifyListeners();
    }
  }
}
