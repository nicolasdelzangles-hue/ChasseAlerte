// lib/services/chat_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as sio;

class ChatService {
  ChatService({required this.baseUrl, required this.token});

  /// Exemple : "https://chassealerte.onrender.com"
  /// (SANS /api à la fin, on l’ajoute nous-mêmes)
  final String baseUrl;
  final String token;

  sio.Socket? _socket;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

  /// Helper pour construire les URL de l’API
  Uri _u(String path, [Map<String, String>? q]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: q);
  }

  dynamic _parse(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      String msg = 'Erreur ${r.statusCode}';
      try {
        final body = jsonDecode(r.body);
        if (body is Map && body['message'] != null) {
          msg = body['message'].toString();
        }
      } catch (_) {}
      throw Exception(msg);
    }
    if (r.body.isEmpty) return null;
    return jsonDecode(r.body);
  }

  // ---------- REST ----------

  Future<List<dynamic>> getConversations() async {
    final r = await http.get(
      _u('/api/conversations'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw Exception('getConversations ${r.statusCode}');
    }
    return jsonDecode(r.body) as List<dynamic>;
  }

  Future<void> deleteConversation(int id) async {
    final r = await http.delete(
      _u('/api/conversations/$id'),
      headers: _headers,
    );
    if (r.statusCode != 204 && r.statusCode != 200) {
      throw Exception(
        jsonDecode(r.body)['message'] ?? 'Suppression impossible',
      );
    }
  }

  Future<List<dynamic>> getMessages(
    int conversationId, {
    int? before,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      if (before != null) 'before': before.toString(),
    };

    final uri = _u('/api/messages/$conversationId', params);
    final r = await http.get(uri, headers: _headers);
    return (_parse(r) as List).cast<dynamic>();
  }

  /// Crée (ou récupère) une conversation privée par téléphone.
  /// Renvoie { id, created? }
  Future<Map<String, dynamic>> createConversationByPhone(String e164) async {
    final r = await http.post(
      _u('/api/conversations/by-phone'),
      headers: _headers,
      body: jsonEncode({'phone': e164}),
    );
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw Exception(
        jsonDecode(r.body)['message'] ?? 'Erreur création 1:1',
      );
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendMessage(
    int conversationId,
    String body,
  ) async {
    final r = await http.post(
      _u('/api/messages'),
      headers: _headers,
      body: jsonEncode({'conversationId': conversationId, 'body': body}),
    );
    return (_parse(r) as Map<String, dynamic>);
  }

  // 🔎 map téléphone -> user (id, etc.)
  Future<Map<String, dynamic>?> userByPhone(String e164) async {
    final uri = _u('/api/users/by-phone', {'phone': e164});
    final r = await http.get(uri, headers: _headers);

    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw Exception('Recherche tél. impossible (${r.statusCode})');
    }

    final data = jsonDecode(r.body);
    return (data is Map<String, dynamic>) ? data : null;
  }

  Future<List<Map<String, dynamic>>> searchUsers(String q) async {
    final uri = _u('/api/users/search', {'q': q});
    final r = await http.get(uri, headers: _headers);

    if (r.statusCode != 200) {
      throw Exception('Recherche impossible (${r.statusCode})');
    }

    final data = jsonDecode(r.body);
    if (data is! List) return [];
    return data.cast<Map<String, dynamic>>();
  }

  // 🧑‍🤝‍🧑 crée un groupe avec un titre et une liste d’IDs membres
  Future<Map<String, dynamic>> createGroup({
    required String title,
    required List<int> memberIds,
  }) async {
    final r = await http.post(
      _u('/api/conversations'),
      headers: _headers,
      body: jsonEncode({'title': title, 'memberIds': memberIds}),
    );
    if (r.statusCode != 201) {
      throw Exception(
        jsonDecode(r.body)['message'] ?? 'Erreur création groupe',
      );
    }
    return jsonDecode(r.body) as Map<String, dynamic>; // { id: ... }
  }

  // ---------- Socket.IO ----------

  /// `socketUrl` = ex: "https://chassealerte.onrender.com"
  sio.Socket connectSocket(String socketUrl) {
    dispose(); // nettoie si déjà ouvert

    _socket = sio.io(
      socketUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setReconnectionDelay(500)
          .setReconnectionAttempts(0) // 0 = infini
          .setAuth({'token': token})
          .build(),
    );

    _socket!.connect();
    return _socket!;
  }

  void dispose() {
    _socket
      ?..off('message:new')
      ..off('typing')
      ..off('messages:read')
      ..disconnect()
      ..close();
    _socket = null;
  }

  // --- Listeners ---

  void onNewMessage(
    void Function(int conversationId, Map<String, dynamic> message) cb,
  ) {
    _socket?.off('message:new');
    _socket?.on('message:new', (data) {
      final map = Map<String, dynamic>.from(data);
      cb(
        map['conversationId'] as int,
        Map<String, dynamic>.from(map['message']),
      );
    });
  }

  void onTyping(void Function(int userId, bool isTyping) cb) {
    _socket?.off('typing');
    _socket?.on('typing', (data) {
      final map = Map<String, dynamic>.from(data);
      cb(map['userId'] as int, map['isTyping'] as bool);
    });
  }

  void onMessagesRead(
    void Function(int userId, int lastMessageId) cb,
  ) {
    _socket?.off('messages:read');
    _socket?.on('messages:read', (data) {
      final map = Map<String, dynamic>.from(data);
      cb(
        map['userId'] as int,
        (map['lastMessageId'] as num).toInt(),
      );
    });
  }

  // --- Rooms & events émis ---

  void joinConversationRoom(int conversationId) {
    _socket?.emit('conversation:join', conversationId);
  }

  void leaveConversationRoom(int conversationId) {
    _socket?.emit('conversation:leave', conversationId);
  }

  void sendTyping(int conversationId, bool isTyping) {
    _socket?.emit(
      'typing',
      {'conversationId': conversationId, 'isTyping': isTyping},
    );
  }

  void sendRead(int conversationId, int lastMessageId) {
    _socket?.emit(
      'messages:read',
      {'conversationId': conversationId, 'lastMessageId': lastMessageId},
    );
  }
}
