import 'dart:io';
import 'dart:typed_data';

/// Copy image bytes to clipboard on Linux via wl-copy (Wayland) or xclip (X11).
Future<void> copyImageToClipboardNative(Uint8List bytes, String filePath) async {
  if (!Platform.isLinux) return;

  final ext = filePath.split('.').last.toLowerCase();
  final mime = const {
    'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
    'gif': 'image/gif', 'webp': 'image/webp',
  }[ext] ?? 'image/png';

  // Try Wayland first (wl-copy reads from stdin)
  try {
    final proc = await Process.start('wl-copy', ['--type', mime]);
    proc.stdin.add(bytes);
    await proc.stdin.close();
    final exitCode = await proc.exitCode;
    if (exitCode == 0) return;
  } catch (_) {}

  // Fall back to X11 xclip
  final proc = await Process.start('xclip', ['-selection', 'clipboard', '-t', mime]);
  proc.stdin.add(bytes);
  await proc.stdin.close();
  await proc.exitCode;
}

bool get isNativeLinux => !const bool.fromEnvironment('dart.library.js_interop') && Platform.isLinux;
