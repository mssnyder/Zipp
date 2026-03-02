import 'dart:convert';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:intl/intl.dart';
import 'package:pasteboard/pasteboard.dart';
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
  final void Function(ZippMessage)? onEdit;
  final void Function(ZippMessage)? onDelete;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onReact,
    this.onReply,
    this.onEdit,
    this.onDelete,
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

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ── Copy ──────────────────────────────────────────────────────────────────

  Future<void> _copyMessage() async {
    final msg = widget.message;
    if (msg.plaintext == null) return;

    switch (msg.type) {
      case MessageType.text:
        final text = msg.plaintext;
        if (text != null && text.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: text));
          _showCopied();
        }
      case MessageType.gif:
        try {
          final data = jsonDecode(msg.plaintext!) as Map<String, dynamic>;
          final url = data['gifUrl'] as String? ?? data['tinyUrl'] as String?;
          if (url != null) await _copyImageFromCache(url);
        } catch (_) {}
      case MessageType.image:
        try {
          final data = jsonDecode(msg.plaintext!) as Map<String, dynamic>;
          final api = context.read<ApiService>();
          final url = api.resolveUrl(data['url'] as String? ?? '');
          await _copyImageFromCache(url);
        } catch (_) {}
      case MessageType.video:
        try {
          final data = jsonDecode(msg.plaintext!) as Map<String, dynamic>;
          final caption = data['caption'] as String? ?? data['filename'] as String?;
          if (caption != null && caption.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: caption));
            _showCopied();
          }
        } catch (_) {}
      case MessageType.file:
        try {
          final data = jsonDecode(msg.plaintext!) as Map<String, dynamic>;
          final text = data['caption'] as String? ?? data['filename'] as String?;
          if (text != null && text.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: text));
            _showCopied();
          }
        } catch (_) {}
    }
  }

  Future<void> _copyImageFromCache(String url) async {
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      final bytes = await file.readAsBytes();
      await Pasteboard.writeImage(bytes);
      if (mounted) _showCopied();
    } catch (_) {
      // Fallback: copy URL as text
      Clipboard.setData(ClipboardData(text: url));
      if (mounted) _showCopied();
    }
  }

  void _showCopied() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }

  // ── Delete confirmation ────────────────────────────────────────────────────

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZippTheme.surfaceVariant,
        title: const Text('Delete message?'),
        content: const Text('This will delete the message for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDelete?.call(widget.message);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── Reaction overlay (mobile) ──────────────────────────────────────────────

  void _showReactionOverlay([Offset? longPressPos]) {
    _removeOverlay();
    HapticFeedback.lightImpact();

    final renderBox = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final bubblePos = renderBox.localToGlobal(Offset.zero);
    final bubbleSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;
    final isMine = widget.isMine;

    // Calculate overlay height based on content
    const emojiRowHeight = 52.0;
    const actionItemHeight = 44.0;
    int actionCount = 2; // Reply + Copy
    if (isMine && widget.message.type == MessageType.text) actionCount++;
    if (isMine) actionCount++;
    final totalHeight = emojiRowHeight + 1 + (actionCount * actionItemHeight) + 8;

    const overlayPadding = 8.0;
    final showAbove = bubblePos.dy > totalHeight + overlayPadding + 50;

    final overlayTop = showAbove
        ? bubblePos.dy - totalHeight - overlayPadding
        : bubblePos.dy + bubbleSize.height + overlayPadding;

    final overlayLeft = isMine
        ? (bubblePos.dx + bubbleSize.width - 280).clamp(8.0, screenSize.width - 288.0)
        : bubblePos.dx.clamp(8.0, screenSize.width - 288.0);

    _overlayEntry = OverlayEntry(
      builder: (context) => _MobileOverlay(
        top: overlayTop,
        left: overlayLeft,
        highlightedIndex: _highlightedIndex,
        isMine: isMine,
        messageType: widget.message.type,
        onReact: (emoji) {
          _removeOverlay();
          widget.onReact?.call(emoji);
          HapticFeedback.lightImpact();
        },
        onReply: () {
          _removeOverlay();
          widget.onReply?.call();
        },
        onCopy: () {
          _removeOverlay();
          _copyMessage();
        },
        onEdit: isMine && widget.message.type == MessageType.text
            ? () {
                _removeOverlay();
                widget.onEdit?.call(widget.message);
              }
            : null,
        onDelete: isMine
            ? () {
                _removeOverlay();
                _confirmDelete();
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

  // ── Desktop hover buttons ──────────────────────────────────────────────────

  void _handleMenuAction(String action) {
    switch (action) {
      case 'copy':
        _copyMessage();
      case 'edit':
        widget.onEdit?.call(widget.message);
      case 'delete':
        _confirmDelete();
    }
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
            onTap: () => _showDesktopReactionOverlay(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: ZippTheme.textSecondary),
            color: ZippTheme.surfaceVariant,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            onSelected: _handleMenuAction,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy', child: _MenuRow(icon: Icons.copy_outlined, label: 'Copy')),
              if (widget.isMine && widget.message.type == MessageType.text)
                const PopupMenuItem(value: 'edit', child: _MenuRow(icon: Icons.edit_outlined, label: 'Edit')),
              if (widget.isMine)
                const PopupMenuItem(value: 'delete', child: _MenuRow(icon: Icons.delete_outlined, label: 'Delete', danger: true)),
            ],
          ),
        ],
      );

  /// Desktop: show emoji-only reaction overlay (no action items).
  void _showDesktopReactionOverlay() {
    _removeOverlay();

    final renderBox = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final bubblePos = renderBox.localToGlobal(Offset.zero);
    final bubbleSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;
    final isMine = widget.isMine;

    const overlayHeight = 52.0;
    const overlayPadding = 8.0;
    final showAbove = bubblePos.dy > overlayHeight + overlayPadding + 50;

    final overlayTop = showAbove
        ? bubblePos.dy - overlayHeight - overlayPadding
        : bubblePos.dy + bubbleSize.height + overlayPadding;

    final overlayLeft = isMine
        ? (bubblePos.dx + bubbleSize.width - 280).clamp(8.0, screenSize.width - 288.0)
        : bubblePos.dx.clamp(8.0, screenSize.width - 288.0);

    _overlayEntry = OverlayEntry(
      builder: (context) => _DesktopReactionOverlay(
        top: overlayTop,
        left: overlayLeft,
        onReact: (emoji) {
          _removeOverlay();
          widget.onReact?.call(emoji);
        },
        onDismiss: _removeOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMine = widget.isMine;

    final isDeleted = message.isDeleted;

    return MouseRegion(
      onEnter: isDeleted ? null : (_) => setState(() => _hovering = true),
      onExit: isDeleted ? null : (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onLongPressStart: _isDesktop || isDeleted ? null : _onLongPressStart,
        onLongPressMoveUpdate: _isDesktop || isDeleted ? null : _onLongPressMoveUpdate,
        onLongPressEnd: _isDesktop || isDeleted ? null : _onLongPressEnd,
        child: _wrapWithSwipe(
          isMine: isMine,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(
              mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isDesktop && isMine && !isDeleted) ...[
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
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
                    child: Column(
                    key: _bubbleKey,
                    crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      _BubbleBody(message: message, isMine: isMine, isDesktop: _isDesktop),
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
                            if (message.isEdited) ...[
                              const SizedBox(width: 4),
                              Text(
                                'edited ${DateFormat.jm().format(message.editedAt!.toLocal())}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: ZippTheme.textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
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
                ),
                if (_isDesktop && !isMine && !isDeleted) ...[
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

  /// Wrap with swipe-to-reply Dismissible (Android only).
  Widget _wrapWithSwipe({required bool isMine, required Widget child}) {
    if (!_isAndroid) return child;
    return Dismissible(
      key: ValueKey('dismiss-${widget.message.id}'),
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
      child: child,
    );
  }
}

// ── Desktop: emoji-only reaction overlay ─────────────────────────────────────

class _DesktopReactionOverlay extends StatelessWidget {
  final double top;
  final double left;
  final void Function(String emoji) onReact;
  final VoidCallback onDismiss;

  const _DesktopReactionOverlay({
    required this.top,
    required this.left,
    required this.onReact,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
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
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        child: Text(_quickEmojis[i], style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Mobile: combined reaction + action overlay (Messenger-style) ─────────────

class _MobileOverlay extends StatelessWidget {
  final double top;
  final double left;
  final int highlightedIndex;
  final bool isMine;
  final MessageType messageType;
  final void Function(String emoji) onReact;
  final VoidCallback onReply;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onDismiss;

  const _MobileOverlay({
    required this.top,
    required this.left,
    required this.highlightedIndex,
    required this.isMine,
    required this.messageType,
    required this.onReact,
    required this.onReply,
    required this.onCopy,
    this.onEdit,
    this.onDelete,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
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
              width: 276,
              decoration: BoxDecoration(
                color: ZippTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(100),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Emoji row
                  Padding(
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
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Colors.white.withAlpha(20)),
                  // Action items
                  _ActionItem(icon: Icons.reply_outlined, label: 'Reply', onTap: onReply),
                  _ActionItem(icon: Icons.copy_outlined, label: 'Copy', onTap: onCopy),
                  if (onEdit != null)
                    _ActionItem(icon: Icons.edit_outlined, label: 'Edit', onTap: onEdit!),
                  if (onDelete != null)
                    _ActionItem(icon: Icons.delete_outlined, label: 'Delete', onTap: onDelete!, danger: true),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red[300]! : ZippTheme.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: color, fontSize: 15)),
          ],
        ),
      ),
    );
  }
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

// ── Desktop popup menu row ───────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;

  const _MenuRow({required this.icon, required this.label, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red[300]! : ZippTheme.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

// ── Bubble body (content rendering) ──────────────────────────────────────────

class _BubbleBody extends StatelessWidget {
  final ZippMessage message;
  final bool isMine;
  final bool isDesktop;

  const _BubbleBody({required this.message, required this.isMine, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiService>();

    // Soft-deleted message placeholder
    if (message.isDeleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ZippTheme.surfaceVariant.withAlpha(120),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZippTheme.border.withAlpha(60)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 14, color: ZippTheme.textSecondary),
            SizedBox(width: 6),
            Text(
              'This message was deleted',
              style: TextStyle(
                color: ZippTheme.textSecondary,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

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
        content = _TextContent(message: message, isDesktop: isDesktop);
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
  final bool isDesktop;
  const _TextContent({required this.message, required this.isDesktop});

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
            if (isDesktop)
              SelectableText(
                message.plaintext ?? '🔒 Encrypted',
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
              )
            else
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
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
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
    final mime = data?['mimeType'] as String? ?? '';
    final isGif = mime.contains('gif');
    final resolvedUrl = api.resolveUrl(url);
    final headers = api.imageHeaders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isGif)
          // Use Image.network for animated GIFs to preserve animation
          Image.network(
            resolvedUrl,
            headers: headers.isNotEmpty ? headers : null,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
          )
        else
          CachedNetworkImage(
            imageUrl: resolvedUrl,
            httpHeaders: headers.isNotEmpty ? headers : null,
            fit: BoxFit.cover,
            placeholder: (_, _) => const SizedBox(
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
    final headers = api.imageHeaders;

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
                httpHeaders: headers.isNotEmpty ? headers : null,
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
