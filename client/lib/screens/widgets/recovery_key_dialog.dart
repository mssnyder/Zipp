import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';

class RecoveryKeyDialog extends StatefulWidget {
  final String recoveryKey;
  /// Called with the optional passphrase (empty string if none) when the user
  /// clicks Done after checking the acknowledgement box.
  final void Function(String passphrase) onAcknowledged;

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
  final _passphraseController = TextEditingController();
  bool _showPassphrase = false;

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ZippTheme.surface,
      title: const Text('Your recovery key'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Passphrase (optional)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Add a passphrase for extra protection. You\'ll need both the '
              'recovery key and this passphrase to restore on a new device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ZippTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passphraseController,
              obscureText: !_showPassphrase,
              decoration: InputDecoration(
                hintText: 'Leave blank to skip',
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassphrase ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _showPassphrase = !_showPassphrase),
                ),
              ),
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
      ),
      actions: [
        FilledButton(
          onPressed: _saved
              ? () => widget.onAcknowledged(_passphraseController.text.trim())
              : null,
          style: FilledButton.styleFrom(backgroundColor: ZippTheme.accent1),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
