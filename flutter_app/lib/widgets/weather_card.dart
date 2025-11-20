import 'package:flutter/material.dart';
import '../services/meteo_france_service.dart';
import '../screens/weather_week_screen.dart';
import '../widgets/weather_icon_mapper.dart' ; // <= alias

// Thème (vert forêt + beige)
const kBeige = Color(0xFFE9E1D1);
const kCard  = Color(0xFF153D31);
const kAccent= Color(0xFFFFD37A);

class WeatherCard extends StatefulWidget {
  final double lat;
  final double lon;

  const WeatherCard({
    super.key,
    required this.lat,
    required this.lon,
  });

  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  late Future<WeatherBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = MeteoFranceService.fetch(widget.lat, widget.lon);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeatherBundle>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return _skeleton();
        if (snap.hasError || !snap.hasData) return _errorTile();
        return _content(snap.data!);
      },
    );
  }

  // ---------- UI: états ----------
  Widget _skeleton() => Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _Shimmer(width: 140, height: 16),
                  SizedBox(height: 8),
                  _Shimmer(width: 90, height: 28),
                  SizedBox(height: 6),
                  _Shimmer(width: 120, height: 14),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _errorTile() => Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: const [
            Icon(Icons.wifi_off_rounded, color: kBeige),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Météo indisponible',
                style: TextStyle(color: kBeige),
              ),
            ),
          ],
        ),
      );

  // ---------- Helpers ----------
  String _fmt0(double v) => v.isFinite ? v.toStringAsFixed(0) : '--';

  // ---------- UI: contenu ----------
  Widget _content(WeatherBundle d) {
    // Icone = code courant, sinon 1er jour, sinon fallback mapper
   final int? codeForIcon = d.current.code ?? (d.week.isNotEmpty ? d.week.first.code : null);
final String iconPath = weatherIconFromCode(codeForIcon);


    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => WeatherWeekScreen(bundle: d)),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.06),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Image.asset(iconPath, width: 28, height: 28),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.cityName.isEmpty ? 'Météo locale' : d.cityName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kBeige,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Laisse ton libellé existant (peut être 'N/A')
                  Text(
                    d.currentLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: kBeige.withOpacity(.85)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_fmt0(d.currentTemp)}°  •  Vent ${_fmt0(d.currentWindKmh)} km/h',
                    style: TextStyle(
                      color: kBeige.withOpacity(.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kBeige),
          ],
        ),
      ),
    );
  }
}

// Shimmer
class _Shimmer extends StatelessWidget {
  final double width;
  final double height;
  const _Shimmer({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.08),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
