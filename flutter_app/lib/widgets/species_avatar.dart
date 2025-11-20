import 'package:flutter/material.dart';

/// Map optionnelle: nom normalisé -> chemin asset
const Map<String, String> kSpeciesAssets = {
  'sanglier': 'assets/image/battue_icone.png',
  'becasse':  'assets/image/becasse.png',
  'lapin':  'assets/image/lapin.png',
  'cerf':  'assets/image/cerf.png',
  'palombe':  'assets/image/palombe.png',
  'perdri':   'assets/image/perdri.png',
  'canard':   'assets/image/canard.png', // tolérance
};

String _normalize(String s) {
  final lower = s.trim().toLowerCase();
  return lower
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ô', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ç', 'c');
}

/// Couleur stable calculée depuis le nom (pour pastille)
Color _colorFrom(String s) {
  int h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  // palette douce
  final candidates = <Color>[
    const Color(0xFFDEEFD9),
    const Color(0xFFE7F0FF),
    const Color(0xFFFFF0D9),
    const Color(0xFFF5E7FF),
    const Color(0xFFFFE3E3),
    const Color(0xFFE7FFF6),
  ];
  return candidates[h % candidates.length];
}

class SpeciesAvatar extends StatelessWidget {
  const SpeciesAvatar({
    super.key,
    required this.name,
    this.size = 64,
  });

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final norm = _normalize(name);
    final asset = kSpeciesAssets[norm];

    if (asset != null && asset.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .25),
          color: const Color(0xFFF3F0EB),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(asset, fit: BoxFit.contain),
      );
    }

    // Fallback générique (ex: "carotte")
    final bg = _colorFrom(norm);
    final initial = norm.isNotEmpty ? norm.characters.first.toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * .25),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(fontSize: size * .45, fontWeight: FontWeight.w800),
      ),
    );
  }
}
