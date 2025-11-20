import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../services/api_services.dart';

class AuthProvider with ChangeNotifier {
  // ====== TOKENS & USER ======
  String? _accessToken;
  String? _refreshToken;
  User? _currentUser;

  // ====== INACTIVITÉ ======
  Timer? _inactivityTimer;

  /// Tu peux réduire à 10 minutes si tu veux :
  /// Duration _inactivity = const Duration(minutes: 10);
  Duration _inactivity = const Duration(minutes: 30);

  // ---- Getters publics ----
  String? get token => _accessToken; // compat ancien nom
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  User? get currentUser => _currentUser;
  User? get user => _currentUser; // alias
  bool get isLoggedIn => _accessToken != null;
  bool get isAuthenticated => isLoggedIn; // alias
  Duration get inactivityDuration => _inactivity;

  /// 👉 Affiche/masque les actions Admin dans l’UI
  bool get isAdmin {
    final r = (_currentUser?.role ?? '').toLowerCase();
    if (r.isNotEmpty) return r == 'admin';
    final fromJwt = _roleFromToken(_accessToken)?.toLowerCase();
    return fromJwt == 'admin';
  }

  // Récupération de token pour les services (compat ancienne API)
  Future<String?> getToken() async {
    if (_accessToken != null) return _accessToken;
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('accessToken') ?? prefs.getString('token');
    return _accessToken;
  }

  // =========================================================
  //               CYCLE DE VIE / INIT / LOGIN
  // =========================================================

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // On lit d’abord les nouveaux noms, puis l’ancien "token" pour compat
    _accessToken = prefs.getString('accessToken') ?? prefs.getString('token');
    _refreshToken = prefs.getString('refreshToken');

    // Charger l’utilisateur si déjà stocké
    final userJson = prefs.getString('user');
    if (userJson != null) {
      try {
        _currentUser = User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      } catch (e) {
        if (kDebugMode) debugPrint('Erreur parse user from prefs: $e');
      }
    }

    // Si on a un accessToken mais pas de user, on tente un /me
    if (_accessToken != null && _currentUser == null) {
      try {
        _currentUser = await ApiServices.getProfile();
        await _persistUser(_currentUser);
        _startInactivityTimer();
      } catch (_) {
        await logout(silent: true);
      }
    } else if (_accessToken != null && _currentUser != null) {
      _startInactivityTimer();
    }

    notifyListeners();
  }

  Future<bool> tryAutoLogin() async {
    await initialize();
    return isLoggedIn;
  }

  /// LOGIN :
  /// ApiServices.login DOIT maintenant renvoyer un objet contenant :
  /// { "accessToken": String, "refreshToken": String, "user": Map }
  Future<bool> login(String email, String password) async {
    try {
      final loginResult = await ApiServices.login(email, password);

      // loginResult peut être un Map<String, dynamic> ou un petit modèle dédié.
      // Ici on suppose un Map.
      final accessToken = loginResult['accessToken'] as String?;
      final refreshToken = loginResult['refreshToken'] as String?;
      final userMap = loginResult['user'] as Map<String, dynamic>?;

      if (accessToken == null || refreshToken == null) {
        throw Exception('Réponse login invalide (tokens manquants)');
      }

      _accessToken = accessToken;
      _refreshToken = refreshToken;
      _currentUser = userMap != null ? User.fromJson(userMap) : null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('accessToken', _accessToken!);
      await prefs.setString('refreshToken', _refreshToken!);
      if (_currentUser != null) {
        await _persistUser(_currentUser);
      }

      _restartInactivityTimer();
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Login error: $e');
      return false;
    }
  }

  Future<void> logout({bool silent = false}) async {
    _cancelInactivityTimer();
    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');         // ancien nom
      await prefs.remove('accessToken');   // nouveau
      await prefs.remove('refreshToken');
      await prefs.remove('user');
    } catch (_) {}

    if (!silent) notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (_accessToken == null) return;
    try {
      _currentUser = await ApiServices.getProfile();
      await _persistUser(_currentUser);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('refreshProfile error: $e');
    }
  }

  Future<void> _persistUser(User? user) async {
  if (user == null) return;
  final prefs = await SharedPreferences.getInstance();

  // ✅ Adapte cette map aux champs réels de ton modèle User
  final map = <String, dynamic>{
    'id': user.id,
    'first_name': user.firstName,
    'last_name': user.lastName,
    'name': user.name,
    'email': user.email,
    'phone': user.phone,
    'role': user.role,
  };

  await prefs.setString('user', jsonEncode(map));
}


  // =========================================================
  //                 REFRESH ACCESS TOKEN
  // =========================================================

  bool _isRefreshing = false;

  /// Appelée par ApiServices quand il reçoit un 401
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null || _isRefreshing) return false;

    _isRefreshing = true;
    try {
      final res = await ApiServices.refreshToken(_refreshToken!);
      // ApiServices.refreshToken doit renvoyer { "accessToken": "..." }
      final newAccessToken = res['accessToken'] as String?;
      if (newAccessToken == null) throw Exception('refreshToken: accessToken manquant');

      _accessToken = newAccessToken;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('accessToken', _accessToken!);

      _isRefreshing = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('refreshAccessToken error: $e');
      _isRefreshing = false;
      await logout(silent: false);
      return false;
    }
  }

  // =========================================================
  //                      INACTIVITÉ
  // =========================================================

  void setInactivityDuration(Duration d) {
    _inactivity = d;
    if (isLoggedIn) _restartInactivityTimer();
  }

  void resetInactivityTimer() => _restartInactivityTimer();

  void _startInactivityTimer() {
    _inactivityTimer = Timer(_inactivity, () async {
      if (kDebugMode) debugPrint('🔒 Déconnexion automatique après inactivité');
      await logout();
    });
  }

  void _restartInactivityTimer() {
    _cancelInactivityTimer();
    if (isLoggedIn) _startInactivityTimer();
  }

  void _cancelInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  // =========================================================
  //                      HELPERS
  // =========================================================

  String? _roleFromToken(String? token) {
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      String normalize(String s) {
        final r = s.length % 4;
        if (r == 2) s += '==';
        if (r == 3) s += '=';
        return s.replaceAll('-', '+').replaceAll('_', '/');
      }

      final payload = json.decode(
        utf8.decode(base64.decode(normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final role = payload['role'];
      return role is String ? role : role?.toString();
    } catch (_) {
      return null;
    }
  }
}
