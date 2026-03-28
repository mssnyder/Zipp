import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'widgets/attachment_preview.dart';
import 'widgets/group_avatar.dart';
import 'widgets/group_settings_sheet.dart';
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
    this.participantId = '',
    this.participantName = '',
    this.embedded = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollCtrl = ScrollController();
  final _inputKey = GlobalKey();
  ZippMessage? _replyingTo;
  ZippMessage? _editingMessage;
  bool _loadingMore = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    // Track active conversation for notification suppression
    NotificationService.instance.activeConversationId = widget.conversationId;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final chat = context.read<ChatProvider>();
      await chat.loadMessages(widget.conversationId);
      _markRead();
      // Auto-focus the message input when the chat opens
      (_inputKey.currentState as dynamic)?.requestFocus();
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
    // In a reversed ListView, maxScrollExtent = top (oldest messages).
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 120 &&
        !_loadingMore) {
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
    // Clear active conversation unless embedded (desktop two-pane manages its own)
    if (!widget.embedded) {
      NotificationService.instance.activeConversationId = null;
    }
    _scrollCtrl.dispose();
    super.dispose();
  }

  Conversation? get _conv => context.read<ChatProvider>().conversationById(widget.conversationId);
  bool get _isGroup => _conv?.isGroup ?? false;

  Future<void> _sendText(String text) async {
    final chat = context.read<ChatProvider>();
    if (_isGroup) {
      await chat.sendGroupTextMessage(
        conversationId: widget.conversationId,
        text: text,
        replyToId: _replyingTo?.id,
      );
    } else {
      await chat.sendTextMessage(
        conversationId: widget.conversationId,
        text: text,
        recipientId: widget.participantId,
        replyToId: _replyingTo?.id,
      );
    }
    if (mounted) setState(() => _replyingTo = null);
    _scrollToBottom();
  }

  Future<void> _sendGif(Map<String, dynamic> gif) async {
    final chat = context.read<ChatProvider>();
    if (_isGroup) {
      await chat.sendGroupGifMessage(
        conversationId: widget.conversationId,
        gifResult: gif,
      );
    } else {
      await chat.sendGifMessage(
        conversationId: widget.conversationId,
        gifResult: gif,
        recipientId: widget.participantId,
      );
    }
    _scrollToBottom();
  }

  Future<void> _sendAttachment(Uint8List bytes, String filename, String type, String? caption) async {
    final api = context.read<ApiService>();
    final chat = context.read<ChatProvider>();
    try {
      final attachment = await api.uploadAttachment(bytes, filename);
      if (_isGroup) {
        await chat.sendGroupAttachmentMessage(
          conversationId: widget.conversationId,
          attachment: attachment,
          type: type,
          caption: caption,
        );
      } else {
        await chat.sendAttachmentMessage(
          conversationId: widget.conversationId,
          attachment: attachment,
          recipientId: widget.participantId,
          type: type,
          caption: caption,
        );
      }
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
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onReply(ZippMessage msg) {
    setState(() {
      _replyingTo = msg;
      _editingMessage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      (_inputKey.currentState as dynamic)?.requestFocus();
    });
  }
  void _cancelReply() => setState(() => _replyingTo = null);

  void _onEdit(ZippMessage msg) {
    setState(() {
      _editingMessage = msg;
      _replyingTo = null;
    });
  }
  void _cancelEdit() => setState(() => _editingMessage = null);

  Future<void> _onEditSend(String messageId, String newText) async {
    try {
      final chat = context.read<ChatProvider>();
      await chat.editMessage(
        conversationId: widget.conversationId,
        messageId: messageId,
        newText: newText,
        recipientId: _isGroup ? '' : widget.participantId,
      );
      if (mounted) setState(() => _editingMessage = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Edit failed: $e')),
        );
      }
    }
  }

  Future<void> _onDelete(ZippMessage msg) async {
    try {
      final chat = context.read<ChatProvider>();
      await chat.deleteMessage(
        conversationId: widget.conversationId,
        messageId: msg.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  void _showGroupSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZippTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GroupSettingsSheet(conversationId: widget.conversationId),
    );
  }

  bool get _isMobile {
    if (widget.embedded) return false;
    if (!kIsWeb) {
      return defaultTargetPlatform == TargetPlatform.iOS ||
             defaultTargetPlatform == TargetPlatform.android;
    }
    return MediaQuery.sizeOf(context).width < 720;
  }

  int _lastMsgCount = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chat = context.watch<ChatProvider>();
    final api = context.read<ApiService>();
    final messages = chat.messagesFor(widget.conversationId);
    final typing = chat.typingIn(widget.conversationId);
    final myId = auth.user?.id ?? '';
    final conv = chat.conversationById(widget.conversationId);
    final isGroup = conv?.isGroup ?? false;
    final convName = conv?.displayName ?? widget.participantName;

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
            if (isGroup)
              GroupAvatar(
                participants: conv!.participants,
                currentUserId: myId,
                size: 36,
                api: api,
              )
            else
              Stack(
                children: [
                  Builder(builder: (context) {
                    final avatarUrl = conv?.participant?.avatarUrl;
                    return CircleAvatar(
                      radius: 18,
                      backgroundColor: ZippTheme.surfaceVariant,
                      backgroundImage: avatarUrl != null ? NetworkImage(api.resolveUrl(avatarUrl)) : null,
                      child: avatarUrl == null
                          ? Text(
                              convName.isNotEmpty ? convName[0].toUpperCase() : '?',
                              style: const TextStyle(color: ZippTheme.accent1, fontWeight: FontWeight.w700),
                            )
                          : null,
                    );
                  }),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(convName, style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis),
                  if (isGroup)
                    Text('${conv!.participants.length} members',
                        style: const TextStyle(fontSize: 11, color: ZippTheme.textSecondary))
                  else if (chat.isOnline(widget.participantId))
                    const Text('Online',
                        style: TextStyle(fontSize: 11, color: ZippTheme.online)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (isGroup)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => _showGroupSettings(context),
            ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: !_isMobile ? null : (_) {},
        onHorizontalDragEnd: !_isMobile ? null : (d) {
          if ((d.primaryVelocity ?? 0) > 300 && context.mounted) {
            context.go('/');
          }
        },
        onHorizontalDragCancel: !_isMobile ? null : () {},
        child: DropTarget(
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
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: messages.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            // Reversed: index 0 = bottom (newest), last index = top (oldest/spinner).
                            if (_loadingMore && i == messages.length) {
                              return const Padding(
                                padding: EdgeInsets.all(8),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            final msg = messages[messages.length - 1 - i];
                            final isMine = msg.senderId == myId;

                            // In groups, show sender name when sender changes
                            Widget? senderLabel;
                            if (isGroup && !isMine) {
                              final nextIdx = messages.length - 1 - i + 1;
                              final prevMsg = nextIdx < messages.length ? messages[nextIdx] : null;
                              if (prevMsg == null || prevMsg.senderId != msg.senderId) {
                                final sender = conv?.participants
                                    .cast<ConversationParticipant?>()
                                    .firstWhere((p) => p!.id == msg.senderId, orElse: () => null);
                                senderLabel = Padding(
                                  padding: const EdgeInsets.only(left: 16, top: 8, bottom: 2),
                                  child: Text(
                                    sender?.name ?? 'Unknown',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ZippTheme.textSecondary),
                                  ),
                                );
                              }
                            }

                            final bubble = MessageBubble(
                              message: msg,
                              isMine: isMine,
                              onReact: (emoji) => chat.toggleReaction(msg.id, widget.conversationId, emoji),
                              onReply: () => _onReply(msg),
                              onEdit: (m) => _onEdit(m),
                              onDelete: (m) => _onDelete(m),
                            ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0);

                            if (senderLabel != null) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [senderLabel, bubble],
                              );
                            }
                            return bubble;
                          },
                        ),
                ),
                if (typing.isNotEmpty) const TypingIndicator(),
                MessageInput(
                  key: _inputKey,
                  replyingTo: _replyingTo,
                  onCancelReply: _cancelReply,
                  editingMessage: _editingMessage,
                  onCancelEdit: _cancelEdit,
                  onSend: _sendText,
                  onEditSend: _onEditSend,
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
      ),
    );
  }
}

