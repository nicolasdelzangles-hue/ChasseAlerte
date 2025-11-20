// lib/screens/add_battue_screen.dart
// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'draw_zone_screen.dart';

import '../providers/auth_provider.dart';
import '../services/api_services.dart';
// import '../config/api_keys.dart'; // plus besoin de clé Google côté front

// --------- Logger simple ----------
String _ts() => DateTime.now().toIso8601String();
void _log(String tag, Object? msg) => print('[${_ts()}][$tag] $msg');

// --------- Icône locale réutilisable ----------
class LocalIcon extends StatelessWidget {
  final String path;
  final double size;
  const LocalIcon(this.path, {super.key, this.size = 22});
  @override
  Widget build(BuildContext context) => Image.asset(path, width: size, height: size);
}

class AddBattueScreen extends StatefulWidget {
  const AddBattueScreen({super.key});

  @override
  State<AddBattueScreen> createState() => _AddBattueScreenState();
}

class _AddBattueScreenState extends State<AddBattueScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  // Champs “métier”
  String title = '';
  String location = '';
  String date = '';
  String description = '';
  String imageUrl = ''; // on réutilise pour stocker le GeoJSON de zone
  String type = '';
  bool isPrivate = false;

  // Adresse (remplace lat/lng)
  final TextEditingController _address = TextEditingController();
  double? _lat;
  double? _lng;
  bool _geocoding = false;

  @override
  void initState() {
    super.initState();

    // Rebuild du suffixIcon quand le texte change
    _address.addListener(() {
      if (mounted) setState(() {});
    });

    // Garde UX: si pas admin, on empêche l’accès à l’écran
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isAdmin = context.read<AuthProvider>().isAdmin;
      if (!isAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action réservée aux administrateurs.')),
        );
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  // ---------- Géocodage via BACKEND (adresse -> lat/lng) ----------
  Future<void> _geocodeAddress() async {
    final raw = _address.text.trim();
    _log('UI', 'geo-btn pressed address="$raw"');

    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisis une adresse à géocoder.')),
      );
      return;
    }

    setState(() => _geocoding = true);
    try {
      final uri = Uri.parse('${ApiServices.baseUrl}/api/geocode')
          .replace(queryParameters: {'q': raw});

      _log('HTTP', 'GET $uri');
      final headers = await ApiServices.authHeaders();
      final r = await http.get(uri, headers: headers);
      _log('HTTP', 'STATUS ${r.statusCode}  len=${r.body.length}');

      if (r.statusCode != 200) {
        throw 'HTTP ${r.statusCode} ${r.body}';
      }

      final data = jsonDecode(r.body) as Map<String, dynamic>;

      final double lat = (data['lat'] as num).toDouble();
      final double lng = (data['lon'] ?? data['lng'] as num).toDouble();

      final String? formatted =
          (data['displayName'] ?? data['formatted_address'])?.toString();

      _log('GEO', 'ok lat=$lat lng=$lng name="${formatted ?? ''}"');

      setState(() {
        _lat = lat;
        _lng = lng;
        if (formatted != null && formatted.isNotEmpty) {
          _address.text = formatted;
        }
      });
    } catch (e) {
      _log('GEO', 'error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec géocodage : $e')),
      );
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_lat == null || _lng == null) {
      _log('UI', 'submit -> no coords, trying geocode');
      await _geocodeAddress();
      if (_lat == null || _lng == null) {
        _log('UI', 'submit -> still no coords after geocode');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adresse invalide ou introuvable.')),
        );
        return;
      }
    }

    setState(() => _loading = true);
    try {
      _log('HTTP', 'POST addBattue lat=$_lat lng=$_lng');
      await ApiServices.addBattue({
        'title': title,
        'location': location,
        'date': date.isEmpty ? DateTime.now().toIso8601String() : date,
        'description': description,
        'imageUrl': imageUrl, // contient GeoJSON de la zone pour l’instant
        'latitude': _lat,
        'longitude': _lng,
        'type': type,
        'isPrivate': isPrivate,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Battue créée')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final friendly = msg.contains('administrateur')
          ? 'Action réservée aux administrateurs.'
          : 'Erreur : $msg';
      _log('HTTP', 'addBattue error: $msg');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().isAdmin;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        leading: IconButton(
          tooltip: 'Retour',
          icon: Image.asset('assets/image/back.png', width: 24, height: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Ajouter une battue'),
      ),
      body: AbsorbPointer(
        absorbing: !isAdmin,
        child: Opacity(
          opacity: isAdmin ? 1 : 0.5,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Titre
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Titre'),
                  onChanged: (v) => title = v,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Requis' : null,
                ),
                const SizedBox(height: 8),

                // Lieu / zone
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Lieu (zone/commune)'),
                  onChanged: (v) => location = v,
                ),
                const SizedBox(height: 8),

                // Date
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD ou ISO)'),
                  onChanged: (v) => date = v,
                  keyboardType: TextInputType.datetime,
                ),
                const SizedBox(height: 8),

                // Description
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Description'),
                  onChanged: (v) => description = v,
                  maxLines: 3,
                ),
                const SizedBox(height: 8),

                // ---------- Bouton "Dessiner la zone" ----------
                if (_lat != null && _lng != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      icon: const LocalIcon('assets/image/carte_icone.png', size: 20),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      label: const Text('Dessiner la zone sur la carte'),
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DrawZoneScreen(
                              initialLat: _lat!,
                              initialLng: _lng!,
                            ),
                          ),
                        );
                        if (!mounted) return;
                        if (result != null) {
                          setState(() {
                            imageUrl = jsonEncode(result); // stocke la zone (GeoJSON)
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Zone enregistrée ✅')),
                          );
                        }
                      },
                    ),
                  ),
                ],

                // ---------- Adresse + Bouton Géocoder ----------
                const SizedBox(height: 16),
                Text(
                  'Adresse (au lieu de Latitude / Longitude)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _address,
                  decoration: InputDecoration(
                    hintText: 'Ex: 10 Rue des Lilas, 75000 Paris',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed:
                          _geocoding || _address.text.trim().isEmpty ? null : _geocodeAddress,
                      icon: _geocoding
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const LocalIcon('assets/image/localisateur.png', size: 18),
                      tooltip: 'Géocoder',
                    ),
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Adresse requise' : null,
                  onFieldSubmitted: (_) => _geocodeAddress(),
                ),

                // Vignette statique (si coords déjà trouvées)
                if (_lat != null && _lng != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      // On passe maintenant par le backend, qui ajoute la clé serveur
                      Uri.parse('${ApiServices.baseUrl}/api/static-map')
                          .replace(queryParameters: {
                            'lat': _lat!.toString(),
                            'lng': _lng!.toString(),
                            'zoom': '15',
                            'size': '600x240',
                          })
                          .toString(),
                      height: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                SwitchListTile(
                  value: isPrivate,
                  onChanged: (v) => setState(() => isPrivate = v),
                  title: const Text('Privée'),
                ),

                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enregistrer'),
                ),

                if (!isAdmin) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Action réservée aux administrateurs.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
