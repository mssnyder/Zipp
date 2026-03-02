import 'package:tray_manager/tray_manager.dart';

class TrayService with TrayListener {
  static final TrayService instance = TrayService._();
  TrayService._();

  void Function()? onShowWindow;
  void Function()? onCloseApp;
  int _unreadCount = 0;

  Future<void> init() async {
    // tray_manager.setIcon() automatically resolves relative to
    // <exe_dir>/data/flutter_assets/, so pass the asset path directly.
    await trayManager.setIcon('assets/images/icon.png');
    await _rebuildMenu();
    trayManager.addListener(this);
  }

  void updateUnreadCount(int count) {
    if (_unreadCount == count) return;
    _unreadCount = count;
    // Show count as label next to tray icon
    trayManager.setTitle(count > 0 ? '$count' : '');
    _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    final items = <MenuItem>[
      MenuItem(key: 'show', label: 'Show Zipp'),
      MenuItem.separator(),
    ];
    if (_unreadCount > 0) {
      items.add(MenuItem(
        key: 'unread',
        label: '$_unreadCount unread message${_unreadCount == 1 ? '' : 's'}',
        disabled: true,
      ));
      items.add(MenuItem.separator());
    }
    items.add(MenuItem(key: 'close', label: 'Close Zipp'));

    final menu = Menu(items: items);
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        onShowWindow?.call();
      case 'close':
        onCloseApp?.call();
    }
  }

  Future<void> dispose() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
