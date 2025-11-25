// lib/services/meteo_france_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart'; // <---- ajouté
import 'api_services.dart';

// ---------------- Helpers ----------------
double _toDouble(Object? v) => (v is num) ? v.toDouble() : double.nan;
String _toString(Object? v) => v?.toString() ?? '';

DateTime _parseDateOrNow(Object? v) {
  final s = _toString(v);
  final dt = s.isEmpty ? null : DateTime.tryParse(s);
  return (dt ?? DateTime.now()).toLocal();
}

// ---------------- Helpers robustes pour les codes météo ----------------
int? _asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

int? _pickWeatherCodeFromMap(Map m) {
  const candidates = [
    'weather', 'weather12H', 'weatherDay', 'code', 'conditionCode', 'wx',
    'symbol', 'iconCode'
  ];
  for (final k in candidates) {
    if (m.containsKey(k)) {
      final c = _asInt(m[k]);
      if (c != null) return c;
    }
  }
  return null;
}

int _dominantCode(Iterable<int> codes) {
  final c = codes.where((e) => e >= 0 && e <= 199).toList();
  if (c.isEmpty) return 3; // nuageux par défaut

  bool any(bool Function(int) f) => c.any(f);

  if (any((x) => x >= 90 && x <= 99)) return 95;
  if (any((x) => (x >= 60 && x <= 69) || (x >= 70 && x <= 79))) return 65;
  if (any((x) =>
      [5, 6, 7, 10].contains(x) || (x >= 40 && x <= 49) || (x >= 80 && x <= 84))) {
    return 41;
  }
  if (any((x) => x == 20 || x == 30 || x == 31)) return 20;
  if (any((x) => x >= 1 && x <= 4)) return 3;
  if (any((x) => x == 0)) return 0;
  return 3;
}

// ----------------- Modèles -----------------
class WeatherDay {
  final DateTime date;
  final double tMin;
  final double tMax;
  final double windKmh;
  final int code;
  final String label;

  WeatherDay({
    required this.date,
    required this.tMin,
    required this.tMax,
    required this.windKmh,
    required this.code,
    required this.label,
  });

  factory WeatherDay.fromJson(Map j) {
    final m = j.cast<String, dynamic>();
    int? code = _pickWeatherCodeFromMap(m);

    if (code == null) {
      final hours = (m['hours'] ?? m['timeseries'] ?? m['timeline']);
      if (hours is List) {
        final list = <int>[];
        for (final h in hours) {
          if (h is Map) {
            final ch = _pickWeatherCodeFromMap(h);
            if (ch != null) list.add(ch);
          }
        }
        if (list.isNotEmpty) code = _dominantCode(list);
      }
    }

    code ??= 3;
    final wd = WeatherDay(
      date: _parseDateOrNow(m['date'] ?? m['datetime'] ?? m['time'] ?? m['day']),
      tMin: _toDouble(m['tmin']),
      tMax: _toDouble(m['tmax']),
      windKmh: m.containsKey('wind_kmh')
          ? _toDouble(m['wind_kmh'])
          : (m.containsKey('wind10m') ? _toDouble(m['wind10m']) : double.nan),
      code: code,
      label: _toString(m['label']),
    );

    if (kDebugMode) {
      debugPrint('[WEEK DAY] ${wd.date.toIso8601String()} '
          'code=${wd.code} t=${wd.tMin}/${wd.tMax} wind=${wd.windKmh} label="${wd.label}"');
    }
    return wd;
  }
}

class WeatherCurrent {
  final double temp;
  final int? code;
  final double windKmh;
  final String label;

  WeatherCurrent({
    required this.temp,
    required this.code,
    required this.windKmh,
    required this.label,
  });

  factory WeatherCurrent.fromJson(Map j) {
    final m = j.cast<String, dynamic>();
    final c = _pickWeatherCodeFromMap(m);

    final wc = WeatherCurrent(
      temp: m.containsKey('temp') ? _toDouble(m['temp']) : double.nan,
      code: c,
      windKmh: m.containsKey('wind_kmh')
          ? _toDouble(m['wind_kmh'])
          : (m.containsKey('wind10m') ? _toDouble(m['wind10m']) : double.nan),
      label: _toString(m['label']),
    );

    if (kDebugMode) {
      debugPrint('[CURRENT] code=${wc.code} temp=${wc.temp} wind=${wc.windKmh} label="${wc.label}"');
    }
    return wc;
  }
}

class WeatherBundle {
  final String cityName;
  final double lat;
  final double lon;
  final WeatherCurrent current;
  final List<WeatherDay> week;

  WeatherBundle({
    required this.cityName,
    required this.lat,
    required this.lon,
    required this.current,
    required this.week,
  });

  factory WeatherBundle.fromJson(Map j) {
    final m = j.cast<String, dynamic>();
    final currentMap = (m['current'] is Map) ? m['current'] as Map : const {};
    final dailyList = (m['daily'] is List)
        ? (m['daily'] as List)
        : (m['week'] is List)
            ? (m['week'] as List)
            : (m['forecast'] is List)
                ? (m['forecast'] as List)
                : const [];

    final week = dailyList.whereType<Map>().map((d) => WeatherDay.fromJson(d)).toList();
    WeatherCurrent cur = WeatherCurrent.fromJson(currentMap);

    if (!cur.temp.isFinite && week.isNotEmpty) {
      final avg = (week.first.tMin.isFinite && week.first.tMax.isFinite)
          ? (week.first.tMin + week.first.tMax) / 2.0
          : double.nan;
      cur = WeatherCurrent(
        temp: avg,
        code: cur.code ?? week.first.code,
        windKmh: cur.windKmh.isFinite ? cur.windKmh : week.first.windKmh,
        label: cur.label.isNotEmpty ? cur.label : week.first.label,
      );
    }

    final wb = WeatherBundle(
      cityName: _toString(m['city'] ?? m['name']),
      lat: _toDouble(m['lat']),
      lon: _toDouble(m['lon']),
      current: cur,
      week: week,
    );

    if (kDebugMode) {
      debugPrint('[BUNDLE] city=${wb.cityName} lat=${wb.lat} lon=${wb.lon}');
    }
    return wb;
  }

  double get currentTemp => current.temp;
  double get currentWindKmh => current.windKmh;
  String get currentLabel => current.label.isEmpty ? 'N/A' : current.label;
}

// ----------------- Service -----------------
class MeteoFranceService {
  /// ⚙️ Méthode existante — garde ton API identique
  static Future<WeatherBundle> fetch(double lat, double lon) async {
    final base = ApiServices.baseUrl; // ex: https://chassealerte.onrender.com/api

    // IMPORTANT : base contient déjà /api → on ajoute seulement /meteo
    final uri = Uri.parse('$base/meteo').replace(queryParameters: {
      'lat': lat.toString(),
      'lon': lon.toString(),
    });

    if (kDebugMode) debugPrint('[HTTP] GET $uri');

    final res = await http.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw Exception('Réponse inattendue: ${res.body}');
    }
    return WeatherBundle.fromJson(decoded);
  }

  /// 🌍 Nouvelle méthode : récupère la météo à MA POSITION
  static Future<WeatherBundle> fetchFromMyPosition() async {
    try {
      if (kDebugMode) debugPrint('[GEO] Requesting position...');
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw Exception('Service de localisation désactivé');

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        throw Exception('Permission localisation refusée');
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (kDebugMode) debugPrint('[GEO] pos=(${pos.latitude}, ${pos.longitude})');

      return await fetch(pos.latitude, pos.longitude);
    } catch (e) {
      if (kDebugMode) debugPrint('[GEO] Erreur localisation: $e');
      rethrow;
    }
  }
}
