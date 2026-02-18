class ZippUser {
  final String id;
  final String email;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? publicKey;
  final bool emailVerified;
  final bool isAdmin;
  final bool hasPassword;
  final DateTime createdAt;
  final List<String> linkedProviders;

  const ZippUser({
    required this.id,
    required this.email,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.publicKey,
    required this.emailVerified,
    required this.isAdmin,
    required this.hasPassword,
    required this.createdAt,
    this.linkedProviders = const [],
  });

  String get name => displayName?.isNotEmpty == true ? displayName! : username;

  factory ZippUser.fromJson(Map<String, dynamic> json) => ZippUser(
        id: json['id'] as String,
        email: json['email'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        publicKey: json['publicKey'] as String?,
        emailVerified: json['emailVerified'] as bool? ?? false,
        isAdmin: json['isAdmin'] as bool? ?? false,
        hasPassword: json['hasPassword'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        linkedProviders: (json['accounts'] as List<dynamic>?)
                ?.map((a) => a['provider'] as String)
                .toList() ??
            [],
      );
}
