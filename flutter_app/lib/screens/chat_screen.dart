// lib/screens/chat_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:chassealerte/services/chat_services.dart';

// ====== AJOUTS pour pièces jointes ======
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
// =======================================

class ChatScreen extends StatefulWidget {
  final int conversationId;
  final String socketUrl;       // ex: 'http://localhost:3000'
  final int currentUserId;      // id de l'utilisateur courant
  final ChatService service;    // si besoin d'appels REST
  final String? peerDisplayName; // Nom + Prénom du correspondant (affiché en titre)

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.socketUrl,
    required this.currentUserId,
    required this.service,
    this.peerDisplayName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late sio.Socket _socket;

  final List<Map<String, dynamic>> _messages = [];
  final Set<String> _seen = {}; // dédup (id, clientMsgId ou url)
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  // ====== AJOUTS ======
  bool _uploading = false;
  late String _apiBase; // construit depuis socketUrl → `${socketUrl}/api`
  // ====================

  // ---------- helpers ----------
  String _genClientId() {
    final r = Random();
    final a = r.nextInt(1 << 31);
    final b = r.nextInt(1 << 31);
    return '${DateTime.now().microsecondsSinceEpoch}_$a$b';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ------- Rendu d'une bulle selon le type ------
  Widget _buildBubble(Map<String, dynamic> m) {
    final type = (m['type'] as String?) ?? 'text';
    if (type == 'image') {
      final url = (m['url'] ?? '').toString();
      if (url.isEmpty) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.photo),
            SizedBox(width: 6),
            Text('Image (envoi...)'),
          ],
        );
      }
      return GestureDetector(
        onTap: () => _openFullScreen(url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url, fit: BoxFit.cover),
        ),
      );
    }
    if (type == 'video') {
      final url = (m['url'] ?? '').toString();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              url.isNotEmpty ? 'Vidéo: $url' : 'Vidéo (envoi...)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    // texte “classique”
    return Text((m['text'] ?? '').toString());
  }

  void _openFullScreen(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Center(child: Image.network(url)),
          ),
        ),
      ),
    );
  }

  void _bindSocketListeners() {
    _socket.off('message_created');
    _socket.off('message');

    // Event “plat” utilisé par ton écran (texte + médias)
    _socket.on('message_created', (data) {
      if (!mounted) return;
      final Map<String, dynamic> msg = Map<String, dynamic>.from(data);

      final String? key =
          (msg['id']?.toString()) ??
          (msg['clientMsgId']?.toString()) ??
          (msg['url']?.toString());
      if (key != null && _seen.contains(key)) return;

      final String? clientMsgId = msg['clientMsgId']?.toString();
      final int idx = clientMsgId == null
          ? -1
          : _messages.indexWhere(
              (m) => (m['clientMsgId']?.toString() == clientMsgId),
            );

      setState(() {
        if (key != null) _seen.add(key);
        if (idx >= 0) {
          _messages[idx] = msg;
        } else {
          _messages.add(msg);
        }
      });
      _scrollToEnd();
    });

    // Event complémentaire (si le serveur émet “message”)
    _socket.on('message', (data) {
      if (!mounted) return;
      setState(() {
        _messages.add(Map<String, dynamic>.from(data));
      });
      _scrollToEnd();
    });
  }

  void _joinRoom() => _socket.emit('join_conversation', widget.conversationId);

  @override
  void initState() {
    super.initState();

    // ====== base API dérivée du socketUrl ======
    final base = widget.socketUrl.replaceAll(RegExp(r'/+$'), '');
    _apiBase = '$base/api';

    _socket = sio.io(
      widget.socketUrl,
      sio.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
    );

    _socket.onConnect((_) => _joinRoom());
    _bindSocketListeners();
    _socket.connect();
    _loadHistory();
  }

  @override
  void dispose() {
    _socket.off('message_created');
    _socket.off('message');
    _socket.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
  try {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    final clientMsgId = _genClientId();
    final nowIso = DateTime.now().toIso8601String();

    // ajout optimiste
    final temp = {
      'clientMsgId': clientMsgId,
      'text': text,
      'sender_id': widget.currentUserId,
      'conversationId': widget.conversationId,
      'createdAt': nowIso,
      'status': 'sending',
      'type': 'text',
    };

    setState(() {
      _messages.add(temp);
      _seen.add(clientMsgId);
    });
    _scrollToEnd();
    _input.clear();

    // >>> ENVOI RÉEL via API REST
    await widget.service.sendMessage(
  conversationId: widget.conversationId,
  text: text,
  clientMsgId: clientMsgId,
);


    // La bulle “définitive” arrivera via le socket
    // dans _socket.on('message_created', ...) avec le même clientMsgId
    // et remplacera la bulle 'sending'.
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erreur envoi : $e')),
    );
  }
}
Future<void> _loadHistory() async {
  try {
    final raw = await widget.service.fetchMessages(
      conversationId: widget.conversationId,
      limit: 50,
    );

    if (!mounted) return;

    setState(() {
      _messages.clear();
      _seen.clear();

      for (final m in raw) {
        final id = m['id'];
        final body = (m['body'] ?? '').toString();
        final created = (m['created_at'] ?? '').toString();

        // Pour l’instant on gère surtout le texte.
        // (On pourra mapper attachments → image/vidéo plus tard.)
        final msg = <String, dynamic>{
          'id': id,
          'sender_id': m['sender_id'],
          'conversationId': m['conversation_id'],
          'text': body,
          'type': 'text',
          'createdAt': created,
        };

        _messages.add(msg);
        if (id != null) _seen.add(id.toString());
      }
    });

    _scrollToEnd();
  } catch (e) {
    if (!mounted) return;
    debugPrint('Erreur loadHistory: $e');
    // pas obligatoire mais utile:
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(content: Text('Erreur chargement messages : $e')),
    // );
  }
}


  // =======================
  // sélection & upload pièces jointes
  // =======================
  Future<void> _pickAndSendMedia() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'jpg','jpeg','png','webp','heic','gif',
          'mp4','mov','m4v','webm','avi','mkv'
        ],
        withData: false,
        withReadStream: true,
      );
      if (res == null || res.files.isEmpty) return;

      setState(() => _uploading = true);

      final uri = Uri.parse('$_apiBase/uploads/chat');
      final request = http.MultipartRequest('POST', uri)
        ..fields['conversationId'] = widget.conversationId.toString()
        ..fields['senderId'] = widget.currentUserId.toString();

      for (final f in res.files) {
        // Optimiste: bulles "en cours" (1 bulle par fichier)
        final tempId = _genClientId();
        final nowIso = DateTime.now().toIso8601String();
        final isImage = RegExp(r'\.(jpe?g|png|webp|heic|gif)$', caseSensitive: false).hasMatch(f.name);
        final type = isImage ? 'image' : 'video';

        setState(() {
          _messages.add({
            'clientMsgId': tempId,
            'sender_id': widget.currentUserId,
            'conversationId': widget.conversationId,
            'createdAt': nowIso,
            'status': 'uploading',
            'type': type,
            'name': f.name,
          });
          _seen.add(tempId);
        });

        if (f.path != null) {
          request.files.add(await http.MultipartFile.fromPath('files', f.path!, filename: f.name));
        } else if (f.readStream != null) {
          request.files.add(http.MultipartFile('files', f.readStream!, f.size, filename: f.name));
        }
      }

      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode != 200) {
        throw Exception('Upload échoué (${resp.statusCode}) : ${resp.body}');
      }

      // On laisse le socket “message_created” mettre à jour les bulles.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur envoi média : $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleText = (widget.peerDisplayName?.trim().isNotEmpty ?? false)
        ? widget.peerDisplayName!.trim()
        : 'Conversation #${widget.conversationId}';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retour',
          icon: Image.asset('assets/image/back.png', width: 24, height: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundImage: AssetImage('assets/image/profile.png'),
              backgroundColor: Colors.transparent,
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(titleText, overflow: TextOverflow.ellipsis)),
          ],
        ),
        centerTitle: false,
      ),

      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                final isMine = (m['sender_id']?.toString() == widget.currentUserId.toString());
                final created = (m['createdAt'] ?? m['created_at'] ?? '') as String?;
                final status = (m['status'] ?? '').toString();

                // contenu (texte/image/vidéo)
                final content = _buildBubble(m);

                return Align(
                  alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: isMine ? Colors.blueGrey.shade100 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        content,
                        if (status == 'uploading')
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        if (created != null && created.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              created.length >= 16 ? created.substring(11, 16) : created,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
              child: Row(
                children: [
                  // ====== bouton pièces jointes ======
                  IconButton(
  tooltip: 'Joindre photo/vidéo',
  icon: Image.asset(
    'assets/image/joindre.png', // ton icône locale
    width: 26,
    height: 26,
  ),
  onPressed: _uploading ? null : _pickAndSendMedia,
),

                  // ===================================

                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Écrire un message…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_uploading)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Envoyer',
                    onPressed: _send,
                    icon: Image.asset('assets/image/send.png', width: 24, height: 24),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
