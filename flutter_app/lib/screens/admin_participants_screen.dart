// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';

import '../services/api_services.dart';

 // <-- pour l’onglet Stats

const kForest     = Color(0xFF0E3A2D);
const kForestDeep = Color(0xFF0A2B22);
const kCard       = Color(0xFF153D31);
const kBeige      = Color(0xFFE9E1D1);
const kBeige70    = Color(0xB3E9E1D1);
const kAccent     = Color(0xFFFFD37A);
class AdminBattueParticipantsScreen extends StatefulWidget {
  const AdminBattueParticipantsScreen({super.key});

  @override
  State<AdminBattueParticipantsScreen> createState() =>
      _AdminBattueParticipantsScreenState();
}

class _AdminBattueParticipantsScreenState
    extends State<AdminBattueParticipantsScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiServices.fetchBattuesWithParticipants();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Participants par battue'),
        backgroundColor: kForest,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erreur : ${snap.error}'));
          }
          final data = snap.data ?? [];
          if (data.isEmpty) {
            return const Center(child: Text('Aucune participation'));
          }

          return ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, index) {
              final b = data[index];
              return ListTile(
                title: Text(b['title']),
                subtitle: Text('${b['location']} • ${b['date']}'),
                trailing: Text('${b['participantCount']} part.'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          BattueParticipantsDetailScreen(battueId: b['id'], title: b['title']),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
class BattueParticipantsDetailScreen extends StatefulWidget {
  final int battueId;
  final String title;
  const BattueParticipantsDetailScreen({
    super.key,
    required this.battueId,
    required this.title,
  });

  @override
  State<BattueParticipantsDetailScreen> createState() =>
      _BattueParticipantsDetailScreenState();
}

class _BattueParticipantsDetailScreenState
    extends State<BattueParticipantsDetailScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiServices.fetchParticipantsForBattue(widget.battueId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Participants • ${widget.title}'),
        backgroundColor: kForest,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erreur : ${snap.error}'));
          }
          final data = snap.data ?? [];
          if (data.isEmpty) {
            return const Center(child: Text('Aucun participant'));
          }

          return ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, index) {
              final p = data[index];
              return ListTile(
                title: Text(p['name'] ?? 'Utilisateur ${p['id']}'),
                subtitle: Text('${p['email'] ?? ''}\n${p['phone'] ?? ''}'),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}
