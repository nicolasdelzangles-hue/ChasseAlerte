import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkStatusProvider extends ChangeNotifier {
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  late final StreamSubscription<List<ConnectivityResult>> _sub;

  NetworkStatusProvider() {
    // v6 : la stream renvoie List<ConnectivityResult>
    _sub = Connectivity().onConnectivityChanged.listen(_onChange);
    _checkInitial();
  }

  Future<void> _checkInitial() async {
    // v6 : renvoie List<ConnectivityResult>
    final results = await Connectivity().checkConnectivity();
    _updateFromResults(results);
  }

  void _onChange(List<ConnectivityResult> results) {
    _updateFromResults(results);
  }

  void _updateFromResults(List<ConnectivityResult> results) {
    // S’il y a AU MOINS un résultat qui n’est pas "none", on considère qu’on est en ligne
    final hasConnection =
        results.any((r) => r != ConnectivityResult.none);

    if (hasConnection != _isOnline) {
      _isOnline = hasConnection;
      if (kDebugMode) {
        debugPrint('[NetworkStatus] isOnline = $_isOnline, results=$results');
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
