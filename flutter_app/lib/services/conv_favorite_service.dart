// lib/services/conv_favorite_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ConvFavoriteService {
  /// Exemple attendu : "https://chassealerte.onrender.com"
  final String baseUrl;
  final String token;

  ConvFavoriteService({
    required this.baseUrl,
    required this.token,
  });

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  /// Normalise la base (enlève / final, évite //, pas de /api répété)
  String get _normalizedBase {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    // Si jamais tu passes déjà un /api, on enlève pour ne pas faire /api/api
    if (b.endsWith('/api')) b = b.substring(0, b.length - 4);
    return b;
  }

  Uri _u(String path) => Uri.parse('$_normalizedBase$path');

  /// Liste des ID de conversations mises en favoris
  Future<List<int>> fetchFavorites() async {
    final uri = _u('/api/conv-favorites');
    if (kDebugMode) debugPrint('[FAV] GET $uri');

    final r = await http.get(uri, headers: _headers);

    // 👉 Si la route n'existe pas (backend pas à jour),
    //    on ne bloque pas toute la page, on renvoie une liste vide.
    if (r.statusCode == 404) {
      if (kDebugMode) debugPrint('[FAV] 404 -> aucune route, on renvoie [].');
      return <int>[];
    }

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

  /// Toggle favori serveur (ajouter / retirer)
  Future<void> toggleFavorite(int conversationId) async {
    final uri = _u('/api/conv-favorites');
    if (kDebugMode) {
      debugPrint('[FAV] TOGGLE conv=$conversationId via POST $uri');
    }

    final post = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({'conversation_id': conversationId}),
    );

    if (post.statusCode == 201) return; // ajouté

    if (post.statusCode == 409) {
      // déjà favori -> on supprime
      final delUri = _u('/api/conv-favorites/$conversationId');
      if (kDebugMode) debugPrint('[FAV] DELETE $delUri');

      final del = await http.delete(delUri, headers: _headers);
      if (del.statusCode == 200 || del.statusCode == 204) return;

      throw Exception('Suppression favori impossible (${del.statusCode})');
    }

    // Si la fonctionnalité n’existe pas côté serveur
    if (post.statusCode == 404) {
      throw Exception(
        'Fonction favoris indisponible sur le serveur (404).',
      );
    }

    throw Exception('Maj favori impossible (${post.statusCode})');
  }
}

