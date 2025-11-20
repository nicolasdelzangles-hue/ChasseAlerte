import 'dart:convert';
import 'package:http/http.dart' as http;

class FavoriteService {
  static const String baseUrl = 'http://localhost:3000'; // adapte si besoin

  static Future<void> toggleFavorite(int userId, int battueId) async {
    final url = Uri.parse('$baseUrl/api/favorites');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'battueId': battueId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Échec lors de l’ajout/retrait du favori');
    }
  }
}
