import 'package:chassealerte/screens/Reportscreen.dart';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_services.dart';
import 'edit_profile_screen.dart';
import 'report_inbox_screen.dart';
import 'admin_participants_screen.dart';

/// Helper pour utiliser des icônes locales
class LocalIcon extends StatelessWidget {
  final String path;
  final double size;
  const LocalIcon(this.path, {super.key, this.size = 22});

  @override
  Widget build(BuildContext context) =>
      Image.asset(path, width: size, height: size);
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    print('=== [PROFILE] _load() démarré ===');
    try {
      // ⬅️ on revient au getProfile ORIGINAL (celui qui marchait)
      final me = await ApiServices.getProfile();

      print('=== [PROFILE] getProfile() OK ===');
      print('   email: ${me.email}');
      print('   role : ${me.role}');

      if (!mounted) return;
      setState(() {
        _user = me;
        _loading = false;
      });

      print('=== [PROFILE] _user mis à jour ===');
      print('   _user.email = ${_user?.email}');
      print('   _user.role  = ${_user?.role}');
    } catch (e) {
      print('=== [PROFILE] ERREUR dans _load() ===');
      print(e);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _fullName(User u) {
    final parts = <String>[];
    if ((u.firstName ?? '').trim().isNotEmpty) parts.add(u.firstName!.trim());
    if ((u.lastName ?? '').trim().isNotEmpty) parts.add(u.lastName!.trim());
    final full = parts.join(' ');
    return full.isNotEmpty ? full : (u.name ?? '').trim();
  }

  String _initials(User u) {
    final f = (u.firstName ?? '').trim();
    final l = (u.lastName ?? '').trim();
    final n = (u.name ?? '').trim();
    String s = '';
    if (f.isNotEmpty) s += f[0];
    if (l.isNotEmpty) s += l[0];
    if (s.isEmpty && n.isNotEmpty) {
      final p = n.split(RegExp(r'\s+'));
      if (p.isNotEmpty) s = p.first[0];
    }
    return s.toUpperCase();
  }

  String? _formatDate(DateTime? d) {
    if (d == null) return null;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    return '$dd/$mm/$yy';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // rôle normalisé (si le champ n’existe pas encore côté API, ça reste null)
    final String roleNorm = (_user?.role ?? '').toString().toLowerCase();
    final bool isAdmin = roleNorm == 'admin';

    print('=== [PROFILE] build() ===');
    print('   _loading   = $_loading');
    print('   _user.email = ${_user?.email}');
    print('   _user.role  = ${_user?.role}');
    print('   roleNorm    = $roleNorm');
    print('   isAdmin     = $isAdmin');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        backgroundColor: Colors.deepOrange,
        actions: [
          if (!_loading && _user != null)
            IconButton(
              tooltip: 'Modifier le profil',
              icon: const LocalIcon('assets/image/modifier.png', size: 24),
              onPressed: () async {
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(user: _user!),
                  ),
                );
                if (updated == true) {
                  _load(); // refresh après sauvegarde
                }
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_user == null)
              ? const Center(child: Text('Impossible de charger le profil.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.deepOrange.shade200,
                          child: Text(
                            _initials(_user!),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _fullName(_user!),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _user!.email ?? '',
                                style: theme.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.black12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Column(
                          children: [
                            _kv('Prénom', _user!.firstName),
                            _kv('Nom', _user!.lastName),
                            _kv('Nom complet', _user!.name),
                            _kv('Téléphone', _user!.phone),
                            _kv('Adresse', _user!.address),
                            _kv('Code postal', _user!.postalCode),
                            _kv('Ville', _user!.city),
                            _kv('N° permis', _user!.permitNumber),
                            _kv('Compte créé le', _formatDate(_user!.createdAt)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: const Icon(Icons.report),
                      label: const Text('Signaler cet utilisateur'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ReportScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    // Bouton admin (sera visible quand role = "admin")
                    // Boutons admin (visibles uniquement si role = "admin")
if (isAdmin) ...[
  const SizedBox(height: 16),

  FilledButton.icon(
    icon: const Icon(Icons.mail),
    label: const Text('Voir les signalements'),
    style: FilledButton.styleFrom(
      backgroundColor: Colors.blueGrey.shade700,
      padding: const EdgeInsets.symmetric(vertical: 14),
    ),
    onPressed: () {
      print('=== [PROFILE] Clic sur "Voir les signalements" ===');
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ReportInboxScreen(),
        ),
      );
    },
  ),

  const SizedBox(height: 8),

  FilledButton.icon(
    icon: const Icon(Icons.people),
    label: const Text('Participants aux battues'),
    style: FilledButton.styleFrom(
      backgroundColor: Colors.teal.shade700,
      padding: const EdgeInsets.symmetric(vertical: 14),
    ),
    onPressed: () {
      print('=== [PROFILE] Clic sur "Participants aux battues" ===');
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AdminBattueParticipantsScreen(),
        ),
      );
    },
  ),
],

                  ],
                ),
    );
  }

  Widget _kv(String label, String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: SelectableText(v)),
        ],
      ),
    );
  }
}
