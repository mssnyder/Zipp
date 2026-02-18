class Reaction {
  final String id;
  final String messageId;
  final String userId;
  final String emoji;
  final DateTime createdAt;

  const Reaction({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory Reaction.fromJson(Map<String, dynamic> json) => Reaction(
        id: json['id'] as String,
        messageId: json['messageId'] as String? ?? '',
        userId: json['userId'] as String,
        emoji: json['emoji'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
