import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/conversation.dart';
import '../../providers/chat_provider.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  const ConversationTile({super.key, required this.conversation});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final p = conversation.participant;
    final name = p?.name ?? 'Unknown';
    final isOnline = p != null && chat.isOnline(p.id);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: ZippTheme.surfaceVariant,
            backgroundImage: p?.avatarUrl != null ? NetworkImage(p!.avatarUrl!) : null,
            child: p?.avatarUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: ZippTheme.accent1,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  )
                : null,
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: ZippTheme.online,
                  shape: BoxShape.circle,
                  border: Border.all(color: ZippTheme.background, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(name, style: Theme.of(context).textTheme.titleMedium),
      subtitle: conversation.lastMessage != null
          ? Text(
              _previewText(conversation.lastMessage!.type),
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: conversation.lastMessage != null
          ? Text(
              _formatTime(conversation.lastMessage!.createdAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
            )
          : null,
      onTap: () => context.push(
        '/chat/${conversation.id}?pid=${p?.id ?? ''}&name=${Uri.encodeComponent(name)}',
      ),
    );
  }

  String _previewText(String type) => switch (type) {
        'GIF' => '🎞️ GIF',
        'IMAGE' => '🖼️ Image',
        'VIDEO' => '🎬 Video',
        'FILE' => '📎 File',
        _ => '🔒 Encrypted message',
      };

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (now.difference(dt).inDays < 1) return DateFormat.jm().format(dt);
    if (now.difference(dt).inDays < 7) return DateFormat.E().format(dt);
    return DateFormat.MMMd().format(dt);
  }
}
