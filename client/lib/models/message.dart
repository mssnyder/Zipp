import 'reaction.dart';

enum MessageType { text, gif, image, video, file }

class MessageReplyPreview {
  final String id;
  final String senderId;
  final String ciphertext;
  final String nonce;
  final MessageType type;

  const MessageReplyPreview({
    required this.id,
    required this.senderId,
    required this.ciphertext,
    required this.nonce,
    required this.type,
  });

  factory MessageReplyPreview.fromJson(Map<String, dynamic> json) =>
      MessageReplyPreview(
        id: json['id'] as String,
        senderId: json['senderId'] as String,
        ciphertext: json['ciphertext'] as String,
        nonce: json['nonce'] as String,
        type: _parseType(json['type'] as String?),
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
  final String ciphertext;
  final String nonce;
  final MessageType type;
  final String? replyToId;
  final MessageReplyPreview? replyTo;
  final List<Reaction> reactions;
  final DateTime? readAt;
  final DateTime createdAt;

  // Decrypted plaintext — populated client-side after decryption
  String? plaintext;

  ZippMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.ciphertext,
    required this.nonce,
    required this.type,
    this.replyToId,
    this.replyTo,
    required this.reactions,
    this.readAt,
    required this.createdAt,
    this.plaintext,
  });

  bool get isRead => readAt != null;
  bool get isDecrypted => plaintext != null;

  factory ZippMessage.fromJson(Map<String, dynamic> json) => ZippMessage(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        senderId: json['senderId'] as String,
        ciphertext: json['ciphertext'] as String,
        nonce: json['nonce'] as String,
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
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  static MessageType _parseType(String? t) => switch (t) {
        'GIF' => MessageType.gif,
        'IMAGE' => MessageType.image,
        'VIDEO' => MessageType.video,
        'FILE' => MessageType.file,
        _ => MessageType.text,
      };

  ZippMessage copyWith({List<Reaction>? reactions, DateTime? readAt, String? plaintext}) =>
      ZippMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        ciphertext: ciphertext,
        nonce: nonce,
        type: type,
        replyToId: replyToId,
        replyTo: replyTo,
        reactions: reactions ?? this.reactions,
        readAt: readAt ?? this.readAt,
        createdAt: createdAt,
        plaintext: plaintext ?? this.plaintext,
      );
}