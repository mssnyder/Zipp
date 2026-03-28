class ConversationParticipant {
  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String role;

  const ConversationParticipant({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.role = 'MEMBER',
  });

  String get name => displayName?.isNotEmpty == true ? displayName! : username;

  factory ConversationParticipant.fromJson(Map<String, dynamic> json) =>
      ConversationParticipant(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        role: json['role'] as String? ?? 'MEMBER',
      );
}

class EpochKeyData {
  final String encryptedKey;
  final String keyNonce;
  final String wrappedById;

  const EpochKeyData({
    required this.encryptedKey,
    required this.keyNonce,
    required this.wrappedById,
  });

  factory EpochKeyData.fromJson(Map<String, dynamic> json) => EpochKeyData(
        encryptedKey: json['encryptedKey'] as String,
        keyNonce: json['keyNonce'] as String,
        wrappedById: json['wrappedById'] as String,
      );
}

class LastMessagePreview {
  final String id;
  final String type;
  final DateTime createdAt;
  final String senderId;
  // DM fields
  final String? recipientCiphertext;
  final String? senderCiphertext;
  // Group field
  final String? ciphertext;
  final String? nonce;
  // Epoch
  final String? epochId;
  final EpochKeyData? epochKey;

  /// Decrypted plaintext — populated client-side.
  String? plaintext;

  LastMessagePreview({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.senderId,
    this.recipientCiphertext,
    this.senderCiphertext,
    this.ciphertext,
    this.nonce,
    this.epochId,
    this.epochKey,
    this.plaintext,
  });

  factory LastMessagePreview.fromJson(Map<String, dynamic> json) =>
      LastMessagePreview(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'TEXT',
        createdAt: DateTime.parse(json['createdAt'] as String),
        senderId: json['senderId'] as String,
        recipientCiphertext: json['recipientCiphertext'] as String?,
        senderCiphertext: json['senderCiphertext'] as String?,
        ciphertext: json['ciphertext'] as String?,
        nonce: json['nonce'] as String?,
        epochId: json['epochId'] as String?,
        epochKey: json['epochKey'] != null
            ? EpochKeyData.fromJson(json['epochKey'] as Map<String, dynamic>)
            : null,
      );
}

class Conversation {
  final String id;
  final bool isGroup;
  final String? name;
  // DM: single participant (the other user)
  final ConversationParticipant? participant;
  // Group: all participants
  final List<ConversationParticipant> participants;
  final LastMessagePreview? lastMessage;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    this.isGroup = false,
    this.name,
    this.participant,
    this.participants = const [],
    this.lastMessage,
    required this.updatedAt,
  });

  /// Display name: group name for groups, participant name for DMs.
  String get displayName {
    if (isGroup) return name ?? 'Group';
    return participant?.name ?? 'Unknown';
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final isGroup = json['isGroup'] as bool? ?? false;
    return Conversation(
      id: json['id'] as String,
      isGroup: isGroup,
      name: json['name'] as String?,
      participant: json['participant'] != null
          ? ConversationParticipant.fromJson(json['participant'] as Map<String, dynamic>)
          : null,
      participants: isGroup && json['participants'] != null
          ? (json['participants'] as List)
              .map((p) => ConversationParticipant.fromJson(p as Map<String, dynamic>))
              .toList()
          : [],
      lastMessage: json['lastMessage'] != null
          ? LastMessagePreview.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Conversation copyWith({
    String? name,
    ConversationParticipant? participant,
    List<ConversationParticipant>? participants,
    LastMessagePreview? lastMessage,
    DateTime? updatedAt,
  }) =>
      Conversation(
        id: id,
        isGroup: isGroup,
        name: name ?? this.name,
        participant: participant ?? this.participant,
        participants: participants ?? this.participants,
        lastMessage: lastMessage ?? this.lastMessage,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
