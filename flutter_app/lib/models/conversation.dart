class Conversation {
  final int id;
  final int? peerId;
  final String phone;
  final String? firstName;
  final String? lastName;
  final String? lastMessage;
  final DateTime? updatedAt;

  Conversation({
    required this.id,
    required this.phone,
    this.peerId,
    this.firstName,
    this.lastName,
    this.lastMessage,
    this.updatedAt,
  });

  String get displayName {
    final n = [firstName, lastName]
        .where((e) => (e ?? '').trim().isNotEmpty)
        .join(' ')
        .trim();
    return n.isNotEmpty ? n : phone;
  }

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final peer = j['peer'] as Map<String, dynamic>?;
    final upd = j['updatedAt'] ?? j['last_at'];
    return Conversation(
      id: j['id'] as int,
      peerId: peer?['id'] as int?,
      phone: peer?['phone'] as String? ?? j['phone'] as String? ?? '',
      firstName: peer?['first_name'] as String? ?? j['first_name'] as String?,
      lastName: peer?['last_name'] as String? ?? j['last_name'] as String?,
      lastMessage: (j['lastMessage'] ?? j['last_message']) as String?,
      updatedAt: upd != null ? DateTime.tryParse(upd as String) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'peer': {
      'id': peerId,
      'phone': phone,
      'first_name': firstName,
      'last_name': lastName,
    },
    'lastMessage': lastMessage,
    'updatedAt': updatedAt?.toIso8601String(),
  };
}
