import 'package:flutter/foundation.dart';
import 'server_url_stub.dart' if (dart.library.io) 'server_url_native.dart';

class ZippConfig {
  /// On web, use same-origin relative paths (empty string).
  /// On desktop, read from the ZIPP_SERVER_URL environment variable.
  static String get serverUrl => kIsWeb ? '' : nativeServerUrl();

  static String get wsUrl {
    if (kIsWeb) {
      final base = Uri.base;
      final scheme = base.scheme == 'https' ? 'wss' : 'ws';
      final port = (base.port == 443 || base.port == 80 || base.port == 0)
          ? ''
          : ':${base.port}';
      return '$scheme://${base.host}$port/ws';
    }
    final uri = Uri.parse(serverUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://${uri.host}$port/ws';
  }
}
