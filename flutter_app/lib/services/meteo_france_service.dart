import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_services.dart';

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

/// Essaie les clés usuelles pouvant contenir le "code météo" d'un jour/heure
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

/// Priorité phénomènes pour agréger plusieurs codes (horaires → jour)
int _dominantCode(Iterable<int> codes) {
  final c = codes.where((e) => e >= 0 && e <= 199).toList();
  if (c.isEmpty) return 3; // nuageux par défaut

  bool any(bool Function(int) f) => c.any(f);

  // Orages (90–99)
  if (any((x) => x >= 90 && x <= 99)) return 95;
  // Neige (60–69) ou pluie-neige (70–79)
  if (any((x) => (x >= 60 && x <= 69) || (x >= 70 && x <= 79))) return 65;
  // Pluie (5–7,10, 40–49) + averses (80–84)
  if (any((x) =>
      [5, 6, 7, 10].contains(x) || (x >= 40 && x <= 49) || (x >= 80 && x <= 84))) {
    return 41;
  }
  // Brouillard (20, 30, 31)
  if (any((x) => x == 20 || x == 30 || x == 31)) return 20;
  // Nuageux (1–4)
  if (any((x) => x >= 1 && x <= 4)) return 3;
  // Ciel clair (0)
  if (any((x) => x == 0)) return 0;

  return 3;
}

// ----------------- Modèles -----------------

class WeatherDay {
  final DateTime date;
  final double tMin;
  final double tMax;
  final double windKmh;
  final int code;        // <- désormais non-nullable
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

    // 1) Essai direct : le jour porte déjà un code
    int? code = _pickWeatherCodeFromMap(m);

    // 2) Sinon : agréger les codes horaires si présents
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

    // 3) Fallback ultime : nuageux
    code ??= 3;

    final wd = WeatherDay(
      date: _parseDateOrNow(m['date'] ?? m['datetime'] ?? m['time'] ?? m['day']),
      tMin: m.containsKey('tmin') ? _toDouble(m['tmin']) : double.nan,
      tMax: m.containsKey('tmax') ? _toDouble(m['tmax']) : double.nan,
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
    // tolère plusieurs clés pour la liste jour
    final dailyList = (m['daily'] is List)
        ? (m['daily'] as List)
        : (m['week'] is List)
            ? (m['week'] as List)
            : (m['forecast'] is List)
                ? (m['forecast'] as List)
                : const [];

    final week = dailyList.whereType<Map>().map((d) => WeatherDay.fromJson(d)).toList();

    // fallbacks sûrs pour éviter NaN dans l’UI
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
      for (final d in wb.week) {
        debugPrint('[BUNDLE] ${d.date.toIso8601String()} code=${d.code}');
      }
    }
    return wb;
  }

  // --- Getters utiles pour les widgets
  double get currentTemp => current.temp;
  double get currentWindKmh => current.windKmh;
  String get currentLabel => current.label.isEmpty ? 'N/A' : current.label;
}

class MeteoFranceService {
  static Future<WeatherBundle> fetch(double lat, double lon) async {
    final base = ApiServices.baseUrl;
    final uri = Uri.parse('$base/api/meteo?lat=$lat&lon=$lon');
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
}
