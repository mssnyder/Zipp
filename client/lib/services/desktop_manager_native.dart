import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'tray_service.dart';

/// Manages desktop-specific lifecycle: window manager, tray, focus tracking.
class DesktopManager with WindowListener {
  static final DesktopManager instance = DesktopManager._();
  DesktopManager._();

  bool _initialized = false;

  bool get isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  Future<void> init() async {
    if (!isDesktop || _initialized) return;
    _initialized = true;

    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(400, 300),
      title: 'Zipp',
    );
    await windowManager.waitUntilReadyToShow(windowOptions);
    await windowManager.show();

    // Intercept close button
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    // Initialize tray
    await TrayService.instance.init();
    TrayService.instance.onShowWindow = showAndFocus;
    TrayService.instance.onCloseApp = _closeApp;
  }

  /// Called when window is restored from tray or focus returns.
  void Function()? onWindowResumed;

  Future<void> showAndFocus() async {
    await windowManager.show();
    await windowManager.focus();
    NotificationService.instance.isAppFocused = true;
    onWindowResumed?.call();
  }

  Future<void> _closeApp() async {
    await TrayService.instance.dispose();
    windowManager.removeListener(this);
    _initialized = false;
    // Clean up single-instance socket
    final uid = Platform.environment['UID'] ?? '1000';
    final socketFile = File('/tmp/zipp-$uid.sock');
    if (socketFile.existsSync()) socketFile.deleteSync();
    // exit(0) avoids the FlutterEngineRemoveView crash on Linux
    exit(0);
  }

  @override
  void onWindowClose() async {
    final minimizeToTray = await StorageService.getMinimizeToTray();
    if (minimizeToTray) {
      await windowManager.hide();
      // Mark as unfocused so notifications aren't suppressed while hidden
      NotificationService.instance.isAppFocused = false;
    } else {
      await _closeApp();
    }
  }

  @override
  void onWindowFocus() {
    NotificationService.instance.isAppFocused = true;
  }

  @override
  void onWindowBlur() {
    NotificationService.instance.isAppFocused = false;
  }

  void updateUnreadCount(int count) {
    if (_initialized) TrayService.instance.updateUnreadCount(count);
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    windowManager.removeListener(this);
    await TrayService.instance.dispose();
  }
}
