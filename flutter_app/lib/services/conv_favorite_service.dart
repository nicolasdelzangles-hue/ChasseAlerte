// lib/services/conv_favorite_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ConvFavoriteService {
  final String baseUrl = 'ApiConfig.baseUrl'; // ex: http://localhost:3000/api
  final String token;

  ConvFavoriteService({required this.baseUrl, required this.token});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  /// Liste des ID de conversations mises en favoris par l'utilisateur courant
  Future<List<int>> fetchFavorites() async {
    final r = await http.get(Uri.parse('$baseUrl/conv-favorites'), headers: _headers);
    if (r.statusCode != 200) {
      throw Exception('Chargement favoris impossible (${r.statusCode})');
    }
    final body = jsonDecode(r.body);
    // retourne List<int> (accepte {conversation_id: x} ou x)
    if (body is List) {
      return body
          .map((e) => (e is Map ? e['conversation_id'] : e))
          .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
          .whereType<int>()
          .toList();
    }
    return <int>[];
  }

  /// Toggle serveur : si favori existant -> DELETE, sinon -> POST
  Future<void> toggleFavorite(int conversationId) async {
    // on tente un POST; si 409 -> on DELETE
    final post = await http.post(
      Uri.parse('$baseUrl/conv-favorites'),
      headers: _headers,
      body: jsonEncode({'conversation_id': conversationId}),
    );

    if (post.statusCode == 201) return; // ajouté

    if (post.statusCode == 409) {
      // déjà favori -> on supprime
      final del = await http.delete(
        Uri.parse('$baseUrl/conv-favorites/$conversationId'),
        headers: _headers,
      );
      if (del.statusCode == 200 || del.statusCode == 204) return;
      throw Exception('Suppression favori impossible (${del.statusCode})');
    }

    throw Exception('Maj favori impossible (${post.statusCode})');
  }
}
