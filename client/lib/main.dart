import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'config/theme.dart';
import 'services/api_service.dart';
import 'services/desktop_manager.dart';
import 'services/notification_service.dart';
import 'services/websocket_service.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/adaptive_home.dart';
import 'screens/login_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Initialize desktop window + tray (no-op on web)
  await DesktopManager.instance.init();

  final api = await ApiService.create();
  runApp(ZippApp(api: api));
}

class ZippApp extends StatefulWidget {
  final ApiService api;
  const ZippApp({super.key, required this.api});

  @override
  State<ZippApp> createState() => _ZippAppState();
}

class _ZippAppState extends State<ZippApp> with WidgetsBindingObserver {
  late final ApiService _api = widget.api;
  final _ws = WebSocketService();
  late final AuthProvider _auth;
  late final ChatProvider _chat;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _auth = AuthProvider(_api);
    _ws.sessionCookieGetter = _api.getSessionCookie;
    _chat = ChatProvider(_api, _ws);

    _router = GoRouter(
      refreshListenable: _auth,
      redirect: (ctx, state) {
        final authed = _auth.isAuthenticated;
        final onLogin = state.matchedLocation == '/login' ||
            state.matchedLocation == '/register';
        if (!authed && !onLogin) return '/login';
        if (authed && onLogin) return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, _) => const LoginScreen(showRegister: true)),
        GoRoute(path: '/', builder: (_, _) => const AdaptiveHome()),
        GoRoute(
          path: '/chat/:convId',
          builder: (_, state) {
            final convId = state.pathParameters['convId']!;
            final pid = state.uri.queryParameters['pid'] ?? '';
            final name = Uri.decodeComponent(state.uri.queryParameters['name'] ?? '');
            return ChatScreen(
              conversationId: convId,
              participantId: pid,
              participantName: name,
            );
          },
        ),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      ],
    );

    // Initialize notifications
    NotificationService.instance.init();
    NotificationService.instance.onNotificationTap = _onNotificationTap;

    // Wire up tray badge updates
    _chat.onUnreadCountChanged = (count) {
      DesktopManager.instance.updateUnreadCount(count);
    };

    // Refresh conversations when window comes back from tray
    DesktopManager.instance.onWindowResumed = () {
      if (_auth.isAuthenticated) {
        _ws.connect();
        _chat.loadConversations();
        // Reload messages for the currently open conversation so any
        // messages received while disconnected show up immediately.
        final activeConvId = NotificationService.instance.activeConversationId;
        if (activeConvId != null) {
          _chat.loadMessages(activeConvId);
        }
      }
    };

    // Restore session and connect WS
    _auth.tryRestoreSession().then((_) {
      if (_auth.isAuthenticated) {
        _chat.keyPair = _auth.keyPair;
        _chat.currentUserId = _auth.user?.id;
        _ws.connect();
        _chat.loadConversations();
      }
    });

    _auth.addListener(() {
      if (_auth.isAuthenticated) {
        _chat.keyPair = _auth.keyPair;
        _chat.currentUserId = _auth.user?.id;
        _ws.connect();
        _chat.loadConversations();
      }
    });
  }

  /// Handle notification tap — show window and navigate to the conversation.
  void _onNotificationTap(String conversationId) {
    DesktopManager.instance.showAndFocus();
    final convIndex = _chat.conversations.indexWhere((c) => c.id == conversationId);
    if (convIndex >= 0) {
      _chat.selectConversation(_chat.conversations[convIndex]);
    }
    _router.go('/');
  }

  /// Track focus changes for web (desktop uses WindowListener in DesktopManager).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!DesktopManager.instance.isDesktop) {
      NotificationService.instance.isAppFocused = state == AppLifecycleState.resumed;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DesktopManager.instance.dispose();
    NotificationService.instance.dispose();
    _ws.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: _auth),
          ChangeNotifierProvider.value(value: _chat),
          Provider.value(value: _api),
          Provider.value(value: _ws),
        ],
        child: MaterialApp.router(
          title: 'Zipp',
          theme: ZippTheme.dark,
          routerConfig: _router,
          debugShowCheckedModeBanner: false,
        ),
      );
}
