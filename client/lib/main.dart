import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'config/theme.dart';
import 'services/api_service.dart';
import 'services/websocket_service.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/adaptive_home.dart';
import 'screens/login_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await ApiService.create();
  runApp(ZippApp(api: api));
}

class ZippApp extends StatefulWidget {
  final ApiService api;
  const ZippApp({super.key, required this.api});

  @override
  State<ZippApp> createState() => _ZippAppState();
}

class _ZippAppState extends State<ZippApp> {
  late final ApiService _api = widget.api;
  final _ws = WebSocketService();
  late final AuthProvider _auth;
  late final ChatProvider _chat;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _auth = AuthProvider(_api);
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
          builder: (_, state) => ChatScreen(
            conversationId: state.pathParameters['convId']!,
            participantId: state.uri.queryParameters['pid'] ?? '',
            participantName: Uri.decodeComponent(state.uri.queryParameters['name'] ?? ''),
          ),
        ),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      ],
    );

    // Restore session and connect WS
    _auth.tryRestoreSession().then((_) {
      if (_auth.isAuthenticated) {
        _chat.keyPair = _auth.keyPair;
        _ws.connect();
        _chat.loadConversations();
      }
    });

    _auth.addListener(() {
      if (_auth.isAuthenticated) {
        _chat.keyPair = _auth.keyPair;
        _ws.connect();
        _chat.loadConversations();
      }
    });
  }

  @override
  void dispose() {
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
