import 'dart:io';
import 'package:flutter/material.dart';
import '../../config/theme.dart';

class AttachmentPreview extends StatefulWidget {
  final File file;
  final String type; // IMAGE | VIDEO | FILE
  final Future<void> Function(File file, String type, String? caption) onSend;

  const AttachmentPreview({
    super.key,
    required this.file,
    required this.type,
    required this.onSend,
  });

  @override
  State<AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends State<AttachmentPreview> {
  final _captionCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final caption = _captionCtrl.text.trim();
    try {
      await widget.onSend(widget.file, widget.type, caption.isEmpty ? null : caption);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filename = widget.file.path.split('/').last;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  'Send ${widget.type == 'IMAGE' ? 'Photo' : widget.type == 'VIDEO' ? 'Video' : 'File'}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ZippTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: ZippTheme.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Preview area
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: _buildPreview(filename),
            ),
          ),
          const SizedBox(height: 16),

          // Caption input + send button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _captionCtrl,
                  style: const TextStyle(color: ZippTheme.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Add a caption...',
                    hintStyle: const TextStyle(color: ZippTheme.textSecondary),
                    filled: true,
                    fillColor: ZippTheme.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              _sending
                  ? const SizedBox(
                      width: 44,
                      height: 44,
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(String filename) {
    if (widget.type == 'IMAGE') {
      return Image.file(
        widget.file,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _fileFallback(filename),
      );
    }
    return _fileFallback(filename);
  }

  Widget _fileFallback(String filename) {
    final icon = widget.type == 'VIDEO' ? Icons.videocam_outlined : Icons.insert_drive_file_outlined;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ZippTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: ZippTheme.textSecondary),
          const SizedBox(height: 8),
          Text(
            filename,
            style: const TextStyle(color: ZippTheme.textPrimary),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
