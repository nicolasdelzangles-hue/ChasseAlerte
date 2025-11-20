/// widgets/weather_icon_mapper.dart
/// Mappe un code Météo-Concept/Météo-France vers une icône locale.
/// S'appuie EXACTEMENT sur les fichiers présents dans assets/icons/weather/.
String weatherIconFromCode(int? code, {bool isNight = false}) {
  const base = 'assets/icons/weather';

  String one(String name) => '$base/$name.png';
  String pick2(String dayName, String nightName) =>
      isNight ? one(nightName) : one(dayName);

  if (code == null) return one('unknow');

  final c = code;

  // ---- Ciel clair / peu nuageux / nuageux / couvert
  if (c == 0) return pick2('clear_day', 'clear_night');                 // ☀️ / 🌙
  if ([1, 2].contains(c)) return pick2('partly_cloudy_day','partly_cloudy_night');
  if (c == 3) return one('cloudy');                                     // nuageux
  if (c == 4) return one('nuageux (1)');                                // couvert (pas de variante nuit)

  // ---- Brouillard / brume
  if ([20, 30, 31].contains(c)) return one('fog');

  // ---- Neige (60–69) + pluie-neige / neige roulée (70–79)
  if ((c >= 60 && c <= 69) || (c >= 70 && c <= 79)) {
    // tu as snow_day.png / snow_night.png
    return pick2('snow_day','snow_night');
  }

  // ---- Pluie continue / variable (5–7,10, 40–49)
  if ([5, 6, 7, 10].contains(c) || (c >= 40 && c <= 49)) {
    return pick2('rain_day','rain_night');
  }

  // ---- Averses (80–84)
  if (c >= 80 && c <= 84) {
    // pas d’icône “showers” dédiée -> on réutilise rain_*
    return pick2('rain_day','rain_night');
  }

  // ---- Orages (90–99)
  if (c >= 90 && c <= 99) {
    // tu as storm_day.png / storm_night.png
    return pick2('storm_day','storm_night');
  }

  // ---- Divers anciens codes “orage” (16–17) si tu les rencontres
  if ([16, 17].contains(c)) return pick2('storm_day','storm_night');

  // ---- Sec par défaut
  return one('cloudy');
}
