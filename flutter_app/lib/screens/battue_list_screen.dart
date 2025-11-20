import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../widgets/battue_list_item.dart';

import '../models/battue.dart';
import '../providers/battue_provider.dart';
import '../providers/auth_provider.dart';      // <-- pour isAdmin
import '../providers/network_status_provider.dart'; // <-- AJOUT
import '../services/api_services.dart';
import 'add_battue_screen.dart';

class BattueListScreen extends StatefulWidget {
  const BattueListScreen({super.key});

  @override
  State<BattueListScreen> createState() => _BattueListScreenState();
}

class _BattueListScreenState extends State<BattueListScreen> {
  @override
  void initState() {
    super.initState();
    // Chargement initial des battues en tenant compte du réseau
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final net = context.read<NetworkStatusProvider>();
      context
          .read<BattueProvider>()
          .fetchBattues(isOnline: net.isOnline); // <-- utilise le mode dégradé
    });
  }

  Future<void> _confirmDelete(Battue b) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer'),
        content: const Text('Confirmer la suppression ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final ok = await ApiServices.deleteBattue(b.id.toString());
      if (!mounted) return;

      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Battue supprimée')),
        );
        final net = context.read<NetworkStatusProvider>();
        await context
            .read<BattueProvider>()
            .fetchBattues(isOnline: net.isOnline);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Battue introuvable')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final friendly = msg.contains('administrateur')
          ? 'Action réservée aux administrateurs.'
          : 'Suppression impossible : $msg';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendly)),
      );
    }
  }

  Future<void> _onAdd() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddBattueScreen()),
    );
    if (!mounted) return;
    final net = context.read<NetworkStatusProvider>();
    await context
        .read<BattueProvider>()
        .fetchBattues(isOnline: net.isOnline);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().isAdmin; // <-- clé UI
    final net = context.watch<NetworkStatusProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F7), // fond clair comme la maquette
      appBar: AppBar(
        title: const Text('Battues'),
        backgroundColor: Colors.deepOrange,
        actions: [
          if (isAdmin) // <-- bouton Ajouter visible seulement pour admin
            IconButton(
              tooltip: 'Ajouter une battue',
              icon: Image.asset(
                'assets/image/plus.png',
                width: 24,
                height: 24,
              ),
              onPressed: _onAdd,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: _ConnectionBanner(isOnline: net.isOnline),
        ),
      ),
      body: Consumer<BattueProvider>(
        builder: (_, p, __) {
          // Indication "données cache" si tu as ajouté loadedFromCache dans le provider
          final List<Widget> children = [];

          if (!net.isOnline) {
            // Optionnel : message supplémentaire dans le body
            children.add(
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'Mode hors-ligne : les données affichées peuvent provenir du cache.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            );
          }

          Widget mainContent;
          if (p.isLoading) {
            mainContent = const Center(child: CircularProgressIndicator());
          } else if (p.battues.isEmpty) {
            mainContent = RefreshIndicator(
              onRefresh: () {
                final net = context.read<NetworkStatusProvider>();
                return context
                    .read<BattueProvider>()
                    .fetchBattues(isOnline: net.isOnline);
              },
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: const [
                  SizedBox(height: 180),
                  Center(child: Text('Aucune battue')),
                ],
              ),
            );
          } else {
            mainContent = RefreshIndicator(
              onRefresh: () {
                final net = context.read<NetworkStatusProvider>();
                return context
                    .read<BattueProvider>()
                    .fetchBattues(isOnline: net.isOnline);
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: p.battues.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final b = p.battues[i];

                  // Carte moderne + bouton supprimer en overlay (admin only)
                  return Stack(
                    children: [
                      BattueListItem(
                        title: b.title,
                        location: b.location ?? '—',
                        dateStr: b.date,
                        onTap: () {
                          // TODO: ouvrir le détail si besoin
                        },
                      ),
                      if (isAdmin)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            elevation: 2,
                            child: IconButton(
                              tooltip: 'Supprimer',
                              iconSize: 22,
                              padding: const EdgeInsets.all(6),
                              icon: Image.asset(
                                'assets/image/delete.png',
                                width: 22,
                                height: 22,
                              ),
                              onPressed: () => _confirmDelete(b),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          }

          children.add(Expanded(child: mainContent));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        },
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle'),
            )
          : null,
    );
  }
}

// Petite bannière "Pas de connexion" réutilisable
class _ConnectionBanner extends StatelessWidget {
  final bool isOnline;
  const _ConnectionBanner({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    if (isOnline) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Colors.red.withOpacity(0.9),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: const Text(
        'Pas de connexion – mode hors-ligne',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
