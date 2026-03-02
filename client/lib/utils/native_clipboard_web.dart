import 'dart:typed_data';

/// No-op on web — Pasteboard.writeImage handles web clipboard.
Future<void> copyImageToClipboardNative(Uint8List bytes, String filePath) async {}

bool get isNativeLinux => false;
