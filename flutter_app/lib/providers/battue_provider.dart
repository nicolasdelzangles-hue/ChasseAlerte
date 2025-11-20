import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/battue.dart';
import '../services/api_services.dart';

class BattueProvider with ChangeNotifier {
  List<Battue> _battues = [];
  bool _isLoading = false;
  bool _loadedFromCache = false;
  String? _error;

  // Box Hive pour le cache
  final Box _box = Hive.box('battuesBox');

  List<Battue> get battues => _battues;
  bool get isLoading => _isLoading;
  bool get loadedFromCache => _loadedFromCache;
  String? get error => _error;

  /// Si tu appelles sans paramètre, on garde le comportement "online"
  Future<void> fetchBattues({bool? isOnline}) async {
    final online = isOnline ?? true;

    _isLoading = true;
    _error = null;
    _loadedFromCache = false;
    notifyListeners();

    try {
      if (online) {
        // ---- Mode ONLINE : API + mise à jour du cache ----
        if (kDebugMode) debugPrint('[BattueProvider] fetchBattues ONLINE');
        final remote = await ApiServices.getBattues();
        _battues = remote;

        // On stocke en cache (liste de JSON)
        final jsonList = remote.map((b) => b.toJson()).toList();
        await _box.put('battues_list', jsonList);
      } else {
        // ---- Mode OFFLINE : lecture du cache ----
        if (kDebugMode) debugPrint('[BattueProvider] fetchBattues OFFLINE');
        final cached = _box.get('battues_list');

        if (cached != null) {
          final list = (cached as List)
              .map((e) => Battue.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _battues = list;
          _loadedFromCache = true;
        } else {
          if (kDebugMode) {
            debugPrint('[BattueProvider] aucun cache disponible');
          }
          _battues = [];
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erreur chargement battues: $e');
      }
      _error = e.toString();
      _battues = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
