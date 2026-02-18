import 'dart:async';
import 'dart:io';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/message.dart';
import '../../services/websocket_service.dart';
import 'gif_picker.dart';

class MessageInput extends StatefulWidget {
  final ZippMessage? replyingTo;
  final VoidCallback? onCancelReply;
  final Future<void> Function(String text) onSend;
  final Future<void> Function(Map<String, dynamic> gif) onSendGif;
  final Future<void> Function(File file, String type) onSendAttachment;
  final String conversationId;

  const MessageInput({
    super.key,
    this.replyingTo,
    this.onCancelReply,
    required this.onSend,
    required this.onSendGif,
    required this.onSendAttachment,
    required this.conversationId,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _showEmoji = false;
  bool _sending = false;
  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _onTextChanged(String v) {
    if (!_isTyping && v.isNotEmpty) {
      _isTyping = true;
      context.read<WebSocketService>().sendTyping(widget.conversationId, isTyping: true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        context.read<WebSocketService>().sendTyping(widget.conversationId, isTyping: false);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    _isTyping = false;
    context.read<WebSocketService>().sendTyping(widget.conversationId, isTyping: false);
    try {
      await widget.onSend(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toggleEmoji() {
    setState(() => _showEmoji = !_showEmoji);
    if (_showEmoji) _focusNode.unfocus();
    else _focusNode.requestFocus();
  }

  void _showGifPicker() async {
    final gif = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZippTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const GifPicker(),
    );
    if (gif != null) await widget.onSendGif(gif);
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ZippTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AttachmentSheet(),
    );
    if (choice == null) return;

    if (choice == 'image') {
      final picker = ImagePicker();
      final xf = await picker.pickImage(source: ImageSource.gallery);
      if (xf != null) await widget.onSendAttachment(File(xf.path), 'IMAGE');
    } else if (choice == 'video') {
      final picker = ImagePicker();
      final xf = await picker.pickVideo(source: ImageSource.gallery);
      if (xf != null) await widget.onSendAttachment(File(xf.path), 'VIDEO');
    } else if (choice == 'file') {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        await widget.onSendAttachment(File(result.files.single.path!), 'FILE');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: ZippTheme.surfaceVariant,
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 16, color: ZippTheme.accent2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reply to message',
                      style: const TextStyle(color: ZippTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onCancelReply,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: ZippTheme.surface,
              border: const Border(top: BorderSide(color: ZippTheme.border)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
                    color: ZippTheme.textSecondary,
                  ),
                  onPressed: _toggleEmoji,
                ),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focusNode,
                    onChanged: _onTextChanged,
                    onSubmitted: (_) => _send(),
                    maxLines: null,
                    style: const TextStyle(color: ZippTheme.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Message…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      fillColor: Colors.transparent,
                      filled: true,
                    ),
                    onTap: () {
                      if (_showEmoji) setState(() => _showEmoji = false);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.gif_box_outlined, color: ZippTheme.textSecondary),
                  onPressed: _showGifPicker,
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file_outlined, color: ZippTheme.textSecondary),
                  onPressed: _pickAttachment,
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _sending
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: ZippTheme.accentGradient,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            onPressed: _send,
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (_showEmoji)
            SizedBox(
              height: 280,
              child: EmojiPicker(
                onEmojiSelected: (_, emoji) {
                  _ctrl.text += emoji.emoji;
                  _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
                },
                config: const Config(
                  height: 280,
                  checkPlatformCompatibility: true,
                  emojiViewConfig: EmojiViewConfig(emojiSizeMax: 28),
                  skinToneConfig: SkinToneConfig(),
                  categoryViewConfig: CategoryViewConfig(
                    backgroundColor: ZippTheme.surface,
                    indicatorColor: ZippTheme.accent1,
                  ),
                  bottomActionBarConfig: BottomActionBarConfig(
                    backgroundColor: ZippTheme.surface,
                    buttonColor: ZippTheme.accent1,
                    buttonIconColor: Colors.white,
                  ),
                  searchViewConfig: SearchViewConfig(
                    backgroundColor: ZippTheme.surface,
                    buttonIconColor: ZippTheme.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AttachmentSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Item(icon: Icons.image_outlined, label: 'Photo', value: 'image'),
            _Item(icon: Icons.videocam_outlined, label: 'Video', value: 'video'),
            _Item(icon: Icons.insert_drive_file_outlined, label: 'File', value: 'file'),
          ],
        ),
      );
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Item({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: ZippTheme.accent1),
        title: Text(label),
        onTap: () => Navigator.of(context).pop(value),
      );
}
