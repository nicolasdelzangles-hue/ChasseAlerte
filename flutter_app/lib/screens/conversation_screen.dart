import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../services/api_services.dart';
import '../services/chat_services.dart';
import '../screens/chat_screen.dart';
import 'package:provider/provider.dart';

// Utilisé pour le ChatService (même base que l'API)
const String kApiBaseUrl = ApiConfig.baseUrl;

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late Future<User> _meFuture;
  late Future<List<Map<String, dynamic>>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _meFuture = ApiServices.getProfile();          // ← renvoie un User
    _conversationsFuture = _fetchConversations();  // ← renvoie Future<List<Map>>
  }

  Future<List<Map<String, dynamic>>> _fetchConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    // IMPORTANT : ChatService exige baseUrl et token (erreur que tu vois)
    final chat = ChatService(baseUrl: kApiBaseUrl, token: token);

    // Si getConversations() renvoie List<dynamic>, on cast proprement
    final raw = await chat.getConversations(); // Future<List<dynamic>> ou Future<List<Map>>
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _conversationsFuture = _fetchConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversations'),
        backgroundColor: Colors.deepOrange,
      ),
      body: FutureBuilder<User>(
        future: _meFuture,
        builder: (context, meSnap) {
          if (meSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (meSnap.hasError) {
            return Center(child: Text('Erreur profil : ${meSnap.error}'));
          }
          final me = meSnap.data!; // User (PAS une Map)

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _conversationsFuture,
            builder: (context, convSnap) {
              if (convSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (convSnap.hasError) {
                return Center(child: Text('Erreur conversations : ${convSnap.error}'));
              }

              final conversations = convSnap.data ?? [];
              if (conversations.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: const [
                      Center(child: Text('Aucune conversation')),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  itemCount: conversations.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final conv = conversations[i]; // Map<String, dynamic>
                    final title = (conv['title'] as String?) ?? 'Sans titre';

                    // participants : List<Map<String,dynamic>> attendu
                    final List<Map<String, dynamic>> participants =
                        (conv['participants'] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            const [];

                    // on affiche l'autre participant (différent de moi) si présent
                    final other = participants.firstWhere(
                      (p) => (p['email'] as String? ?? '') != (me.email ?? ''),
                      orElse: () => <String, dynamic>{},
                    );
                    final otherName = (other['name'] as String?) ??
                        (other['email'] as String?) ??
                        title;

                    final lastMsg = (conv['lastMessage'] as String?) ?? '';

                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(otherName),
                      subtitle: Text(
                        lastMsg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
  final auth = context.read<AuthProvider>();
  final user = auth.currentUser;
  final token = auth.token;          // <-- adapte le nom si besoin

  if (user == null || token == null) return;

  final displayName = otherName;     // ou ton calcul existant

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: conv['id'] as int,
        socketUrl: ApiServices.socketUrl,        // pour Socket.IO
        currentUserId: user.id!,  // <- on enlève le ? en disant "je sais qu'il n’est pas null"

        service: ChatService(
          baseUrl: ApiServices.baseUrl,         // pour l’API REST
          token: token,
        ),
        peerDisplayName: displayName,
      ),
    ),
  );
},


                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
