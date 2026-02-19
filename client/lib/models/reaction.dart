class Reaction {
  final String id;
  final String messageId;
  final String userId;
  final String emoji;
  final String? displayName;
  final DateTime createdAt;

  const Reaction({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.emoji,
    this.displayName,
    required this.createdAt,
  });

  factory Reaction.fromJson(Map<String, dynamic> json) => Reaction(
        id: json['id'] as String,
        messageId: json['messageId'] as String? ?? '',
        userId: json['userId'] as String,
        emoji: json['emoji'] as String,
        displayName: json['displayName'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
