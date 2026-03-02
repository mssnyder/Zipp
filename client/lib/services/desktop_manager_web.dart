/// No-op on web — no window manager or tray.
class DesktopManager {
  static final DesktopManager instance = DesktopManager._();
  DesktopManager._();

  bool get isDesktop => false;
  void Function()? onWindowResumed;

  Future<void> showAndFocus() async {}
  Future<void> init() async {}
  void updateUnreadCount(int count) {}
  Future<void> dispose() async {}
}
