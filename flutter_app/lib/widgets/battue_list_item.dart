import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'species_avatar.dart';

class BattueListItem extends StatelessWidget {
  const BattueListItem({
    super.key,
    required this.title,     // ex. "Palombe" ou "Carotte"
    required this.location,  // ex. "Eauze"
    required this.dateStr,   // ex. "2025-09-14T22:00:00.000Z"
    this.onTap,
  });

  final String title;
  final String location;
  final String dateStr;
  final VoidCallback? onTap;

  String _fmt(String s) {
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    // ✅ Supprimé 'fr_FR' pour éviter LocaleDataException
    return DateFormat('yyyy-MM-dd').format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 2),
            SpeciesAvatar(name: title, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    location,
                    style: TextStyle(
                      color: Colors.black.withOpacity(.65),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmt(dateStr),
                    style: TextStyle(
                      color: Colors.black.withOpacity(.65),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
