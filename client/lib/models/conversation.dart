import 'user.dart';

class ConversationParticipant {
  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  const ConversationParticipant({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
  });

  String get name => displayName?.isNotEmpty == true ? displayName! : username;

  factory ConversationParticipant.fromJson(Map<String, dynamic> json) =>
      ConversationParticipant(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
      );
}

class LastMessagePreview {
  final String id;
  final String type;
  final DateTime createdAt;
  final String senderId;

  const LastMessagePreview({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.senderId,
  });

  factory LastMessagePreview.fromJson(Map<String, dynamic> json) =>
      LastMessagePreview(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'TEXT',
        createdAt: DateTime.parse(json['createdAt'] as String),
        senderId: json['senderId'] as String,
      );
}

class Conversation {
  final String id;
  final ConversationParticipant? participant;
  final LastMessagePreview? lastMessage;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    this.participant,
    this.lastMessage,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        participant: json['participant'] != null
            ? ConversationParticipant.fromJson(json['participant'] as Map<String, dynamic>)
            : null,
        lastMessage: json['lastMessage'] != null
            ? LastMessagePreview.fromJson(json['lastMessage'] as Map<String, dynamic>)
            : null,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
