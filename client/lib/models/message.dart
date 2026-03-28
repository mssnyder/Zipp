import 'conversation.dart';
import 'reaction.dart';

enum MessageType { text, gif, image, video, file }

class MessageReplyPreview {
  final String id;
  final String senderId;
  // DM fields
  final String? recipientCiphertext;
  final String? senderCiphertext;
  // Group field
  final String? ciphertext;
  final String? nonce;
  final MessageType type;
  // Epoch
  final String? epochId;
  final EpochKeyData? epochKey;

  // Decrypted plaintext — populated client-side after decryption
  String? plaintext;

  MessageReplyPreview({
    required this.id,
    required this.senderId,
    this.recipientCiphertext,
    this.senderCiphertext,
    this.ciphertext,
    this.nonce,
    required this.type,
    this.epochId,
    this.epochKey,
    this.plaintext,
  });

  factory MessageReplyPreview.fromJson(Map<String, dynamic> json) =>
      MessageReplyPreview(
        id: json['id'] as String,
        senderId: json['senderId'] as String,
        recipientCiphertext: json['recipientCiphertext'] as String?,
        senderCiphertext: json['senderCiphertext'] as String?,
        ciphertext: json['ciphertext'] as String?,
        nonce: json['nonce'] as String?,
        type: _parseType(json['type'] as String?),
        epochId: json['epochId'] as String?,
        epochKey: json['epochKey'] != null
            ? EpochKeyData.fromJson(json['epochKey'] as Map<String, dynamic>)
            : null,
      );

  static MessageType _parseType(String? t) => switch (t) {
        'GIF' => MessageType.gif,
        'IMAGE' => MessageType.image,
        'VIDEO' => MessageType.video,
        'FILE' => MessageType.file,
        _ => MessageType.text,
      };
}

class ZippMessage {
  final String id;
  final String conversationId;
  final String senderId;
  // DM fields
  final String? recipientCiphertext;
  final String? senderCiphertext;
  // Group field
  final String? ciphertext;
  final String? nonce;
  final MessageType type;
  final String? replyToId;
  final MessageReplyPreview? replyTo;
  final List<Reaction> reactions;
  final DateTime? readAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime createdAt;
  // Epoch
  final String? epochId;
  final EpochKeyData? epochKey;

  // Decrypted plaintext — populated client-side after decryption
  String? plaintext;

  ZippMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.recipientCiphertext,
    this.senderCiphertext,
    this.ciphertext,
    this.nonce,
    required this.type,
    this.replyToId,
    this.replyTo,
    required this.reactions,
    this.readAt,
    this.editedAt,
    this.deletedAt,
    required this.createdAt,
    this.epochId,
    this.epochKey,
    this.plaintext,
  });

  bool get isRead => readAt != null;
  bool get isEdited => editedAt != null;
  bool get isDeleted => deletedAt != null;
  bool get isDecrypted => plaintext != null;
  bool get isGroupMessage => epochId != null;

  factory ZippMessage.fromJson(Map<String, dynamic> json) => ZippMessage(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        senderId: json['senderId'] as String,
        recipientCiphertext: json['recipientCiphertext'] as String?,
        senderCiphertext: json['senderCiphertext'] as String?,
        ciphertext: json['ciphertext'] as String?,
        nonce: json['nonce'] as String?,
        type: _parseType(json['type'] as String?),
        replyToId: json['replyToId'] as String?,
        replyTo: json['replyTo'] != null
            ? MessageReplyPreview.fromJson(json['replyTo'] as Map<String, dynamic>)
            : null,
        reactions: (json['reactions'] as List<dynamic>?)
                ?.map((r) => Reaction.fromJson(r as Map<String, dynamic>))
                .toList() ??
            [],
        readAt: json['readAt'] != null ? DateTime.parse(json['readAt'] as String) : null,
        editedAt: json['editedAt'] != null ? DateTime.parse(json['editedAt'] as String) : null,
        deletedAt: json['deletedAt'] != null ? DateTime.parse(json['deletedAt'] as String) : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
        epochId: json['epochId'] as String?,
        epochKey: json['epochKey'] != null
            ? EpochKeyData.fromJson(json['epochKey'] as Map<String, dynamic>)
            : null,
      );

  static MessageType _parseType(String? t) => switch (t) {
        'GIF' => MessageType.gif,
        'IMAGE' => MessageType.image,
        'VIDEO' => MessageType.video,
        'FILE' => MessageType.file,
        _ => MessageType.text,
      };

  ZippMessage copyWith({
    List<Reaction>? reactions,
    DateTime? readAt,
    DateTime? editedAt,
    DateTime? deletedAt,
    String? plaintext,
    String? recipientCiphertext,
    String? senderCiphertext,
    String? ciphertext,
    String? nonce,
  }) =>
      ZippMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        recipientCiphertext: recipientCiphertext ?? this.recipientCiphertext,
        senderCiphertext: senderCiphertext ?? this.senderCiphertext,
        ciphertext: ciphertext ?? this.ciphertext,
        nonce: nonce ?? this.nonce,
        type: type,
        replyToId: replyToId,
        replyTo: replyTo,
        reactions: reactions ?? this.reactions,
        readAt: readAt ?? this.readAt,
        editedAt: editedAt ?? this.editedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        createdAt: createdAt,
        epochId: epochId,
        epochKey: epochKey,
        plaintext: plaintext ?? this.plaintext,
      );
}
