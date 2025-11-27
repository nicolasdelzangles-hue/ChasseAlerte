// lib/screens/chat_list_screen.dart
import 'dart:async';
import 'package:chassealerte/services/api_services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/chat_services.dart';
import '../services/conv_favorite_service.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  // Adapte à ton réseau si besoin
  static const String _apiBase = '${ApiConfig.baseUrl}/api';

  static const String _socketUrl = ApiConfig.baseUrl;

  final _phoneCtrl = TextEditingController();
  final _phoneFocus = FocusNode();

  ChatService? _service;
  ConvFavoriteService? _favService;

  List<dynamic> _conversations = [];
  final Set<int> _favConvs = <int>{};

  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _phoneFocus.unfocus();
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  // ---------------- init / load ----------------
  Future<void> _init() async {
    try {
      final auth = context.read<AuthProvider>();
      final token = await auth.getToken();
      if (token == null) throw Exception('Token manquant, reconnecte-toi.');

      _service = ChatService(baseUrl: _apiBase, token: token);
      _favService = ConvFavoriteService(baseUrl: _apiBase, token: token);

      await Future.wait([_loadConversations(), _loadFavorites()]);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadConversations() async {
    if (_service == null) return;
    final list = await _service!.getConversations();
    if (!mounted) return;
    setState(() => _conversations = list);
  }

  Future<void> _loadFavorites() async {
    if (_favService == null) return;
    final ids = await _favService!.fetchFavorites();
    if (!mounted) return;
    setState(() {
      _favConvs
        ..clear()
        ..addAll(ids);
    });
  }

  // ---------------- helpers ----------------
  Future<void> _showErrorDialog(String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: const Text('Erreur'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) {
                FocusScope.of(context).requestFocus(_phoneFocus);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String? _toE164Fr(String input) {
    var p = input.replaceAll(RegExp(r'\s+'), '');
    if (p.isEmpty) return null;
    if (p.startsWith('0')) {
      p = '+33${p.substring(1)}';
    } else if (!p.startsWith('+')) {
      p = '+33$p';
    }
    final fr = RegExp(r'^\+33[1-9]\d{8}$');
    return fr.hasMatch(p) ? p : null;
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return int.tryParse(v.toString());
  }

  // ---------------- actions ----------------
  Future<void> _addConversation() async {
    if (_service == null) return;

    final raw = _phoneCtrl.text.trim();
    final e164 = _toE164Fr(raw);
    if (e164 == null) {
      await _showErrorDialog(
        "Format attendu : 0XXXXXXXXX ou +33XXXXXXXXX (9 chiffres après l'indicatif).",
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final res = await _service!.createConversationByPhone(e164);
      await _loadConversations();
      if (!mounted) return;
      _phoneCtrl.clear();

      final convId = (res['id'] as num).toInt();
      _openConversation({'id': convId});
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      await _showErrorDialog(msg.isEmpty ? "Une erreur est survenue." : msg);
    } finally {
      if (!mounted) return;
      setState(() => _creating = false);
    }
  }

  void _openConversation(Map<String, dynamic> conv) {
    final auth = context.read<AuthProvider>();
    final dynamic rawId = auth.user?.id ?? auth.currentUser?.id;
    final int? currentUserId = _asInt(rawId);

    if (currentUserId == null || _service == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Session invalide')));
      }
      return;
    }

    // Calcul du nom pour l’AppBar
    final convObj = _conversations.firstWhere(
      (e) => _asInt(e['id']) == _asInt(conv['id']),
      orElse: () => conv,
    );
    final displayName = _computeTitle(Map<String, dynamic>.from(convObj));

    final conversationId = _asInt(conv['id'])!;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          service: _service!,
          socketUrl: _socketUrl,
          currentUserId: currentUserId,
          peerDisplayName: displayName,
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(int convId) async {
    if (!mounted) return;
    setState(() {
      if (_favConvs.contains(convId)) {
        _favConvs.remove(convId);
      } else {
        _favConvs.add(convId);
      }
    });

    try {
      await _favService!.toggleFavorite(convId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_favConvs.contains(convId)) {
          _favConvs.remove(convId);
        } else {
          _favConvs.add(convId);
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur favoris: $e')));
    }
  }

  Future<void> _deleteConversation(int convId) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la discussion ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _service!.deleteConversation(convId);
      if (!mounted) return;
      setState(() {
        _conversations.removeWhere((e) => _asInt(e['id']) == convId);
        _favConvs.remove(convId);
      });
    } catch (e) {
      await _showErrorDialog('Suppression impossible : $e');
    }
  }

  // ---------------- bottom sheet: création de groupe ----------------
  Future<void> _openCreateGroupSheet() async {
    if (!mounted) return;

    await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final nameCtrl = TextEditingController();
        final memberInputCtrl = TextEditingController();
        final focusNode = FocusNode();

        List<Map<String, dynamic>> suggestions = [];
        final List<Map<String, dynamic>> selected = []; // {id, first_name, last_name, phone}
        String? err;
        bool creating = false;
        Timer? debounce;

        String _labelOf(Map<String, dynamic> u) {
          final f = (u['first_name'] as String?)?.trim() ?? '';
          final l = (u['last_name'] as String?)?.trim() ?? '';
          final full = ('$f $l').trim();
          return full.isNotEmpty ? full : (u['phone'] as String? ?? 'Utilisateur #${u['id']}');
        }

        String? toE164Fr(String input) {
          var p = input.replaceAll(RegExp(r'\s+'), '');
          if (p.isEmpty) return null;
          if (p.startsWith('0')) p = '+33${p.substring(1)}';
          else if (!p.startsWith('+')) p = '+33$p';
          final fr = RegExp(r'^\+33[1-9]\d{8}$');
          return fr.hasMatch(p) ? p : null;
        }

        Future<void> runSearch(String q, void Function(void Function()) setLocal) async {
          if (_service == null) return;
          if (q.trim().isEmpty) {
            setLocal(() => suggestions = []);
            return;
          }
          try {
            final res = await _service!.searchUsers(q.trim());
            setLocal(() => suggestions = res);
          } catch (_) {
            setLocal(() => suggestions = []);
          }
        }

        Future<void> tryAddCurrentInput(void Function(void Function()) setLocal) async {
          final raw = memberInputCtrl.text.trim();
          if (raw.isEmpty) return;

          final e164 = toE164Fr(raw);
          if (e164 != null) {
            final user = await _service!.userByPhone(e164);
            if (user != null && user['id'] != null) {
              final already = selected.any((u) => u['id'] == user['id']);
              if (!already) setLocal(() => selected.add(user));
              setLocal(() {
                memberInputCtrl.clear();
                suggestions = [];
                err = null;
              });
              return;
            } else {
              setLocal(() => err = 'Aucun utilisateur avec ce numéro.');
              return;
            }
          }

          if (suggestions.isNotEmpty) {
            final u = suggestions.first;
            final already = selected.any((x) => x['id'] == u['id']);
            if (!already) setLocal(() => selected.add(u));
            setLocal(() {
              memberInputCtrl.clear();
              suggestions = [];
              err = null;
            });
            return;
          }

          setLocal(() => err = 'Aucun résultat pour "$raw".');
        }

        Future<void> doCreate(void Function(void Function()) setLocal) async {
          if (_service == null) return;
          final title = nameCtrl.text.trim();
          if (title.isEmpty || selected.isEmpty) {
            setLocal(() => err = 'Nom et au moins un membre sont requis.');
            return;
          }

          setLocal(() {
            creating = true;
            err = null;
          });

          try {
            final ids = selected.map((u) => (u['id'] as num).toInt()).toList();
            final res = await _service!.createGroup(title: title, memberIds: ids);

            if (!mounted) return;
            Navigator.pop(ctx);
            await _loadConversations();

            final convId = _asInt(res['id']);
            if (convId != null) _openConversation({'id': convId});
          } catch (e) {
            setLocal(() => err = e.toString().replaceFirst('Exception: ', ''));
          } finally {
            setLocal(() => creating = false);
          }
        }

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16, right: 16, top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset('assets/image/groupe.png', width: 22, height: 22),
                        const SizedBox(width: 8),
                        const Text(
                          'Nouveau groupe',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nom du groupe',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final u in selected)
                            Chip(
                              label: Text(_labelOf(u)),
                              onDeleted: () => setLocal(() => selected.remove(u)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Champ de recherche / ajout de membres
                    TextField(
                      controller: memberInputCtrl,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Ajouter membres (nom/prénom ou téléphone)',
                        hintText: 'ex: Paul, 0612345678, Delz...',
                        border: const OutlineInputBorder(),
                        // <-- icône locale (évite le carré barré sur Web)
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 24, height: 24,
                            child: Image.asset(
                              'assets/image/profile.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        suffixIconConstraints:
                            const BoxConstraints(minWidth: 40, minHeight: 40),
                      ),
                      onChanged: (v) {
                        debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 250), () {
                          runSearch(v, setLocal);
                        });
                      },
                      onSubmitted: (_) => tryAddCurrentInput(setLocal),
                    ),

                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          itemCount: suggestions.length,
                          itemBuilder: (_, i) {
                            final u = suggestions[i];
                            return ListTile(
                              dense: true,
                              leading: const CircleAvatar(
                                radius: 16,
                                backgroundImage:
                                    AssetImage('assets/image/profile.png'),
                                backgroundColor: Colors.transparent,
                              ),
                              title: Text(_labelOf(u)),
                              subtitle: (u['phone'] != null)
                                  ? Text('${u['phone']}')
                                  : null,
                              onTap: () {
                                final already =
                                    selected.any((x) => x['id'] == u['id']);
                                if (!already) setLocal(() => selected.add(u));
                                setLocal(() {
                                  memberInputCtrl.clear();
                                  suggestions = [];
                                  err = null;
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],

                    if (err != null) ...[
                      const SizedBox(height: 8),
                      Text(err!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Annuler'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: creating ? null : () => doCreate(setLocal),
                          child: creating
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Créer'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------- display helpers ----------------
  String _computeTitle(Map<String, dynamic> c) {
    final dn = (c['display_name'] as String?)?.trim();
    if (dn != null && dn.isNotEmpty) return dn;

    final peer = c['peer'] as Map<String, dynamic>?;
    if (peer != null) {
      final first = (peer['first_name'] as String?)?.trim() ?? '';
      final last = (peer['last_name'] as String?)?.trim() ?? '';
      final full = ('$first $last').trim();
      if (full.isNotEmpty) return full;
      final phone = (peer['phone'] as String?)?.trim();
      if (phone != null && phone.isNotEmpty) return phone;
    }

    final legacyName = (c['otherUserName'] as String?)?.trim();
    if (legacyName != null && legacyName.isNotEmpty) return legacyName;

    final title = (c['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty) return title;

    return 'Conversation #${c['id']}';
  }

  String _computeLast(Map<String, dynamic> c) {
    final lm = c['last_message'] as Map<String, dynamic>?;
    if (lm != null) {
      final body = (lm['body'] as String?)?.trim();
      if (body != null && body.isNotEmpty) return body;
    }
    final legacy = c['lastMessage'] as Map<String, dynamic>?;
    if (legacy != null) {
      final content = (legacy['content'] as String?)?.trim();
      if (content != null && content.isNotEmpty) return content;
    }
    return '';
  }

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Erreur: $_error'));

    final sorted = List<Map<String, dynamic>>.from(_conversations.cast());
    sorted.sort((a, b) {
      final aFav = _favConvs.contains(_asInt(a['id']));
      final bFav = _favConvs.contains(_asInt(b['id']));
      if (aFav == bFav) return 0;
      return aFav ? -1 : 1;
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Discussions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateGroupSheet,
        icon: Image.asset('assets/image/groupe.png', width: 22, height: 22),
        label: const Text('Nouveau groupe'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    focusNode: _phoneFocus,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Numéro français (ex: 0612345678)',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addConversation(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _creating ? null : _addConversation,
                  child: _creating
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Ajouter'),
                ),
              ],
            ),
          ),
          const Divider(height: 0),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadConversations();
                await _loadFavorites();
              },
              child: ListView.separated(
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (_, i) {
                  final c = Map<String, dynamic>.from(sorted[i]);
                  final id = _asInt(c['id'])!;
                  final titleToShow = _computeTitle(c);
                  final last = _computeLast(c);
                  final isFav = _favConvs.contains(id);

                  return ListTile(
                    leading: const CircleAvatar(
                      radius: 20,
                      backgroundImage: AssetImage('assets/image/profile.png'),
                      backgroundColor: Colors.transparent,
                    ),
                    title: Text(titleToShow),
                    subtitle: Text(
                      last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _openConversation({'id': id}),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isFav)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Image.asset(
                              'assets/image/star.png',
                              width: 20,
                              height: 20,
                            ),
                          ),
                        PopupMenuButton<String>(
                          tooltip: 'Options',
                          icon: Image.asset(
                            'assets/image/3points.png',
                            width: 22,
                            height: 22,
                          ),
                          onSelected: (value) async {
                            switch (value) {
                              case 'fav':
                                await _toggleFavorite(id);
                                break;
                              case 'delete':
                                await _deleteConversation(id);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'fav',
                              child: Text(isFav
                                  ? 'Retirer des favoris'
                                  : 'Ajouter aux favoris'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Supprimer la conversation'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
