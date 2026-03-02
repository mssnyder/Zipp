import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import 'widgets/conversation_tile.dart';
import 'widgets/user_search_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: ZippTheme.background,
      appBar: AppBar(
        title: const Text('Zipp'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: () async {
              await auth.logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: chat.convsLoading
          ? const Center(child: CircularProgressIndicator())
          : chat.conversations.isEmpty
              ? _empty(context)
              : RefreshIndicator(
                  onRefresh: chat.loadConversations,
                  child: ListView.separated(
                    itemCount: chat.conversations.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
                    itemBuilder: (ctx, i) {
                      final conv = chat.conversations[i];
                      return ConversationTile(conversation: conv)
                          .animate()
                          .fadeIn(delay: (i * 40).ms)
                          .slideX(begin: 0.05, end: 0);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUserSearch(context),
        backgroundColor: ZippTheme.accent1,
        child: const Icon(Icons.edit_outlined, color: Colors.white),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: ZippTheme.textSecondary.withAlpha(60)),
            const SizedBox(height: 16),
            Text('No conversations yet',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: ZippTheme.textSecondary)),
            const SizedBox(height: 8),
            Text('Tap + to start chatting',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );

  void _showUserSearch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZippTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const UserSearchSheet(),
    );
  }
}
