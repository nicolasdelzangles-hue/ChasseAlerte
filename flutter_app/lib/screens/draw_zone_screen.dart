import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:convert';
/// Helper icône locale
class LocalIcon extends StatelessWidget {
  final String path;
  final double size;
  const LocalIcon(this.path, {super.key, this.size = 22});
  @override
  Widget build(BuildContext context) =>
      Image.asset(path, width: size, height: size);
}

class DrawZoneScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  const DrawZoneScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  State<DrawZoneScreen> createState() => _DrawZoneScreenState();
}

class _DrawZoneScreenState extends State<DrawZoneScreen> {
  final List<LatLng> _points = [];
  Set<Polygon> _polys = {};
  GoogleMapController? _map;

  void _refresh() {
    setState(() {
      _polys = {
        Polygon(
          polygonId: const PolygonId('zone'),
          points: _points,
          strokeWidth: 3,
          strokeColor: Colors.deepOrange,
          fillColor: Colors.orange.withOpacity(0.30),
        ),
      };
    });
  }

  void _addPoint(LatLng p) {
    _points.add(p);
    _refresh();
  }

  void _undo() {
    if (_points.isNotEmpty) {
      _points.removeLast();
      _refresh();
    }
  }

  void _clear() {
    _points.clear();
    _refresh();
  }

  void _save() {
    if (_points.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute au moins 3 points.')),
      );
      return;
    }
    final geojson = {
      "type": "Polygon",
      "coordinates": [
        _points.map((p) => [p.longitude, p.latitude]).toList()
      ]
    };
    Navigator.pop(context, geojson);
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.initialLat, widget.initialLng);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        leading: IconButton(
          tooltip: 'Retour',
          onPressed: () => Navigator.pop(context),
          icon: const LocalIcon('assets/image/back.png', size: 22),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            //<<<<<<<<LocalIcon('assets/image/zone.png', size: 22), // ← ton logo local
            SizedBox(width: 8),
            Text('Dessiner la zone'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Valider la zone',
            onPressed: _save,
            icon: const LocalIcon('assets/image/marque.png', size: 22),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 14),
            onMapCreated: (c) => _map = c,
            padding: const EdgeInsets.only(bottom: 72), // espace pour la barre
            onTap: _addPoint,
            polygons: _polys,
            zoomControlsEnabled: true,
            myLocationButtonEnabled: true,
          ),

          // Barre d’outils en bas
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                height: 56,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)],
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Annuler le dernier point',
                      onPressed: _undo,
                      icon: const LocalIcon('assets/image/back.png'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Effacer tout',
                      onPressed: _clear,
                      icon: const LocalIcon('assets/image/erase.png'),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      icon: const LocalIcon('assets/image/valider.png', size: 20),
                      label: const Text('Valider'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
