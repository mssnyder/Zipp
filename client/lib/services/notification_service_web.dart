import 'dart:js_interop';
import 'package:web/web.dart' as web;

class NotificationServiceImpl {
  bool isAppFocused = true;
  String? activeConversationId;
  void Function(String conversationId)? onNotificationTap;

  Future<void> init() async {
    // Request notification permission
    if (web.Notification.permission == 'default') {
      await web.Notification.requestPermission().toDart;
    }
  }

  Future<void> showMessageNotification({
    required String conversationId,
    required String senderName,
    required String messagePreview,
    required String messageType,
  }) async {
    // Suppress if document has focus AND user is viewing this conversation
    if (web.document.hasFocus() && activeConversationId == conversationId) return;

    if (web.Notification.permission != 'granted') {
      // Try requesting permission once
      final result = await web.Notification.requestPermission().toDart;
      if (result.toDart != 'granted') return;
    }

    final options = web.NotificationOptions(body: messagePreview);
    final notification = web.Notification(senderName, options);

    notification.onclick = ((web.Event e) {
      web.window.focus();
      onNotificationTap?.call(conversationId);
      notification.close();
    }).toJS;
  }

  void dispose() {}
}
