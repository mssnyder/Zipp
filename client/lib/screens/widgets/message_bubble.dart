import 'dart:convert';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/message.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'reaction_bar.dart';

const _quickEmojis = ['❤️', '😂', '😮', '😢', '👍', '🔥'];

class MessageBubble extends StatefulWidget {
  final ZippMessage message;
  final bool isMine;
  final void Function(String emoji)? onReact;
  final VoidCallback? onReply;
  final VoidCallback? onCopy;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onReact,
    this.onReply,
    this.onCopy,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hovering = false;
  final _bubbleKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  int _highlightedIndex = -1;

  bool get _isDesktop =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showReactionOverlay([Offset? longPressPos]) {
    _removeOverlay();
    HapticFeedback.lightImpact();

    final renderBox = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final bubblePos = renderBox.localToGlobal(Offset.zero);
    final bubbleSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;
    final isMine = widget.isMine;

    // Position the overlay above the bubble, or below if too close to the top
    const overlayHeight = 52.0;
    const overlayPadding = 8.0;
    final showAbove = bubblePos.dy > overlayHeight + overlayPadding + 50;

    final overlayTop = showAbove
        ? bubblePos.dy - overlayHeight - overlayPadding
        : bubblePos.dy + bubbleSize.height + overlayPadding;

    // Align horizontally with the message
    final overlayLeft = isMine
        ? (bubblePos.dx + bubbleSize.width - 280).clamp(8.0, screenSize.width - 288.0)
        : bubblePos.dx.clamp(8.0, screenSize.width - 288.0);

    _overlayEntry = OverlayEntry(
      builder: (context) => _ReactionOverlay(
        top: overlayTop,
        left: overlayLeft,
        highlightedIndex: _highlightedIndex,
        onReact: (emoji) {
          _removeOverlay();
          widget.onReact?.call(emoji);
          HapticFeedback.lightImpact();
        },
        onReply: () {
          _removeOverlay();
          widget.onReply?.call();
        },
        onCopy: widget.message.plaintext != null
            ? () {
                _removeOverlay();
                widget.onCopy?.call();
              }
            : null,
        onDismiss: _removeOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _highlightedIndex = -1;
    _showReactionOverlay(details.globalPosition);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_overlayEntry == null) return;

    final renderBox = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final bubblePos = renderBox.localToGlobal(Offset.zero);
    final bubbleSize = renderBox.size;
    final isMine = widget.isMine;
    final screenSize = MediaQuery.of(context).size;

    const overlayHeight = 52.0;
    const overlayPadding = 8.0;
    final showAbove = bubblePos.dy > overlayHeight + overlayPadding + 50;

    final overlayTop = showAbove
        ? bubblePos.dy - overlayHeight - overlayPadding
        : bubblePos.dy + bubbleSize.height + overlayPadding;

    final overlayLeft = isMine
        ? (bubblePos.dx + bubbleSize.width - 280).clamp(8.0, screenSize.width - 288.0)
        : bubblePos.dx.clamp(8.0, screenSize.width - 288.0);

    // Calculate which emoji the finger is closest to
    final fingerPos = details.globalPosition;
    const emojiSpacing = 44.0;
    const emojiStartX = 8.0;
    final emojiCenterY = overlayTop + overlayHeight / 2;

    int closest = -1;
    double closestDist = double.infinity;

    for (int i = 0; i < _quickEmojis.length; i++) {
      final emojiCenterX = overlayLeft + emojiStartX + (i * emojiSpacing) + emojiSpacing / 2;
      final dx = fingerPos.dx - emojiCenterX;
      final dy = fingerPos.dy - emojiCenterY;
      final dist = dx * dx + dy * dy;
      if (dist < closestDist && dist < 80 * 80) {
        closest = i;
        closestDist = dist;
      }
    }

    if (closest != _highlightedIndex) {
      _highlightedIndex = closest;
      _overlayEntry?.markNeedsBuild();
      if (closest >= 0) HapticFeedback.selectionClick();
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_highlightedIndex >= 0 && _highlightedIndex < _quickEmojis.length) {
      final emoji = _quickEmojis[_highlightedIndex];
      _removeOverlay();
      widget.onReact?.call(emoji);
      HapticFeedback.lightImpact();
    }
    _highlightedIndex = -1;
  }

  Widget _buildHoverButtons() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoverBtn(
            icon: Icons.reply_outlined,
            tooltip: 'Reply',
            onTap: widget.onReply,
          ),
          _HoverBtn(
            icon: Icons.emoji_emotions_outlined,
            tooltip: 'React',
            onTap: () => _showReactionOverlay(),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMine = widget.isMine;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onLongPressStart: _isDesktop ? null : _onLongPressStart,
        onLongPressMoveUpdate: _isDesktop ? null : _onLongPressMoveUpdate,
        onLongPressEnd: _isDesktop ? null : _onLongPressEnd,
        child: Dismissible(
          key: ValueKey('dismiss-${message.id}'),
          direction: isMine ? DismissDirection.endToStart : DismissDirection.startToEnd,
          confirmDismiss: (_) async {
            widget.onReply?.call();
            return false;
          },
          background: Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: isMine ? 0 : 16, right: isMine ? 16 : 0),
              child: Icon(Icons.reply, color: ZippTheme.accent2.withAlpha(180)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(
              mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isDesktop && isMine) ...[
                  IgnorePointer(
                    ignoring: !_hovering,
                    child: AnimatedOpacity(
                      opacity: _hovering ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: _buildHoverButtons(),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  child: Column(
                    key: _bubbleKey,
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
                if (_isDesktop && !isMine) ...[
                  const SizedBox(width: 4),
                  IgnorePointer(
                    ignoring: !_hovering,
                    child: AnimatedOpacity(
                      opacity: _hovering ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: _buildHoverButtons(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Inline reaction overlay ──────────────────────────────────────────────────

class _ReactionOverlay extends StatelessWidget {
  final double top;
  final double left;
  final int highlightedIndex;
  final void Function(String emoji) onReact;
  final VoidCallback onReply;
  final VoidCallback? onCopy;
  final VoidCallback onDismiss;

  const _ReactionOverlay({
    required this.top,
    required this.left,
    required this.highlightedIndex,
    required this.onReact,
    required this.onReply,
    this.onCopy,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Tap outside to dismiss
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: top,
          left: left,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: ZippTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(100),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < _quickEmojis.length; i++)
                    GestureDetector(
                      onTap: () => onReact(_quickEmojis[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: highlightedIndex == i ? 44 : 36,
                        height: highlightedIndex == i ? 44 : 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: highlightedIndex == i
                              ? ZippTheme.accent1.withAlpha(60)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          _quickEmojis[i],
                          style: TextStyle(fontSize: highlightedIndex == i ? 28 : 22),
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  _OverlayAction(icon: Icons.reply_outlined, onTap: onReply),
                  if (onCopy != null)
                    _OverlayAction(icon: Icons.copy_outlined, onTap: onCopy!),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OverlayAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _OverlayAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: ZippTheme.textSecondary),
        ),
      );
}

// ── Hover button for desktop ─────────────────────────────────────────────────

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

// ── Bubble body (content rendering) ──────────────────────────────────────────

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
                  '↩ ${message.replyTo!.plaintext ?? (message.replyTo!.type == MessageType.text ? "Message" : message.replyTo!.type.name)}',
                  style: const TextStyle(fontSize: 12, color: ZippTheme.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CachedNetworkImage(
          imageUrl: api.resolveUrl(url),
          fit: BoxFit.cover,
          placeholder: (_, __) => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
        _buildCaption(data),
      ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
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
        ),
        _buildCaption(data),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
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
        ),
        _buildCaption(data),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

Widget _buildCaption(Map<String, dynamic>? data) {
  final caption = data?['caption'] as String?;
  if (caption == null || caption.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
    child: Text(
      caption,
      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
    ),
  );
}

class _EncryptedPlaceholder extends StatelessWidget {
  const _EncryptedPlaceholder();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(12),
        child: Text('🔒 Encrypted', style: TextStyle(color: Colors.white70)),
      );
}
