import 'dart:convert';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/message.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'reaction_bar.dart';

class MessageBubble extends StatefulWidget {
  final ZippMessage message;
  final bool isMine;
  final VoidCallback? onLongPress;
  final VoidCallback? onSwipeReply;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onLongPress,
    this.onSwipeReply,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hovering = false;

  // Show hover actions on desktop/web; on mobile long-press handles it.
  bool get _isDesktop =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMine = widget.isMine;

    final hoverActions = _hovering && _isDesktop
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HoverBtn(
                icon: Icons.reply_outlined,
                tooltip: 'Reply',
                onTap: widget.onSwipeReply,
              ),
              _HoverBtn(
                icon: Icons.emoji_emotions_outlined,
                tooltip: 'React',
                onTap: widget.onLongPress,
              ),
            ],
          )
        : const SizedBox.shrink();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        child: Dismissible(
          key: ValueKey('dismiss-${message.id}'),
          direction: DismissDirection.startToEnd,
          confirmDismiss: (_) async {
            widget.onSwipeReply?.call();
            return false; // Don't actually dismiss
          },
          background: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Icon(Icons.reply, color: ZippTheme.accent2.withAlpha(180)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(
              mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!isMine) ...[hoverActions, const SizedBox(width: 4)],
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  child: Column(
                    crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      _BubbleBody(message: message, isMine: isMine),
                      if (message.reactions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: ReactionBar(
                            reactions: message.reactions,
                            myUserId: context.read<AuthProvider>().user?.id ?? '',
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat.jm().format(message.createdAt.toLocal()),
                              style: const TextStyle(fontSize: 10, color: ZippTheme.textSecondary),
                            ),
                            if (isMine) ...[
                              const SizedBox(width: 4),
                              Icon(
                                message.isRead ? Icons.done_all : Icons.done,
                                size: 12,
                                color: message.isRead ? ZippTheme.accent2 : ZippTheme.textSecondary,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isMine) ...[const SizedBox(width: 4), hoverActions],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _HoverBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 18, color: ZippTheme.textSecondary),
          ),
        ),
      );
}

class _BubbleBody extends StatelessWidget {
  final ZippMessage message;
  final bool isMine;

  const _BubbleBody({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiService>();

    Widget content;
    switch (message.type) {
      case MessageType.gif:
        content = _GifContent(message: message, api: api);
      case MessageType.image:
        content = _ImageContent(message: message, api: api);
      case MessageType.video:
        content = _VideoContent(message: message, api: api);
      case MessageType.file:
        content = _FileContent(message: message);
      case MessageType.text:
        content = _TextContent(message: message);
    }

    if (isMine) {
      return Container(
        decoration: BoxDecoration(
          gradient: ZippTheme.accentGradient,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          child: content,
        ),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(4),
        topRight: Radius.circular(16),
        bottomLeft: Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(18),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(color: Colors.white.withAlpha(20)),
          ),
          child: content,
        ),
      ),
    );
  }
}

class _TextContent extends StatelessWidget {
  final ZippMessage message;
  const _TextContent({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.replyTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(left: BorderSide(color: ZippTheme.accent2, width: 3)),
                ),
                child: Text(
                  '↩ ${message.replyTo!.type == MessageType.text ? "Message" : message.replyTo!.type.name}',
                  style: const TextStyle(fontSize: 12, color: ZippTheme.textSecondary),
                ),
              ),
            Text(
              message.plaintext ?? '🔒 Encrypted',
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
            ),
          ],
        ),
      );
}

class _GifContent extends StatelessWidget {
  final ZippMessage message;
  final ApiService api;
  const _GifContent({required this.message, required this.api});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(message.plaintext ?? '{}') as Map<String, dynamic>?;
    } catch (_) {}
    final url = data?['gifUrl'] as String? ?? data?['tinyUrl'] as String?;
    if (url == null) return const _EncryptedPlaceholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
    );
  }
}

class _ImageContent extends StatelessWidget {
  final ZippMessage message;
  final ApiService api;
  const _ImageContent({required this.message, required this.api});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(message.plaintext ?? '{}') as Map<String, dynamic>?;
    } catch (_) {}
    final url = data?['url'] as String?;
    if (url == null) return const _EncryptedPlaceholder();
    return CachedNetworkImage(
      imageUrl: api.resolveUrl(url),
      fit: BoxFit.cover,
      placeholder: (_, __) => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

class _VideoContent extends StatelessWidget {
  final ZippMessage message;
  final ApiService api;
  const _VideoContent({required this.message, required this.api});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(message.plaintext ?? '{}') as Map<String, dynamic>?;
    } catch (_) {}
    final thumbUrl = data?['thumbUrl'] as String?;
    final duration = data?['duration'] as int?;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (thumbUrl != null)
          CachedNetworkImage(
            imageUrl: api.resolveUrl(thumbUrl),
            fit: BoxFit.cover,
            width: double.infinity,
            height: 200,
          )
        else
          Container(height: 200, color: ZippTheme.surfaceVariant),
        const Icon(Icons.play_circle_outline, size: 56, color: Colors.white),
        if (duration != null)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDuration(duration),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _FileContent extends StatelessWidget {
  final ZippMessage message;
  const _FileContent({required this.message});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(message.plaintext ?? '{}') as Map<String, dynamic>?;
    } catch (_) {}

    final size = data?['sizeBytes'] as int? ?? 0;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_file, color: Colors.white70, size: 28),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data?['filename'] as String? ?? 'File',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatSize(size),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _EncryptedPlaceholder extends StatelessWidget {
  const _EncryptedPlaceholder();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(12),
        child: Text('🔒 Encrypted', style: TextStyle(color: Colors.white70)),
      );
}
