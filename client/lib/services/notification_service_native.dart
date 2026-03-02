import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationServiceImpl {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool isAppFocused = true;
  String? activeConversationId;
  void Function(String conversationId)? onNotificationTap;
  int _idCounter = 0;
  bool _initialized = false;

  Future<void> init() async {
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open Zipp',
    );
    const settings = InitializationSettings(linux: linuxSettings);
    _initialized = await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onResponse,
    ) ?? false;
  }

  void _onResponse(NotificationResponse response) {
    final convId = response.payload;
    if (convId != null) onNotificationTap?.call(convId);
  }

  Future<void> showMessageNotification({
    required String conversationId,
    required String senderName,
    required String messagePreview,
    required String messageType,
  }) async {
    // Suppress if app is focused AND user is viewing this conversation
    if (isAppFocused && activeConversationId == conversationId) return;
    if (!_initialized) return;

    await _plugin.show(
      _idCounter++,
      senderName,
      messagePreview,
      const NotificationDetails(linux: LinuxNotificationDetails()),
      payload: conversationId,
    );
  }

  void dispose() {}
}
