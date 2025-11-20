import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import '../services/logger.dart';
import '../models/user.dart';
import '../models/battue.dart';

class ApiServices {
  static String? _overrideBase;

  // -------------------- Base & Socket --------------------
  static String get baseUrl => _overrideBase ?? _detectBaseUrl();
  static String get socketUrl => baseUrl;

  static void setBaseUrl(String url) {
    _overrideBase = url; // ex: 'http://192.168.1.50:3000'
  }

  static String _detectBaseUrl() {
    if (kIsWeb) return 'http://localhost:3000';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:3000';
      return 'http://localhost:3000';
    } catch (_) {
      return 'http://localhost:3000';
    }
  }

  // -------------------- Helpers HTTP --------------------
  static Uri _u(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$baseUrl$path')
          .replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  static const _timeout = Duration(seconds: 15);

  static Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    // 🔐 Nouveau : on lit d’abord accessToken, puis ancien "token" pour compatibilité
    final token = prefs.getString('accessToken') ?? prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Never _throwHttp(String label, http.Response r) =>
      throw Exception('$label: ${r.statusCode} ${r.body}');

  // ===================================================================
  // AUTH
  // ===================================================================

  /// LOGIN
  /// Le backend renvoie maintenant un JSON du type :
  /// {
  ///   "accessToken": "...",
  ///   "refreshToken": "...",
  ///   "user": { ... }
  /// }
  /// On renvoie ce Map tel quel à AuthProvider.
  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final r = await http
        .post(
          _u('/api/auth/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim().toLowerCase(),
            'password': password,
          }),
        )
        .timeout(_timeout);

    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return data;
    }
    if (r.statusCode == 401) throw Exception('Identifiants incorrects');
    _throwHttp('Échec login', r);
  }

  /// REFRESH TOKEN
  /// Utilisée par AuthProvider.refreshAccessToken(refreshToken)
  /// Renvoie un Map contenant au minimum { "accessToken": "..." }
  static Future<Map<String, dynamic>> refreshToken(
      String refreshToken) async {
    final r = await http
        .post(
          _u('/api/auth/refresh'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        )
        .timeout(_timeout);

    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return data;
    }
    if (r.statusCode == 401) {
      throw Exception('Refresh token invalide ou expiré');
    }
    _throwHttp('Échec refreshToken', r);
  }

  static Future<bool> register({
    required String firstName,
    required String lastName,
    required String phone,
    required String address,
    required String postalCode,
    required String city,
    required String permitNumber, // 14 chiffres
    required String email,
    required String password,
  }) async {
    final body = {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'address': address,
      'postal_code': postalCode,
      'city': city,
      'permit_number': permitNumber,
      'email': email.trim().toLowerCase(),
      'password': password,
    };

    final r = await http
        .post(
          _u('/api/register'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (r.statusCode == 201) return true;

    if (r.statusCode == 400) {
      final m = jsonDecode(r.body);
      throw Exception(
        m is Map && m['errors'] != null
            ? (m['errors'] as List).join(' • ')
            : 'Champs invalides',
      );
    }
    if (r.statusCode == 409) {
      final m = jsonDecode(r.body);
      throw Exception(
        m is Map && m['message'] != null ? m['message'] : 'Conflit (doublon)',
      );
    }
    _throwHttp('Échec register', r);
  }

  static Future<void> postReport({
    required String reportedFirstName,
    required String reportedLastName,
    required String category,
    required String description,
    String? location,
    String? incidentAt, // <-- ICI on déclare bien incidentAt
    bool isAnonymous = true,
    bool muted = false,
    bool blocked = false,
  }) async {
    final body = {
      'reported_first_name': reportedFirstName,
      'reported_last_name': reportedLastName,
      'category': category,
      'description': description,
      'location': location,
      'incident_at': incidentAt, // <-- envoyé à l’API sous ce nom
      'is_anonymous': isAnonymous,
      'muted': muted,
      'blocked': blocked,
    };

    final res = await http.post(
      _u('/api/reports'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Erreur API reports: ${res.statusCode} ${res.body}');
    }
  }

  // ------- PROFIL (moi) -------
  static Future<User> getProfile() async {
    final r = await http
        .get(_u('/api/users/me'), headers: await _authHeaders())
        .timeout(_timeout);

    if (r.statusCode == 200) {
      final map = jsonDecode(r.body) as Map<String, dynamic>;
      return User.fromJson(map);
    }
    if (r.statusCode == 401) throw Exception('Session expirée');
    _throwHttp('Échec getProfile', r);
  }

  // ------- NOUVEAU : liste “safe” de tous les utilisateurs -------
  static Future<List<User>> getUsers() async {
    final r = await http
        .get(_u('/api/users'), headers: await _authHeaders())
        .timeout(_timeout);

    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      if (data is List) {
        return data
            .map((e) => User.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return <User>[];
    }
    if (r.statusCode == 401) throw Exception('Session expirée');
    _throwHttp('Échec getUsers', r);
  }

  // ===================================================================
  // BATTUES
  // ===================================================================
  static Future<List<Battue>> getBattues() async {
    final r = await http
        .get(_u('/api/battues'), headers: await _authHeaders())
        .timeout(_timeout);

    if (r.statusCode == 200) {
      final list = jsonDecode(r.body) as List;
      return list
          .map((e) => Battue.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (r.statusCode == 401) throw Exception('Session expirée');
    _throwHttp('Échec getBattues', r);
  }

  static Future<void> addBattue(Map<String, dynamic> newBattueData) async {
    final r = await http
        .post(
          _u('/api/battues'),
          headers: await _authHeaders(),
          body: jsonEncode(newBattueData),
        )
        .timeout(_timeout);

    if (r.statusCode == 201) return;
    if (r.statusCode == 401) throw Exception('Session expirée');
    if (r.statusCode == 403) {
      throw Exception('Action réservée aux administrateurs.');
    }
    _throwHttp('Échec addBattue', r);
  }

  static Future<bool> deleteBattue(String battueId) async {
    final r = await http
        .delete(_u('/api/battues/$battueId'), headers: await _authHeaders())
        .timeout(_timeout);

    if (r.statusCode == 200 || r.statusCode == 204) return true;
    if (r.statusCode == 404) return false;
    if (r.statusCode == 401) throw Exception('Session expirée');
    if (r.statusCode == 403) {
      throw Exception('Action réservée aux administrateurs.');
    }
    _throwHttp('Échec deleteBattue', r);
  }

  // ===================================================================
  // FAVORIS DE BATTUES (HomeScreen)
  // ===================================================================
  static Future<List<Battue>> getFavoriteBattues() async {
    final r = await http
        .get(_u('/api/favorites'), headers: await _authHeaders())
        .timeout(_timeout);

    if (r.statusCode == 200) {
      final list = jsonDecode(r.body) as List;
      return list
          .map((e) => Battue.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (r.statusCode == 401) throw Exception('Session expirée');
    _throwHttp('Échec chargement des favoris', r);
  }

  /// Toggle robuste : tente l’ajout, si 409 on supprime.
  static Future<void> toggleBattueFavorite(int battueId) async {
    final add = await http
        .post(
          _u('/api/favorites'),
          headers: await _authHeaders(),
          body: jsonEncode({'battue_id': battueId}),
        )
        .timeout(_timeout);

    if (add.statusCode == 201) return; // ajouté
    if (add.statusCode == 409) {
      final del = await http
          .delete(_u('/api/favorites/$battueId'),
              headers: await _authHeaders())
          .timeout(_timeout);
      if (del.statusCode == 200 || del.statusCode == 204) return;
      _throwHttp('Échec retrait favori', del);
    }

    if (add.statusCode == 401) throw Exception('Session expirée');
    _throwHttp('Échec ajout/retrait favori', add);
  }

  // ===================================================================
  // FAVORIS DE CONVERSATIONS (ChatList)
  // ===================================================================

  static Future<List<int>> getConvFavorites() async {
    final r = await http
        .get(_u('/api/conv-favorites'), headers: await _authHeaders())
        .timeout(_timeout);

    if (r.statusCode != 200) {
      _throwHttp('Chargement favoris impossible', r);
    }

    final data = jsonDecode(r.body);
    if (data is! List) return <int>[];

    return data
        .map<int>((e) {
          if (e is int) return e;
          if (e is Map && e['conversation_id'] != null) {
            final v = e['conversation_id'];
            return v is int ? v : int.tryParse('$v') ?? 0;
          }
          final v = (e is Map ? e['id'] : null);
          if (v is int) return v;
          return int.tryParse('$v') ?? 0;
        })
        .where((id) => id > 0)
        .toList();
  }

  static Future<void> addConvFavorite(int conversationId) async {
    final r = await http
        .post(
          _u('/api/conv-favorites'),
          headers: await _authHeaders(),
          body: jsonEncode({'conversation_id': conversationId}),
        )
        .timeout(_timeout);

    if (r.statusCode == 201 || r.statusCode == 409) return;
    _throwHttp('Ajout favori impossible', r);
  }

  static Future<void> removeConvFavorite(int conversationId) async {
    final r = await http
        .delete(_u('/api/conv-favorites/$conversationId'),
            headers: await _authHeaders())
        .timeout(_timeout);

    if (r.statusCode == 204) return;
    _throwHttp('Retrait favori impossible', r);
  }

  // -------------------------------------------------------
  // Profil (PUT) - déjà utilisé par EditProfileScreen
  // -------------------------------------------------------
  static Future<User> updateProfile(Map<String, dynamic> data) async {
    final r = await http
        .put(
          _u('/api/users/me'),
          headers: await _authHeaders(),
          body: jsonEncode(data),
        )
        .timeout(_timeout);

    if (r.statusCode == 200) {
      final map = jsonDecode(r.body) as Map<String, dynamic>;
      return User.fromJson(map);
    }
    if (r.statusCode == 401) throw Exception('Session expirée');
    _throwHttp('Échec updateProfile', r);
  }

  static Future<void> toggleConvFavorite(int conversationId) async {
    final r = await http
        .post(
          _u('/api/conv-favorites'),
          headers: await _authHeaders(),
          body: jsonEncode({'conversation_id': conversationId}),
        )
        .timeout(_timeout);

    if (r.statusCode == 201) return; // ajouté
    if (r.statusCode == 409) {
      await removeConvFavorite(conversationId); // déjà favori -> on retire
      return;
    }
    _throwHttp('Toggle favori impossible', r);
  }

  // ===================================================================
  // GÉOCODAGE (PROXY SERVEUR) — AJOUT SANS CASSER
  // ===================================================================
  static Future<Map<String, dynamic>> geocodeAddress(String address) async {
    logI('GEO', 'submit address="$address"');
    try {
      final uri = _u('/api/geocode', {'q': address}); // 'q' côté backend
      logI('HTTP', 'GET $uri');
      final r = await http.get(uri).timeout(_timeout);
      logI('HTTP', 'STATUS ${r.statusCode} for $uri');

      final data = r.body.isEmpty ? null : jsonDecode(r.body);
      logI('HTTP', 'BODY ${r.body.length} chars');

      if (r.statusCode == 200 && data is Map<String, dynamic>) {
        logI('GEO',
            'ok lat=${data['lat']} lon=${data['lon']} name="${data['displayName']}"');
        return data;
      }
      final msg = (data is Map &&
                  (data['error'] != null ? data['error'] : data['message'])) ??
          'Échec géocodage';
      logI('GEO', 'error: $msg');
      throw Exception(msg);
    } catch (e) {
      logI('GEO', 'exception: $e');
      rethrow;
    }
  }

  static Future<List<dynamic>> placesAutocomplete(String input) async {
    logI('PLACES', 'input="$input"');
    final uri = _u('/api/places', {'input': input});
    logI('HTTP', 'GET $uri');
    final r = await http.get(uri).timeout(_timeout);
    logI('HTTP', 'STATUS ${r.statusCode} for $uri');
    final data = jsonDecode(r.body);
    logI('PLACES',
        'status=${data['status']} count=${(data['predictions'] as List?)?.length ?? 0}');
    if (r.statusCode != 200) throw Exception('Places HTTP ${r.statusCode}');
    return (data['predictions'] as List?) ?? [];
  }

  static Future<Map<String, dynamic>> placeDetails(String placeId) async {
    logI('DETAILS', 'place_id=$placeId');
    final uri = _u('/api/place-details', {'place_id': placeId});
    logI('HTTP', 'GET $uri');
    final r = await http.get(uri).timeout(_timeout);
    logI('HTTP', 'STATUS ${r.statusCode} for $uri');
    final data = jsonDecode(r.body);
    logI('DETAILS',
        'status=${data['status']} hasResult=${data['result'] != null}');
    if (r.statusCode != 200) throw Exception('Details HTTP ${r.statusCode}');
    return data;
  }

  static Future<Map<String, dynamic>> getBattueSeries({
    required int battueId,
    String granularity = 'day', // 'day' | 'month'
  }) async {
    final uri = Uri.parse('$baseUrl/api/battues/$battueId/stats/series')
        .replace(queryParameters: {'granularity': granularity});

    final headers = await authHeaders();
    final r = await http.get(uri, headers: headers).timeout(_timeout);

    if (r.statusCode != 200) {
      throw 'HTTP ${r.statusCode} ${r.body}';
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<Map<String, String>> authHeaders() => _authHeaders();

  static Future<void> saveBattueStat(
      int battueId, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl/api/battues/$battueId/stats');
    final headers = await authHeaders();
    final r = await http
        .post(uri,
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(_timeout);
    if (r.statusCode != 200) {
      throw 'HTTP ${r.statusCode} ${r.body}';
    }
  }

  static Future<List<Map<String, dynamic>>> getReports() async {
    final res =
        await http.get(_u('/api/reports')).timeout(_timeout);
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return List<Map<String, dynamic>>.from(data);
    } else {
      throw Exception('Erreur lors du chargement des signalements');
    }
  }

  // Helper debug (optionnel) - je corrige l’URL pour coller à ton backend
  static Future<User> getProfile2() async {
    final response =
        await http.get(_u('/api/users/me'), headers: await _authHeaders());

    print("=== [API] Profil brut (getProfile2) ===");
    print(response.body);

    if (response.statusCode != 200) {
      throw Exception(
        'Erreur lors du chargement du profil (${response.statusCode})',
      );
    }

    final data = jsonDecode(response.body);
    print("=== [API] JSON décodé (getProfile2) ===");
    print(data);

    return User.fromJson(data as Map<String, dynamic>);
  }
}
