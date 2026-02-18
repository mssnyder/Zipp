import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_input.dart';
import 'widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String participantId;
  final String participantName;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.participantId,
    required this.participantName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollCtrl = ScrollController();
  ZippMessage? _replyingTo;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadMessages(widget.conversationId);
    });

    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    // Scroll-up to load older messages
    if (_scrollCtrl.position.pixels <= 120 && !_loadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final chat = context.read<ChatProvider>();
    if (!chat.hasMoreFor(widget.conversationId)) return;
    setState(() => _loadingMore = true);
    await chat.loadMoreMessages(widget.conversationId);
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendText(String text) async {
    final chat = context.read<ChatProvider>();
    await chat.sendTextMessage(
      conversationId: widget.conversationId,
      text: text,
      recipientId: widget.participantId,
      replyToId: _replyingTo?.id,
    );
    setState(() => _replyingTo = null);
    _scrollToBottom();
  }

  Future<void> _sendGif(Map<String, dynamic> gif) async {
    final chat = context.read<ChatProvider>();
    await chat.sendGifMessage(
      conversationId: widget.conversationId,
      gifResult: gif,
      recipientId: widget.participantId,
    );
    _scrollToBottom();
  }

  Future<void> _sendAttachment(File file, String type) async {
    final api = context.read<ApiService>();
    final chat = context.read<ChatProvider>();
    try {
      final attachment = await api.uploadAttachment(file);
      await chat.sendAttachmentMessage(
        conversationId: widget.conversationId,
        attachment: attachment,
        recipientId: widget.participantId,
        type: type,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onReply(ZippMessage msg) => setState(() => _replyingTo = msg);
  void _cancelReply() => setState(() => _replyingTo = null);

  void _onLongPress(BuildContext context, ZippMessage msg) {
    final chat = context.read<ChatProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: ZippTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReactionPicker(
        onReact: (emoji) {
          Navigator.pop(context);
          chat.toggleReaction(msg.id, widget.conversationId, emoji);
          HapticFeedback.lightImpact();
        },
        onReply: () {
          Navigator.pop(context);
          _onReply(msg);
        },
        onCopy: msg.plaintext != null
            ? () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: msg.plaintext!));
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chat = context.watch<ChatProvider>();
    final messages = chat.messagesFor(widget.conversationId);
    final typing = chat.typingIn(widget.conversationId);
    final myId = auth.user?.id ?? '';

    return Scaffold(
      backgroundColor: ZippTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: ZippTheme.surfaceVariant,
                  child: Text(
                    widget.participantName.isNotEmpty ? widget.participantName[0].toUpperCase() : '?',
                    style: const TextStyle(color: ZippTheme.accent1, fontWeight: FontWeight.w700),
                  ),
                ),
                if (chat.isOnline(widget.participantId))
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: ZippTheme.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: ZippTheme.background, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.participantName, style: const TextStyle(fontSize: 16)),
                if (chat.isOnline(widget.participantId))
                  const Text('Online',
                      style: TextStyle(fontSize: 11, color: ZippTheme.online)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: chat.msgLoadingFor(widget.conversationId) && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: messages.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (_loadingMore && i == 0) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      final idx = _loadingMore ? i - 1 : i;
                      final msg = messages[idx];
                      final isMine = msg.senderId == myId;
                      return MessageBubble(
                        message: msg,
                        isMine: isMine,
                        onLongPress: () => _onLongPress(context, msg),
                        onSwipeReply: () => _onReply(msg),
                      ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0);
                    },
                  ),
          ),
          if (typing.isNotEmpty) const TypingIndicator(),
          MessageInput(
            replyingTo: _replyingTo,
            onCancelReply: _cancelReply,
            onSend: _sendText,
            onSendGif: _sendGif,
            onSendAttachment: _sendAttachment,
            conversationId: widget.conversationId,
          ),
        ],
      ),
    );
  }
}

class _ReactionPicker extends StatelessWidget {
  final void Function(String emoji) onReact;
  final VoidCallback onReply;
  final VoidCallback? onCopy;

  const _ReactionPicker({required this.onReact, required this.onReply, this.onCopy});

  static const _quickEmojis = ['❤️', '😂', '😮', '😢', '👍', '🔥'];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _quickEmojis
                  .map((e) => GestureDetector(
                        onTap: () => onReact(e),
                        child: Text(e, style: const TextStyle(fontSize: 32))
                            .animate()
                            .scale(delay: (_quickEmojis.indexOf(e) * 30).ms),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _ActionBtn(icon: Icons.reply_outlined, label: 'Reply', onTap: onReply),
                if (onCopy != null)
                  _ActionBtn(icon: Icons.copy_outlined, label: 'Copy', onTap: onCopy!),
              ],
            ),
          ],
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon, color: ZippTheme.textSecondary),
          label: Text(label, style: const TextStyle(color: ZippTheme.textSecondary)),
        ),
      );
}
