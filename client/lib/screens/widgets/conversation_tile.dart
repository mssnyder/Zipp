import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/conversation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import 'group_avatar.dart';

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
    final api = context.read<ApiService>();
    final myId = context.read<AuthProvider>().user?.id ?? '';
    final isGroup = conversation.isGroup;
    final p = conversation.participant;
    final name = conversation.displayName;
    final isOnline = !isGroup && p != null && chat.isOnline(p.id);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          if (isGroup)
            GroupAvatar(
              participants: conversation.participants,
              currentUserId: myId,
              size: 52,
              api: api,
            )
          else
            CircleAvatar(
              radius: 26,
              backgroundColor: ZippTheme.surfaceVariant,
              backgroundImage: p?.avatarUrl != null ? NetworkImage(api.resolveUrl(p!.avatarUrl!)) : null,
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
              _previewText(conversation.lastMessage!, chat, myId),
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
      onTap: onTap ?? () => context.push('/chat/${conversation.id}'),
    );
  }

  String _previewText(LastMessagePreview lastMsg, ChatProvider chat, String myId) {
    String text;
    // For non-text types, show a generic label
    switch (lastMsg.type) {
      case 'GIF': text = '🎞️ GIF'; break;
      case 'IMAGE': text = '🖼️ Image'; break;
      case 'VIDEO': text = '🎬 Video'; break;
      case 'FILE': text = '📎 File'; break;
      default:
        // Use the decrypted plaintext from the preview itself
        if (lastMsg.plaintext != null) {
          text = lastMsg.plaintext!;
        } else {
          // Fall back to checking loaded messages cache
          final messages = chat.messagesFor(conversation.id);
          String? cached;
          for (var i = messages.length - 1; i >= 0; i--) {
            if (messages[i].id == lastMsg.id && messages[i].plaintext != null) {
              cached = messages[i].plaintext!;
              break;
            }
          }
          text = cached ?? '🔒 Encrypted message';
        }
    }
    // For groups, prefix with sender name
    if (conversation.isGroup) {
      final isMe = lastMsg.senderId == myId;
      if (isMe) {
        text = 'You: $text';
      } else {
        final sender = conversation.participants
            .cast<ConversationParticipant?>()
            .firstWhere((p) => p!.id == lastMsg.senderId, orElse: () => null);
        if (sender != null) {
          text = '${sender.name}: $text';
        }
      }
    }
    return text;
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    if (now.difference(local).inDays < 1) return DateFormat.jm().format(local);
    if (now.difference(local).inDays < 7) return DateFormat.E().format(local);
    return DateFormat.MMMd().format(local);
  }
}
