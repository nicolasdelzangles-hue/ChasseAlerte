import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/meteo_france_service.dart';
import '../widgets/weather_icon_mapper.dart';

const kBeige = Color(0xFFF8F8F7);
const kCard  = Color(0xFF0A0A0A);

/// Récupère l'heure courante quelle que soit la propriété dans WeatherCurrent
extension _BundleTime on WeatherBundle {
  DateTime? get currentTime {
    final c = current;
    if (c == null) return null;
    try { return (c as dynamic).datetime as DateTime?; } catch (_) {}
    try { return (c as dynamic).dateTime as DateTime?; } catch (_) {}
    try { return (c as dynamic).time as DateTime?; } catch (_) {}
    try { return (c as dynamic).dt as DateTime?; } catch (_) {}
    return null;
  }
}

class WeatherWeekScreen extends StatelessWidget {
  final WeatherBundle bundle;
  const WeatherWeekScreen({super.key, required this.bundle});

  // sécurise l’affichage d’un entier
  String _fmt0(double v) => v.isFinite ? v.toStringAsFixed(0) : '--';

  @override
  Widget build(BuildContext context) {
    final days = bundle.week;

    // bornes globales sécurisées
    final tmins = days.map((e) => e.tMin).where((v) => v.isFinite).toList();
    final tmaxs = days.map((e) => e.tMax).where((v) => v.isFinite).toList();
    final double minGlobal = tmins.isEmpty ? 0 : tmins.reduce((a, b) => a < b ? a : b);
    final double maxGlobal = tmaxs.isEmpty ? 1 : tmaxs.reduce((a, b) => a > b ? a : b);
    final double total = (maxGlobal - minGlobal).abs() < 1e-6 ? 1.0 : (maxGlobal - minGlobal);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Image.asset('assets/icons/back.png', width: 22, height: 22),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Retour',
        ),
        title: Text(bundle.cityName.isEmpty ? 'Prévisions' : bundle.cityName),
      ),
      backgroundColor: const Color(0xFF0A2B22),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _headerNow(bundle),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: days.isEmpty
                ? const _EmptyDays()
                : Column(
                    children: days.map((d) => _dayRow(
                      d: d,
                      minGlobal: minGlobal,
                      total: total,
                    )).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _headerNow(WeatherBundle b) => Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_fmt0(b.currentTemp)}°',
              style: const TextStyle(
                color: kBeige,
                fontSize: 56,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              b.currentLabel.isEmpty ? 'N/A' : b.currentLabel,
              style: const TextStyle(color: kBeige, fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              'Vent ${_fmt0(b.currentWindKmh)} km/h',
              style: TextStyle(color: kBeige.withOpacity(.85)),
            ),

            if (kDebugMode) ...[
              const SizedBox(height: 6),
              Text(
                'code=${b.current.code} @ ${b.currentTime?.toLocal().toIso8601String()}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      );

  // ---- Ligne d’un jour ----
  Widget _dayRow({
    required WeatherDay d,
    required double minGlobal,
    required double total,
  }) {
    final double tmin = d.tMin.isFinite ? d.tMin : minGlobal;
    final double tmax = d.tMax.isFinite ? d.tMax : (minGlobal + total);

    // positions normalisées de la barre
    final left = ((tmin - minGlobal) / total).clamp(0.0, 1.0);
    final right = ((minGlobal + total - tmax) / total).clamp(0.0, 1.0);

    // Icône JOUR (pas de variante nuit pour l’aperçu semaine)
    final String dayIcon = weatherIconFromCode(d.code, isNight: false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // Jour (Lun/Mar/…)
          SizedBox(
            width: 40,
            child: Text(
              _weekday(d.date),
              style: const TextStyle(color: kBeige),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),

          // Icône
          SizedBox(
            width: 22,
            height: 22,
            child: Image.asset(dayIcon, fit: BoxFit.contain),
          ),
          const SizedBox(width: 8),

          // Tmin
          SizedBox(
            width: 30,
            child: Text(
              '${tmin.round()}°',
              style: TextStyle(color: kBeige.withOpacity(.8)),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 6),

          // Barre proportionnelle
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final leftPx = c.maxWidth * left;
                final rightPx = c.maxWidth * right;
                final barW = (c.maxWidth - leftPx - rightPx).clamp(6.0, c.maxWidth);

                return Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Positioned(
                      left: leftPx,
                      width: barW,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 6),

          // Tmax
          SizedBox(
            width: 34,
            child: Text(
              '${tmax.round()}°',
              style: const TextStyle(color: kBeige),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _weekday(DateTime d) {
    const fr = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return fr[(d.weekday - 1) % 7];
  }
}

class _EmptyDays extends StatelessWidget {
  const _EmptyDays();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Aucune prévision disponible.',
        style: TextStyle(color: kBeige),
      ),
    );
  }
}
