// ignore_for_file: prefer_const_constructors
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../widgets/weather_card.dart';
import '../services/location_services.dart';
import '../providers/auth_provider.dart';
import '../providers/battue_provider.dart';
import '../services/favorite_service.dart';
import '../services/api_services.dart';

import 'battue_map_screen.dart';
import 'battue_list_screen.dart';
import 'chat_list_screen.dart';
import 'profile_screen.dart';
import 'battue_charts_screen.dart'; // <-- pour l’onglet Stats


const kForest     = Color(0xFF0E3A2D);
const kForestDeep = Color(0xFF0A2B22);
const kCard       = Color(0xFF153D31);
const kBeige      = Color(0xFFE9E1D1);
const kBeige70    = Color(0xB3E9E1D1);
const kAccent     = Color(0xFFFFD37A);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final Set<int> _favoris = {};
 
  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return int.tryParse(v.toString());
  }

  void _goToBattuesTab() => setState(() => _selectedIndex = 2);

  @override
  void initState() {
    super.initState();
    
    Future.microtask(() => context.read<BattueProvider>().fetchBattues());
    context.read<AuthProvider>().resetInactivityTimer();
  }
 
   


  /// Construit les 6 onglets (inclut Stats)
  List<Widget> _buildTabs(BuildContext context) {
    return [
      HomeContent(
        favoris: _favoris,
        onToggleFavori: _handleToggleFavori,
        onOpenBattuesTab: _goToBattuesTab,
      ),
      const BattueMapScreen(),
      const BattueListScreen(),
      ChatListScreen(),
      const ProfileScreen(),
      _buildStatsTab(context), // <-- 6e onglet : Stats
    ];
  }

  Widget _buildStatsTab(BuildContext context) {
    final p = context.watch<BattueProvider>();
    if (p.isLoading) return const Center(child: CircularProgressIndicator());
    if (p.battues.isEmpty) {
      return const Center(child: Text('Aucune battue disponible', style: TextStyle(color: kBeige)));
    }
    final b = p.battues.first; // simple : on affiche la première battue
    return BattueChartsScreen(battue: b);
  }

  Future<void> _handleToggleFavori(int id) async {
    setState(() {
      if (_favoris.contains(id)) {
        _favoris.remove(id);
      } else {
        _favoris.add(id);
      }
    });

    final authProvider = context.read<AuthProvider>();
    final user = await authProvider.currentUser;
    final int? userId = _asInt(user?.id);
    final int? battueId = _asInt(id);

    if (userId == null || battueId == null) {
      if (!mounted) return;
      setState(() {
        if (_favoris.contains(id)) {
          _favoris.remove(id);
        } else {
          _favoris.add(id);
        }
      });
      return;
    }

    try {
      await ApiServices.toggleBattueFavorite(battueId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_favoris.contains(id)) {
          _favoris.remove(id);
        } else {
          _favoris.add(id);
        }
      });
    }
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final tabs = _buildTabs(context);

    // sécurité : si _selectedIndex dépasse (hot reload, etc.)
    final safeIndex = _selectedIndex.clamp(0, tabs.length - 1);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kForest,
        title: const Text(
          'ChasseAlerte',
          style: TextStyle(color: kBeige, fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              onPressed: () {
                authProvider.logout();
                if (!mounted) return;
                Navigator.of(context).pushReplacementNamed('/login');
              },
              icon: Image.asset('assets/image/deco.png', width: 22, height: 22),
              label: Text('Déconnexion'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB64E4E),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),

      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kForest, kForestDeep],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: tabs.elementAt(safeIndex),
      ),

      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          canvasColor: kForestDeep,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          backgroundColor: kForestDeep,
          currentIndex: safeIndex,
          onTap: (i) => setState(() {
            _selectedIndex = (i < tabs.length) ? i : tabs.length - 1;
          }),
          selectedItemColor: kBeige,
          unselectedItemColor: const Color(0xFF9FB2A9),
          items: const [
            BottomNavigationBarItem(
              icon: ImageIcon(AssetImage('assets/image/home_icone.png')),
              label: 'Accueil',
            ),
            BottomNavigationBarItem(
              icon: ImageIcon(AssetImage('assets/image/carte_icone.png')),
              label: 'Carte',
            ),
            BottomNavigationBarItem(
              icon: ImageIcon(AssetImage('assets/image/battue_icone.png')),
              label: 'Battues',
            ),
            BottomNavigationBarItem(
              icon: ImageIcon(AssetImage('assets/image/envoyer.png')),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: ImageIcon(AssetImage('assets/image/profil_icone.png')),
              label: 'Profil',
            ),
            BottomNavigationBarItem(
              icon: ImageIcon(AssetImage('assets/image/diagramme.png')),
              label: 'Stats',
            ),
          ],
        ),
      ),
    );
  }
}

/* ---------------------- Accueil ---------------------- */

class HomeContent extends StatefulWidget {
  final Set<int> favoris;
  final void Function(int) onToggleFavori;
  final VoidCallback onOpenBattuesTab;

  const HomeContent({
    super.key,
    required this.favoris,
    required this.onToggleFavori,
    required this.onOpenBattuesTab,
  });

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  WeatherBundle? _meteo;
  bool _loadingMeteo = false;
  String? _meteoErr;
final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadMeteoFromMyPosition();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMeteoFromMyPosition() async {
    setState(() {
      _loadingMeteo = true;
      _meteoErr = null;
    });
    try {
      final b = await MeteoFranceService.fetchFromMyPosition();
      if (!mounted) return;                // <-- évite setState après dispose
      setState(() => _meteo = b);
    } catch (e) {
      if (!mounted) return;
      setState(() => _meteoErr = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loadingMeteo = false);
    }
  }
    List<dynamic> _filterBattues(List<dynamic> all) {
    if (_searchQuery.isEmpty) return all;

    bool contains(String? value) =>
        value != null && value.toLowerCase().contains(_searchQuery);

    return all.where((b) {
      // on filtre sur plusieurs champs
      return contains(b.title) ||
             contains(b.location) ||   // zone / commune
             contains(b.description) ||
             contains(b.type);
    }).toList();
  }


  @override
    @override
  Widget build(BuildContext context) {
    final battueProvider = context.watch<BattueProvider>();
    final allBattues = battueProvider.battues;
    final filteredBattues = _filterBattues(allBattues);

    Widget tuileMeteo() {
      if (_loadingMeteo) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator(color: kBeige)),
        );
      }
      if (_meteoErr != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Météo indisponible : $_meteoErr',
                  style: const TextStyle(color: kBeige70)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadMeteoFromMyPosition,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBeige.withOpacity(.12),
                  foregroundColor: kBeige,
                ),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        );
      }
      if (_meteo != null) {
        return WeatherCard(lat: _meteo!.lat, lon: _meteo!.lon);
      }
      return const SizedBox.shrink();
    }

    // ----- construction dynamique de la page -----
    final List<Widget> children = [
      TextField(
        controller: _searchController,
        style: const TextStyle(color: kBeige),
        decoration: InputDecoration(
          hintText: 'Rechercher une battue...',
          hintStyle: const TextStyle(color: kBeige70),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Image.asset(
              'assets/image/recherche_icone.png',
              width: 22,
              height: 22,
              color: kBeige,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(26),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: const Color(0xFF1B4A3B),
        ),
      ),
      const SizedBox(height: 20),

      tuileMeteo(),
      const SizedBox(height: 20),
    ];

    // --- Si on tape quelque chose : on affiche les résultats ---
    if (_searchQuery.isNotEmpty) {
      children.addAll([
        const Text(
          'Résultats de recherche',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: kBeige,
          ),
        ),
        const SizedBox(height: 10),

        if (filteredBattues.isEmpty)
          const Text(
            'Aucune battue trouvée.',
            style: TextStyle(color: kBeige70),
          )
        else
          Column(
            children: filteredBattues
                .map<Widget>((b) => BattueSearchResultCard(battue: b))
                .toList(),
          ),

        const SizedBox(height: 20),
      ]);
    } else {
      // --- Sinon : ton écran habituel (favoris + battues dispo) ---
      children.addAll([
        const Text(
          'Favoris',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: kBeige,
          ),
        ),
        const SizedBox(height: 10),
        if (widget.favoris.isEmpty)
          const Text('Aucun favori.', style: TextStyle(color: kBeige70))
        else
          Column(
            children: allBattues
                .where((b) => widget.favoris.contains(b.id))
                .map((b) => BattueCard(
                      battue: b,
                      isFavori: true,
                      onToggleFavori: widget.onToggleFavori,
                      onOpenBattues: widget.onOpenBattuesTab,
                    ))
                .toList(),
          ),
        const SizedBox(height: 30),

        const Text(
          'Battues disponibles',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: kBeige,
          ),
        ),
        const SizedBox(height: 10),
        if (battueProvider.isLoading)
          const Center(child: CircularProgressIndicator(color: kBeige))
        else if (allBattues.isEmpty)
          const Text(
            'Aucune battue disponible.',
            style: TextStyle(color: kBeige70),
          )
        else
          Column(
            children: allBattues
                .map((b) => BattueCard(
                      battue: b,
                      isFavori: widget.favoris.contains(b.id),
                      onToggleFavori: widget.onToggleFavori,
                      onOpenBattues: widget.onOpenBattuesTab,
                    ))
                .toList(),
          ),
        const SizedBox(height: 12),
      ]);
    }

    return Container(
      color: Colors.transparent,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }

}

/* ---------------------- Carte Battue ---------------------- */

class BattueCard extends StatelessWidget {
  final dynamic battue;
  final bool isFavori;
  final void Function(int) onToggleFavori;
  final VoidCallback? onOpenBattues;

  const BattueCard({
    super.key,
    required this.battue,
    required this.isFavori,
    required this.onToggleFavori,
    this.onOpenBattues,
  });

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return int.tryParse(v.toString());
  }

 String _staticMapThumb(double? lat, double? lng) {
  if (lat == null || lng == null) return '';

  final baseUrl = ApiServices.baseUrl; // tu l’as déjà dans ApiServices
  final uri = Uri.parse('$baseUrl/api/static-map').replace(
    queryParameters: {
      'lat': '$lat',
      'lng': '$lng',
      'zoom': '13',
      'size': '160x160',
    },
  );
  return uri.toString();
}



  List<LatLng> _parsePolygonFromGeoJsonString(String? geoJsonString) {
    if (geoJsonString == null || geoJsonString.isEmpty) return <LatLng>[];
    try {
      final obj = jsonDecode(geoJsonString);
      if (obj is Map && obj['type'] == 'Polygon') {
        final rings = obj['coordinates'] as List;
        if (rings.isNotEmpty) {
          final outer = rings.first as List;
          return outer.map<LatLng>((c) {
            final lon = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            return LatLng(lat, lon);
          }).toList();
        }
      }
    } catch (_) {}
    return <LatLng>[];
  }

  LatLngBounds? _bounds(List<LatLng> pts) {
    if (pts.length < 2) return null;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }

  @override
  Widget build(BuildContext context) {
    final battueIdInt = _asInt(battue.id);

    final double? lat =
        battue.latitude is num ? (battue.latitude as num).toDouble() : null;
    final double? lng =
        battue.longitude is num ? (battue.longitude as num).toDouble() : null;

    final List<LatLng> zonePoints = _parsePolygonFromGeoJsonString(battue.imageUrl as String?);
    final thumbUrl = _staticMapThumb(lat, lng);

    return Card(
      color: kCard,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        iconColor: kBeige,
        collapsedIconColor: kBeige,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: thumbUrl.isNotEmpty
              ? Image.network(thumbUrl, width: 48, height: 48, fit: BoxFit.cover)
              : Container(
                  width: 48, height: 48, color: const Color(0xFF1B4A3B),
                  child: Center(child: Image.asset('assets/image/battue_icone.png', width: 22, height: 22, color: kBeige)),
                ),
        ),
        title: Text(
          battue.title,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, color: kBeige),
        ),
        subtitle: Text(
          'Date : ${battue.date} • Zone : ${battue.location}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: kBeige70),
        ),
        trailing: IconButton(
          tooltip: isFavori ? 'Retirer des favoris' : 'Ajouter aux favoris',
          icon: Image.asset('assets/image/star.png', width: 22, height: 22),
          onPressed: () {
            final id = battueIdInt;
            if (id != null) onToggleFavori(id);
          },
        ),
        children: [
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 200,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: (zonePoints.isNotEmpty)
                      ? zonePoints.first
                      : (lat != null && lng != null ? LatLng(lat, lng) : const LatLng(46.5, 2.5)),
                  zoom: (zonePoints.isNotEmpty) ? 12 : 13,
                ),
                polygons: zonePoints.isNotEmpty
                    ? {
                        Polygon(
                          polygonId: PolygonId('zone_${battue.id}'),
                          points: zonePoints,
                          strokeWidth: 2,
                          strokeColor: kAccent,
                          fillColor: kAccent.withOpacity(0.18),
                        ),
                      }
                    : <Polygon>{},
                markers: zonePoints.isEmpty && lat != null && lng != null
                    ? {
                        Marker(
                          markerId: const MarkerId('battue'),
                          position: LatLng(lat, lng),
                          infoWindow: InfoWindow(title: battue.title),
                        ),
                      }
                    : <Marker>{},
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
                onMapCreated: (c) {
                  if (zonePoints.length >= 3) {
                    final b = _bounds(zonePoints);
                    if (b != null) {
                      Future.delayed(const Duration(milliseconds: 100), () {
                        c.animateCamera(CameraUpdate.newLatLngBounds(b, 24));
                      });
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onOpenBattues,
                icon: const Icon(Icons.open_in_new, color: kBeige),
                label: const Text('Ouvrir l’onglet Battues', style: TextStyle(color: kBeige)),
                style: TextButton.styleFrom(
                  backgroundColor: kBeige.withOpacity(.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
class BattueSearchResultCard extends StatelessWidget {
  final dynamic battue;

  const BattueSearchResultCard({super.key, required this.battue});

  Widget _line(String label, dynamic value) {
    if (value == null) return const SizedBox.shrink();
    if (value is String && value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: kBeige),
          children: [
            TextSpan(
              text: '$label : ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: '$value'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: kCard,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              battue.title ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: kBeige,
              ),
            ),
            const SizedBox(height: 8),
            _line('Lieu (zone/commune)', battue.location),
            _line('Date', battue.date),
            _line('Description', battue.description),
            _line('Type', battue.type),
            _line('Privée', battue.isPrivate == true ? 'Oui' : 'Non'),
          ],
        ),
      ),
    );
  }
}

