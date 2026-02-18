import 'package:flutter/foundation.dart';

class ZippConfig {
  static const String _productionUrl = 'https://ZIPP_SERVER_DOMAIN';

  // On web, use same-origin relative paths so the app works when served from the server.
  // On native desktop, use the absolute production URL.
  static String get serverUrl => kIsWeb ? '' : _productionUrl;

  static String get wsUrl {
    if (kIsWeb) {
      final base = Uri.base;
      final scheme = base.scheme == 'https' ? 'wss' : 'ws';
      final port = (base.port == 443 || base.port == 80 || base.port == 0) ? '' : ':${base.port}';
      return '$scheme://${base.host}$port/ws';
    }
    return 'wss://ZIPP_SERVER_DOMAIN/ws';
  }

  // In dev, override with your local machine IP:
  // static String get serverUrl => kIsWeb ? '' : 'http://192.168.8.172:4200';
  // static String get wsUrl => kIsWeb ? ... : 'ws://192.168.8.172:4200/ws';
}
