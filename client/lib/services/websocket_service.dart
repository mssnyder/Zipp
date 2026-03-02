import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/constants.dart';

typedef WsEventHandler = void Function(String event, Map<String, dynamic> payload);

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final List<WsEventHandler> _handlers = [];
  bool _disposed = false;
  bool _connecting = false;
  Timer? _reconnectTimer;

  /// Cookie getter for native auth — set by main.dart from ApiService.
  Future<String?> Function()? sessionCookieGetter;

  void addListener(WsEventHandler handler) => _handlers.add(handler);
  void removeListener(WsEventHandler handler) => _handlers.remove(handler);

  Future<void> connect() async {
    if (_connecting) return;
    _disposed = false;
    _connecting = true;
    _reconnectTimer?.cancel();

    // Tear down any existing subscription before opening a new one
    await _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;

    // Get session cookie for authentication (native only; web uses browser cookies)
    final sessionCookie = await sessionCookieGetter?.call();

    try {
      final wsUri = sessionCookie != null
          ? Uri.parse('${ZippConfig.wsUrl}?sid=$sessionCookie')
          : Uri.parse(ZippConfig.wsUrl);
      _channel = WebSocketChannel.connect(wsUri);
      await _channel!.ready;
      _sub = _channel!.stream.listen(
        (raw) {
          try {
            final msg = jsonDecode(raw as String) as Map<String, dynamic>;
            final event = msg['event'] as String? ?? '';
            final payload = msg['payload'] as Map<String, dynamic>? ?? {};
            for (final h in List.of(_handlers)) {
              h(event, payload);
            }
          } catch (_) {}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[WS] connect failed: $e');
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void send(String event, Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode({'event': event, 'payload': payload}));
  }

  void sendTyping(String conversationId, {required bool isTyping}) {
    send('message:typing', {'conversationId': conversationId, 'isTyping': isTyping});
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _handlers.clear();
  }
}
