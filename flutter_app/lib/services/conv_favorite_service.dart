// lib/services/conv_favorite_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ConvFavoriteService {
  final String baseUrl;   // ex: https://chassealerte.onrender.com
  final String token;

  ConvFavoriteService({required this.baseUrl, required this.token});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  /// Helper pour construire l’URL API
  Uri _u(String path) => Uri.parse('$baseUrl$path');

  /// Liste des ID de conversations mises en favoris
  Future<List<int>> fetchFavorites() async {
    final r = await http.get(
      _u('/api/conv-favorites'),
      headers: _headers,
    );

    if (r.statusCode != 200) {
      throw Exception('Chargement favoris impossible (${r.statusCode})');
    }

    final body = jsonDecode(r.body);

    if (body is List) {
      return body
          .map((e) => (e is Map ? e['conversation_id'] : e))
          .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
          .whereType<int>()
          .toList();
    }

    return <int>[];
  }

  /// Toggle favori serveur
  Future<void> toggleFavorite(int conversationId) async {
    final post = await http.post(
      _u('/api/conv-favorites'),
      headers: _headers,
      body: jsonEncode({'conversation_id': conversationId}),
    );

    if (post.statusCode == 201) return; // ajouté

    if (post.statusCode == 409) {
      // déjà favori -> on supprime
      final del = await http.delete(
        _u('/api/conv-favorites/$conversationId'),
        headers: _headers,
      );
      if (del.statusCode == 200 || del.statusCode == 204) return;

      throw Exception('Suppression favori impossible (${del.statusCode})');
    }

    throw Exception('Maj favori impossible (${post.statusCode})');
  }
}
