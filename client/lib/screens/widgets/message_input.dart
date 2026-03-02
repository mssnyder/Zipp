import 'dart:async';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/message.dart';
import '../../services/websocket_service.dart';
import 'attachment_preview.dart';
import 'gif_picker.dart';

class MessageInput extends StatefulWidget {
  final ZippMessage? replyingTo;
  final VoidCallback? onCancelReply;
  final ZippMessage? editingMessage;
  final VoidCallback? onCancelEdit;
  final Future<void> Function(String text) onSend;
  final Future<void> Function(String messageId, String newText)? onEditSend;
  final Future<void> Function(Map<String, dynamic> gif) onSendGif;
  final Future<void> Function(Uint8List bytes, String filename, String type, String? caption) onSendAttachment;
  final String conversationId;

  const MessageInput({
    super.key,
    this.replyingTo,
    this.onCancelReply,
    this.editingMessage,
    this.onCancelEdit,
    required this.onSend,
    this.onEditSend,
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

  bool get _isDesktopOrWeb =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (_isDesktopOrWeb) {
      _focusNode.onKeyEvent = (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          _send();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
    }
  }

  @override
  void didUpdateWidget(covariant MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When editingMessage changes, pre-fill the text field
    if (widget.editingMessage != null && widget.editingMessage != oldWidget.editingMessage) {
      _ctrl.text = widget.editingMessage!.plaintext ?? '';
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
      _focusNode.requestFocus();
    } else if (widget.editingMessage == null && oldWidget.editingMessage != null) {
      _ctrl.clear();
    }
  }

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
      if (widget.editingMessage != null && widget.onEditSend != null) {
        await widget.onEditSend!(widget.editingMessage!.id, text);
      } else {
        await widget.onSend(text);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toggleEmoji() {
    setState(() => _showEmoji = !_showEmoji);
    if (_showEmoji) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  Future<void> _showGifPicker() async {
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

    Uint8List? bytes;
    String filename;
    String type;
    if (choice == 'image') {
      final picker = ImagePicker();
      final xf = await picker.pickImage(source: ImageSource.gallery);
      if (!mounted || xf == null) return;
      bytes = await xf.readAsBytes();
      filename = xf.name;
      type = 'IMAGE';
    } else if (choice == 'video') {
      final picker = ImagePicker();
      final xf = await picker.pickVideo(source: ImageSource.gallery);
      if (!mounted || xf == null) return;
      bytes = await xf.readAsBytes();
      filename = xf.name;
      type = 'VIDEO';
    } else if (choice == 'file') {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (!mounted || result == null) return;
      final pf = result.files.single;
      if (pf.bytes == null) return;
      bytes = pf.bytes!;
      filename = pf.name;
      type = 'FILE';
    } else {
      return;
    }

    if (!mounted) return;
    _showAttachmentPreview(bytes, filename, type);
  }

  void _showAttachmentPreview(Uint8List bytes, String filename, String type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZippTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AttachmentPreview(
        bytes: bytes,
        filename: filename,
        type: type,
        onSend: widget.onSendAttachment,
      ),
    );
  }

  /// Show attachment preview for an externally provided file (e.g. drag-and-drop).
  void showPreviewForFile(Uint8List bytes, String filename, String type) {
    _showAttachmentPreview(bytes, filename, type);
  }

  /// Focus the text input field (e.g. after starting a reply).
  void requestFocus() {
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.editingMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: ZippTheme.surfaceVariant,
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 16, color: ZippTheme.accent2),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Editing message',
                      style: TextStyle(color: ZippTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onCancelEdit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            )
          else if (widget.replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: ZippTheme.surfaceVariant,
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 16, color: ZippTheme.accent2),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Reply to message',
                      style: TextStyle(color: ZippTheme.textSecondary, fontSize: 13),
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
                    // On desktop/web Enter is handled via FocusNode.onKeyEvent.
                    // On mobile, onSubmitted fires when the soft keyboard send button is tapped.
                    onSubmitted: _isDesktopOrWeb ? null : (_) => _send(),
                    textInputAction: _isDesktopOrWeb ? TextInputAction.newline : TextInputAction.send,
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
                config: Config(
                  height: 280,
                  checkPlatformCompatibility: true,
                  emojiViewConfig: EmojiViewConfig(
                    emojiSizeMax: 28,
                    backgroundColor: ZippTheme.surface,
                    noRecents: const Text(
                      'No Recents',
                      style: TextStyle(fontSize: 20, color: ZippTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  skinToneConfig: const SkinToneConfig(
                    dialogBackgroundColor: ZippTheme.surfaceVariant,
                    indicatorColor: ZippTheme.accent1,
                  ),
                  categoryViewConfig: const CategoryViewConfig(
                    backgroundColor: ZippTheme.surface,
                    indicatorColor: ZippTheme.accent1,
                    iconColorSelected: ZippTheme.accent1,
                    iconColor: ZippTheme.textSecondary,
                    dividerColor: ZippTheme.border,
                  ),
                  bottomActionBarConfig: const BottomActionBarConfig(
                    backgroundColor: ZippTheme.surface,
                    buttonColor: ZippTheme.accent1,
                    buttonIconColor: Colors.white,
                  ),
                  searchViewConfig: const SearchViewConfig(
                    backgroundColor: ZippTheme.surface,
                    buttonIconColor: ZippTheme.textSecondary,
                    hintText: 'Search emoji...',
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
