import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';

class RecoveryKeyDialog extends StatefulWidget {
  final String recoveryKey;
  final VoidCallback onAcknowledged;

  const RecoveryKeyDialog({
    super.key,
    required this.recoveryKey,
    required this.onAcknowledged,
  });

  @override
  State<RecoveryKeyDialog> createState() => _RecoveryKeyDialogState();
}

class _RecoveryKeyDialogState extends State<RecoveryKeyDialog> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ZippTheme.surface,
      title: const Text('Your recovery key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This is the only way to recover your encrypted messages if you '
            'lose access to this device. Save it in a password manager or '
            'write it down somewhere safe.',
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ZippTheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ZippTheme.accent2.withAlpha(80)),
            ),
            child: SelectableText(
              widget.recoveryKey,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: ZippTheme.accent2,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.recoveryKey));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Recovery key copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy to clipboard'),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _saved,
            onChanged: (v) => setState(() => _saved = v ?? false),
            title: const Text(
              'I have saved this recovery key',
              style: TextStyle(fontSize: 14),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: _saved ? widget.onAcknowledged : null,
          style: FilledButton.styleFrom(backgroundColor: ZippTheme.accent1),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
