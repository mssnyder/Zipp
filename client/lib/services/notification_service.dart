import 'notification_service_native.dart'
    if (dart.library.js_interop) 'notification_service_web.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  final _impl = NotificationServiceImpl();

  NotificationService._();

  bool get isAppFocused => _impl.isAppFocused;
  set isAppFocused(bool v) => _impl.isAppFocused = v;

  String? get activeConversationId => _impl.activeConversationId;
  set activeConversationId(String? v) => _impl.activeConversationId = v;

  set onNotificationTap(void Function(String)? cb) => _impl.onNotificationTap = cb;

  Future<void> init() => _impl.init();
  void dispose() => _impl.dispose();

  Future<void> showMessageNotification({
    required String conversationId,
    required String senderName,
    required String messagePreview,
    required String messageType,
  }) =>
      _impl.showMessageNotification(
        conversationId: conversationId,
        senderName: senderName,
        messagePreview: messagePreview,
        messageType: messageType,
      );
}
