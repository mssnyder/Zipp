import 'dart:async';
import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import 'widgets/attachment_preview.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_input.dart';
import 'widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String participantId;
  final String participantName;
  final bool embedded;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.participantId,
    required this.participantName,
    this.embedded = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollCtrl = ScrollController();
  final _inputKey = GlobalKey();
  ZippMessage? _replyingTo;
  bool _loadingMore = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final chat = context.read<ChatProvider>();
      await chat.loadMessages(widget.conversationId);
      _markRead();
    });

    _scrollCtrl.addListener(_onScroll);
  }

  /// Mark latest incoming message as read.
  void _markRead() {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final myId = auth.user?.id ?? '';
    if (myId.isEmpty) return;
    chat.markLastMessageRead(widget.conversationId, myId);
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
    if (mounted) setState(() => _replyingTo = null);
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

  Future<void> _sendAttachment(Uint8List bytes, String filename, String type, String? caption) async {
    final api = context.read<ApiService>();
    final chat = context.read<ChatProvider>();
    try {
      final attachment = await api.uploadAttachment(bytes, filename);
      await chat.sendAttachmentMessage(
        conversationId: widget.conversationId,
        attachment: attachment,
        recipientId: widget.participantId,
        type: type,
        caption: caption,
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

  Future<void> _handleDrop(DropDoneDetails details) async {
    for (final xFile in details.files) {
      final name = xFile.name;
      final ext = name.split('.').last.toLowerCase();
      final type = const {
        'jpg': 'IMAGE', 'jpeg': 'IMAGE', 'png': 'IMAGE', 'gif': 'IMAGE', 'webp': 'IMAGE',
        'mp4': 'VIDEO', 'mov': 'VIDEO', 'avi': 'VIDEO', 'mkv': 'VIDEO',
      }[ext] ?? 'FILE';
      final bytes = await xFile.readAsBytes();
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: ZippTheme.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => AttachmentPreview(
          bytes: bytes,
          filename: name,
          type: type,
          onSend: _sendAttachment,
        ),
      );
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

  void _onReply(ZippMessage msg) {
    setState(() => _replyingTo = msg);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      (_inputKey.currentState as dynamic)?.requestFocus();
    });
  }
  void _cancelReply() => setState(() => _replyingTo = null);

  int _lastMsgCount = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chat = context.watch<ChatProvider>();
    final messages = chat.messagesFor(widget.conversationId);
    final typing = chat.typingIn(widget.conversationId);
    final myId = auth.user?.id ?? '';

    // Mark as read when new messages arrive from the other person
    if (messages.length > _lastMsgCount && messages.isNotEmpty) {
      _lastMsgCount = messages.length;
      final lastMsg = messages.last;
      if (lastMsg.senderId != myId) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
      }
    }

    return Scaffold(
      backgroundColor: ZippTheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
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
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (details) {
          setState(() => _isDragging = false);
          _handleDrop(details);
        },
        child: Stack(
          children: [
            Column(
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
                              onReact: (emoji) => chat.toggleReaction(msg.id, widget.conversationId, emoji),
                              onReply: () => _onReply(msg),
                              onCopy: msg.plaintext != null
                                  ? () => Clipboard.setData(ClipboardData(text: msg.plaintext!))
                                  : null,
                            ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0);
                          },
                        ),
                ),
                if (typing.isNotEmpty) const TypingIndicator(),
                MessageInput(
                  key: _inputKey,
                  replyingTo: _replyingTo,
                  onCancelReply: _cancelReply,
                  onSend: _sendText,
                  onSendGif: _sendGif,
                  onSendAttachment: _sendAttachment,
                  conversationId: widget.conversationId,
                ),
              ],
            ),
            if (_isDragging)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: ZippTheme.accent1.withAlpha(30),
                    border: Border.all(color: ZippTheme.accent1, width: 2),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.upload_file, size: 56, color: ZippTheme.accent1),
                        SizedBox(height: 12),
                        Text(
                          'Drop files to send',
                          style: TextStyle(
                            color: ZippTheme.accent1,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

