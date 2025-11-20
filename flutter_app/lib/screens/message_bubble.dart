// lib/screens/widgets/message_bubble.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _fmtTime = DateFormat('HH:mm');

enum MsgStatus { sending, sent, received, read }

class MessageBubble extends StatelessWidget {
  final bool mine;
  final String? text;
  final DateTime createdAt;
  final MsgStatus? status; // optionnel, seulement pour MES messages

  const MessageBubble({
    super.key,
    required this.mine,
    required this.text,
    required this.createdAt,
    this.status,
  });

  Icon _statusIcon(MsgStatus s) {
    switch (s) {
      case MsgStatus.sending:
        return const Icon(Icons.access_time, size: 14, color: Colors.grey);
      case MsgStatus.sent:
        return const Icon(Icons.check, size: 16, color: Colors.grey);
      case MsgStatus.received:
        return const Icon(Icons.done_all, size: 16, color: Colors.grey);
      case MsgStatus.read:
        return const Icon(Icons.done_all, size: 16, color: Colors.blue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = mine ? Colors.blue.shade100 : Colors.grey.shade200;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: mine ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: mine ? const Radius.circular(4)  : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((text ?? '').isNotEmpty) Text(text!),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_fmtTime.format(createdAt), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                if (mine && status != null) ...[
                  const SizedBox(width: 6),
                  _statusIcon(status!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
