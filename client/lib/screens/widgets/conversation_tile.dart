import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/conversation.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback? onTap;
  final bool isSelected;
  const ConversationTile({
    super.key,
    required this.conversation,
    this.onTap,
    this.isSelected = false,
  });

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
            backgroundImage: p?.avatarUrl != null ? NetworkImage(context.read<ApiService>().resolveUrl(p!.avatarUrl!)) : null,
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
              _previewText(conversation.lastMessage!, chat),
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
      selected: isSelected,
      selectedTileColor: ZippTheme.surfaceVariant,
      onTap: onTap ?? () => context.push(
        '/chat/${conversation.id}?pid=${p?.id ?? ''}&name=${Uri.encodeComponent(name)}',
      ),
    );
  }

  String _previewText(LastMessagePreview lastMsg, ChatProvider chat) {
    // For non-text types, show a generic label
    switch (lastMsg.type) {
      case 'GIF': return '🎞️ GIF';
      case 'IMAGE': return '🖼️ Image';
      case 'VIDEO': return '🎬 Video';
      case 'FILE': return '📎 File';
    }
    // Use the decrypted plaintext from the preview itself
    if (lastMsg.plaintext != null) return lastMsg.plaintext!;
    // Fall back to checking loaded messages cache
    final messages = chat.messagesFor(conversation.id);
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].id == lastMsg.id && messages[i].plaintext != null) {
        return messages[i].plaintext!;
      }
    }
    return '🔒 Encrypted message';
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    if (now.difference(local).inDays < 1) return DateFormat.jm().format(local);
    if (now.difference(local).inDays < 7) return DateFormat.E().format(local);
    return DateFormat.MMMd().format(local);
  }
}
