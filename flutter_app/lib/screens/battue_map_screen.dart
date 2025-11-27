import 'dart:async';
import 'dart:math' as math;

import 'package:chassealerte/services/api_services.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class BattueMapScreen extends StatefulWidget {
  const BattueMapScreen({super.key});
  @override
  State<BattueMapScreen> createState() => _BattueMapScreenState();
}

class _BattueMapScreenState extends State<BattueMapScreen> {
  // ====== CONFIG ======
static const String _apiBase = ApiConfig.baseUrl;
  /// Limitation du viewport (France métropolitaine)
  static final LatLngBounds _frBounds = LatLngBounds(
    southwest: const LatLng(41.0, -5.5),
    northeast: const LatLng(51.5, 9.8),
  );

  /// Evite les zooms extrêmes (réduit bandes/coutures)
  static const MinMaxZoomPreference _frZoom = MinMaxZoomPreference(5.5, 19.0);

  // ====== STATE / LOGS ======
  final _logBuf = StringBuffer();
  final ValueNotifier<String> _hud = ValueNotifier<String>('');
  final _searchCtrl = TextEditingController();

  void _L(String tag, Object msg) {
    final now = DateTime.now().toIso8601String().split('T').last;
    final line = '[$now][$tag] $msg';
    // ignore: avoid_print
    print(line);
    if (_logBuf.length > 4000) _logBuf.clear();
    _logBuf.writeln(line);
    _hud.value = _logBuf.toString();
  }

  final Completer<GoogleMapController> _controller = Completer();
  GoogleMapController? _mapCtrl;

  late final Dio _dio;

  LatLng? _myPos;
  LatLng _initial = const LatLng(43.6045, 1.4440); // Toulouse par défaut
  final Set<Marker> _markers = <Marker>{};
  final Set<Polyline> _polylines = <Polyline>{};

  // debug
  String _lastPlacesStatus = '-';
  String _lastDetailsStatus = '-';
  String _lastRouteStatus = '-';
  int _lastRoutePoints = 0;
  String? _lastUIError;

  // ====== AUTH ======
  String? _token;
  late final VoidCallback _authListener;

  @override
  void initState() {
    super.initState();
    _L('INIT', 'BattueMapScreen');

    // --- Dio + Auth header ---
    _dio = Dio(
      BaseOptions(
        baseUrl: _apiBase,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (c) => (c ?? 0) >= 200 && (c ?? 0) < 600,
      ),
    );

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        if (_token != null && _token!.isNotEmpty) {
          o.headers['Authorization'] = 'Bearer $_token';
        }
        o.extra['t'] = DateTime.now();
        _L('HTTP→', '${o.method} ${o.uri}');
        h.next(o);
      },
      onResponse: (r, h) {
        final t0 = r.requestOptions.extra['t'] as DateTime?;
        final dt = t0 == null ? '-' : '${DateTime.now().difference(t0).inMilliseconds}ms';
        _L('HTTP←', '${r.requestOptions.uri} status=${r.statusCode} $dt');
        if (r.statusCode == 401 || r.statusCode == 403) _handleUnauthorized();
        h.next(r);
      },
      onError: (e, h) {
        _L('HTTPERR', '${e.requestOptions.uri} ${e.message}');
        if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
          _handleUnauthorized();
        }
        h.next(e);
      },
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      _token = auth.token;
      _L('AUTH', 'token present=${_token != null && _token!.isNotEmpty}');
      _authListener = () {
        final newToken = auth.token;
        final changed = newToken != _token;
        _token = newToken;
        if (changed) {
          _L('AUTH', 'token updated present=${_token != null && _token!.isNotEmpty}');
        }
      };
      auth.addListener(_authListener);
    });

    _determinePosition();
  }

  @override
  void dispose() {
    if (mounted) {
      try {
        context.read<AuthProvider>().removeListener(_authListener);
      } catch (_) {}
    }
    super.dispose();
  }

  void _handleUnauthorized() {
    _lastUIError = 'Session expirée ou non autorisée.';
    setState(() {});
    _L('AUTH', 'unauthorized (401/403)');
  }

  Future<bool> _ensureAuth() async {
    if (_token == null || _token!.isEmpty) {
      _lastUIError = 'Vous devez être connecté pour utiliser la recherche et l’itinéraire.';
      setState(() {});
      _L('AUTH', 'no token -> blocked');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez vous connecter.')),
      );
    }
    return _token != null && _token!.isNotEmpty;
  }

  // ====== GEO ======
  Future<void> _determinePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      _L('GEO', 'service=$serviceEnabled');
      if (!serviceEnabled) return;

      final p = await Geolocator.requestPermission();
      _L('GEO', 'perm=$p');
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition();
      final me = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _myPos = me;
        _initial = me;
        _markers.add(Marker(
          markerId: const MarkerId('me'),
          position: me,
          infoWindow: const InfoWindow(title: 'Moi'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ));
      });
      _L('GEO', 'me=(${me.latitude},${me.longitude})');
    } catch (e) {
      _L('GEOERR', e);
    }
  }

  // ====== API protégées ======
  Future<List<Map<String, dynamic>>> _searchPlaces(String q) async {
  if (q.trim().isEmpty) return [];
  if (!await _ensureAuth()) return [];

  try {
    final preds = await ApiServices.placesAutocomplete(q);
    _lastPlacesStatus = 'OK';
    _L('PLACES', 'status=$_lastPlacesStatus, n=${preds.length}');
    return preds.cast<Map<String, dynamic>>();
  } catch (e) {
    _lastPlacesStatus = 'HTTP_ERROR';
    _L('PLACES', 'err=$e');
    return [];
  } finally {
    setState(() {});
  }
}


  Future<LatLng?> _getPlaceLatLng(String placeId) async {
  if (!await _ensureAuth()) return null;

  try {
    final data = await ApiServices.placeDetails(placeId);
    _lastDetailsStatus = (data['status'] ?? '-').toString();

    final loc = data['result']?['geometry']?['location'];
    if (loc is Map && loc['lat'] != null && loc['lng'] != null) {
      final ll = LatLng(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      );
      _L('DETAILS', 'OK $ll');
      return ll;
    }
    _L('DETAILS', 'no geometry');
    return null;
  } catch (e) {
    _lastDetailsStatus = 'HTTP_ERROR';
    _L('DETAILS', 'err=$e');
    return null;
  } finally {
    setState(() {});
  }
}


  // ====== ROUTE — helpers ======
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> poly = [];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;
      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return poly;
  }

  double _distKm(LatLng a, LatLng b) {
    const R = 6371.0;
    final dLat = (b.latitude - a.latitude) * (math.pi / 180);
    final dLng = (b.longitude - a.longitude) * (math.pi / 180);
    final la1 = a.latitude * (math.pi / 180);
    final la2 = b.latitude * (math.pi / 180);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * R * math.asin(math.sqrt(h));
  }

  List<LatLng> _sane(List<LatLng> src) {
    LatLng? last;
    final out = <LatLng>[];
    for (final p in src) {
      final ok = p.latitude.isFinite &&
          p.longitude.isFinite &&
          p.latitude >= -85 &&
          p.latitude <= 85 &&
          p.longitude >= -180 &&
          p.longitude <= 180;
      if (!ok) continue;
      if (last == null ||
          last.latitude != p.latitude ||
          last.longitude != p.longitude) {
        out.add(p);
        last = p;
      }
    }
    return out;
  }

  List<List<LatLng>> _splitByHop(List<LatLng> pts, {double maxHopKm = 40}) {
    final chunks = <List<LatLng>>[];
    var cur = <LatLng>[];
    for (final p in pts) {
      if (cur.isEmpty) {
        cur.add(p);
        continue;
      }
      if (_distKm(cur.last, p) > maxHopKm) {
        if (cur.length >= 2) chunks.add(cur);
        cur = <LatLng>[p];
      } else {
        cur.add(p);
      }
    }
    if (cur.length >= 2) chunks.add(cur);
    return chunks;
  }

  // ====== ROUTE — build avec steps + fallback et anti-diagonales ======
  Future<void> _buildRoute(LatLng dest) async {
    if (_myPos == null) {
      _lastUIError = 'Pas de position courante';
      setState(() {});
      _L('ROUTE', 'no current pos');
      return;
    }
    if (!await _ensureAuth()) return;

    try {
      final r = await _dio.get('/api/directions', queryParameters: {
        'origin': '${_myPos!.latitude},${_myPos!.longitude}',
        'destination': '${dest.latitude},${dest.longitude}',
        'mode': 'driving',
        'language': 'fr',
      });
      _lastRouteStatus = (r.data?['status'] ?? '-').toString();

      final routes = (r.data?['routes'] as List?) ?? const [];
      if (routes.isEmpty) {
        _L('ROUTE', 'no routes');
        setState(() {
          _polylines.clear();
          _lastRoutePoints = 0;
        });
        return;
      }

      // 1) On tente la segmentation par steps (plus robuste)
      final legs = (routes[0]['legs'] as List?) ?? const [];
      final segs = <Polyline>[];
      final allPts = <LatLng>[];
      int segId = 0;

      for (final leg in legs) {
        final steps = (leg['steps'] as List?) ?? const [];
        for (final s in steps) {
          final enc = s['polyline']?['points'] as String?;
          if (enc == null || enc.isEmpty) continue;
          final sane = _sane(_decodePolyline(enc));
          final chunks = _splitByHop(sane, maxHopKm: 40);
          for (final chunk in chunks) {
            allPts.addAll(chunk);
            segs.add(Polyline(
              polylineId: PolylineId('route_${segId++}'),
              points: chunk,
              width: 5,
              color: Colors.deepOrange,
              geodesic: false, // IMPORTANT côté web
              zIndex: 50,
            ));
          }
        }
      }

      // 2) Fallback sur overview_polyline si steps vides
      if (segs.isEmpty) {
        final pointsStr = routes.first['overview_polyline']?['points'] as String?;
        if (pointsStr == null || pointsStr.isEmpty) {
          _L('ROUTE', 'no polyline');
          setState(() {
            _polylines.clear();
            _lastRoutePoints = 0;
          });
          return;
        }
        final sane = _sane(_decodePolyline(pointsStr));
        final chunks = _splitByHop(sane, maxHopKm: 40);
        for (final chunk in chunks) {
          allPts.addAll(chunk);
          segs.add(Polyline(
            polylineId: PolylineId('route_${segId++}'),
            points: chunk,
            width: 5,
            color: Colors.deepOrange,
            geodesic: false,
            zIndex: 50,
          ));
        }
      }

      _L('ROUTE', 'poly points total=${allPts.length} segs=${segs.length}');
      setState(() {
        _polylines.removeWhere((p) => p.polylineId.value.startsWith('route'));
        _polylines.addAll(segs);
        _markers
          ..removeWhere((m) => m.markerId.value == 'dest')
          ..add(Marker(
            markerId: const MarkerId('dest'),
            position: dest,
            infoWindow: const InfoWindow(title: 'Destination'),
          ));
        _lastRoutePoints = allPts.length;
      });

      await _safeFitBounds(allPts);
    } catch (e) {
      _lastRouteStatus = 'HTTP_ERROR';
      _lastUIError = 'Erreur itinéraire: $e';
      setState(() {});
      _L('ROUTEERR', e);
    } finally {
      setState(() {});
    }
  }

  // ====== Helpers carte ======
  Future<void> _goTo(LatLng ll, {double zoom = 14}) async {
    _mapCtrl ??= await _controller.future;
    await _mapCtrl!.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: ll, zoom: zoom)),
    );
  }

  Future<void> _safeFitBounds(List<LatLng> pts) async {
    if (pts.isEmpty) return;

    final sw = LatLng(
      pts.map((e) => e.latitude).reduce(math.min),
      pts.map((e) => e.longitude).reduce(math.min),
    );
    final ne = LatLng(
      pts.map((e) => e.latitude).reduce(math.max),
      pts.map((e) => e.longitude).reduce(math.max),
    );

    try {
      _mapCtrl ??= await _controller.future;
      final ok = sw.latitude <= ne.latitude && sw.longitude <= ne.longitude && sw != ne;
      if (!ok) {
        _L('CAM', 'invalid bounds: $sw / $ne');
        return;
      }
      _L('CAM', 'fit bounds');
      await _mapCtrl!.animateCamera(
        CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 80),
      );
    } catch (e) {
      _L('CAMERR', e);
      _lastUIError = 'AnimateCamera a échoué: $e';
      setState(() {});
    }
  }

  // ====== UI events ======
  Future<void> _submitSearch(String text) async {
    _L('UI', 'submit "$text"');
    _lastUIError = null;
    setState(() {});
    final list = await _searchPlaces(text);
    if (list.isEmpty) {
      _L('UI', 'no predictions');
      _lastUIError = 'Aucun lieu trouvé.';
      setState(() {});
      return;
    }

    final placeId = list.first['place_id']?.toString();
    if (placeId == null) {
      _lastUIError = 'Prediction sans place_id';
      setState(() {});
      return;
    }

    final ll = await _getPlaceLatLng(placeId);
    if (ll == null) {
      _lastUIError = 'Pas de coordonnées';
      setState(() {});
      return;
    }

    // Centre + zoom sur la ville (pas d’itinéraire auto)
    await _goTo(ll, zoom: 14);

    // Marqueur de recherche
    setState(() {
      _markers
        ..removeWhere((m) => m.markerId.value == 'search_city')
        ..add(Marker(
          markerId: const MarkerId('search_city'),
          position: ll,
          infoWindow: InfoWindow(
            title: _searchCtrl.text.trim().isEmpty ? 'Lieu' : _searchCtrl.text.trim(),
          ),
        ));
    });
  }

  Future<void> _routeToCurrentSearch() async {
    final m = _markers
        .cast<Marker?>()
        .firstWhere((mm) => mm?.markerId.value == 'search_city', orElse: () => null);
    if (m == null) {
      _lastUIError = 'Cherche une ville d’abord.';
      setState(() {});
      return;
    }
    await _buildRoute(m.position);
  }

  @override
  Widget build(BuildContext context) {
    _L('BUILD', 'markers=${_markers.length} polys=${_polylines.length} routePts=$_lastRoutePoints');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte des Battues'),
        backgroundColor: Colors.deepOrange,
        actions: [
          IconButton(
            tooltip: 'Itinéraire vers le lieu recherché',
            icon: const Icon(Icons.alt_route),
            onPressed: _routeToCurrentSearch,
          ),
          if (_lastRoutePoints > 0)
            IconButton(
              tooltip: 'Recentrer sur le trajet',
              icon: const Icon(Icons.center_focus_strong),
              onPressed: () {
                final allRoutes = _polylines
                    .where((p) => p.polylineId.value.startsWith('route'))
                    .expand((p) => p.points)
                    .toList(growable: false);
                _safeFitBounds(allRoutes);
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _initial, zoom: 12),
            onMapCreated: (c) async {
              _L('MAP', 'created');
              _controller.complete(c);
              _mapCtrl = c;
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers,
            polylines: _polylines,
            compassEnabled: true,
            zoomControlsEnabled: false,

            // Empêche “multi-planisphère” en dézoom
            cameraTargetBounds: CameraTargetBounds(_frBounds),

            // Evite zooms trop extrêmes (bandes/coutures)
            minMaxZoomPreference: _frZoom,

            mapType: MapType.normal,
          ),

          // Barre de recherche
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: TypeAheadField<Map<String, dynamic>>(
                suggestionsCallback: (p) async {
                  _L('UI', 'suggestions("$p")');
                  if (p.trim().length < 2) return const [];
                  return _searchPlaces(p);
                },
                itemBuilder: (ctx, s) => ListTile(
                  dense: true,
                  title: Text(s['description'] ?? '(sans libellé)'),
                ),
                onSelected: (s) async {
                  _L('UI', 'selected ${s['description']}');
                  final id = s['place_id']?.toString();
                  if (id == null) return;
                  final ll = await _getPlaceLatLng(id);
                  if (ll != null) {
                    await _goTo(ll, zoom: 14);
                    setState(() {
                      _markers
                        ..removeWhere((m) => m.markerId.value == 'search_city')
                        ..add(Marker(
                          markerId: const MarkerId('search_city'),
                          position: ll,
                          infoWindow: InfoWindow(
                            title: s['description']?.toString() ?? 'Lieu',
                          ),
                        ));
                    });
                  }
                },
                builder: (context, controller, focusNode) {
                  _searchCtrl.value = controller.value;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _submitSearch,
                    decoration: InputDecoration(
                      hintText: 'Rechercher une adresse...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Itinéraire depuis ma position',
                        icon: const Icon(Icons.alt_route),
                        onPressed: _routeToCurrentSearch,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  );
                },
                emptyBuilder: (ctx) => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Aucun lieu trouvé.'),
                ),
                loadingBuilder: (ctx) => const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                debounceDuration: const Duration(milliseconds: 250),
              ),
            ),
          ),

          // HUD debug
       /*   Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: _DebugHud(
              hud: _hud,
              places: _lastPlacesStatus,
              details: _lastDetailsStatus,
              route: _lastRouteStatus,
              pts: _lastRoutePoints,
              uiErr: _lastUIError,
            ),
          ),*/
        ],
      ),
    );
  }
}

class _DebugHud extends StatelessWidget {
  final ValueNotifier<String> hud;
  final String places, details, route;
  final int pts;
  final String? uiErr;
  const _DebugHud({
    required this.hud,
    required this.places,
    required this.details,
    required this.route,
    required this.pts,
    required this.uiErr,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: hud,
      builder: (context, text, _) {
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 12, color: Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PLACES=$places  DETAILS=$details  ROUTE=$route  pts=$pts'),
                if (uiErr != null)
                  Text('UI: $uiErr', style: const TextStyle(color: Colors.orangeAccent)),
                const SizedBox(height: 4),
                SizedBox(
                  height: 90,
                  child: SingleChildScrollView(
                    child: Text(text.isEmpty ? '(logs vides)' : text),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
