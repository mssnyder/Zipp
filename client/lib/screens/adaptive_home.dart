import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import 'chat_screen.dart';
import 'widgets/conversation_tile.dart';
import 'widgets/user_search_sheet.dart';

const _kDesktopBreakpoint = 720.0;
const _kSidebarWidth = 320.0;

class AdaptiveHome extends StatelessWidget {
  const AdaptiveHome({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= _kDesktopBreakpoint) {
      return const _DesktopLayout();
    }
    return const _MobileLayout();
  }
}

// ── Mobile layout ──────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  const _MobileLayout();

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
      body: _ConversationList(chat: chat, desktop: false),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUserSearch(context),
        backgroundColor: ZippTheme.accent1,
        child: const Icon(Icons.edit_outlined, color: Colors.white),
      ),
    );
  }
}

// ── Desktop layout ─────────────────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout();

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();
    final selectedConvId = chat.selectedConvId;

    return Scaffold(
      backgroundColor: ZippTheme.background,
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────────────────
          SizedBox(
            width: _kSidebarWidth,
            child: Column(
              children: [
                // Sidebar AppBar
                Container(
                  height: kToolbarHeight + MediaQuery.paddingOf(context).top,
                  padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
                  decoration: const BoxDecoration(
                    color: ZippTheme.background,
                    border: Border(right: BorderSide(color: ZippTheme.border)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Text(
                        'Zipp',
                        style: Theme.of(context).appBarTheme.titleTextStyle,
                      ),
                      const Spacer(),
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
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showUserSearch(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _ConversationList(chat: chat, desktop: true),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: ZippTheme.border),
          // ── Chat pane ────────────────────────────────────────────────────
          Expanded(
            child: selectedConvId != null
                ? ChatScreen(
                    key: ValueKey(selectedConvId),
                    conversationId: selectedConvId,
                    participantId: chat.selectedParticipantId ?? '',
                    participantName: chat.selectedParticipantName,
                    embedded: true,
                  )
                : const _NoChatPlaceholder(),
          ),
        ],
      ),
    );
  }
}

class _NoChatPlaceholder extends StatelessWidget {
  const _NoChatPlaceholder();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 72, color: ZippTheme.textSecondary.withAlpha(50)),
            const SizedBox(height: 16),
            Text('Select a conversation',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: ZippTheme.textSecondary)),
          ],
        ),
      );
}

// ── Shared conversation list ───────────────────────────────────────────────────

class _ConversationList extends StatelessWidget {
  final ChatProvider chat;
  final bool desktop;

  const _ConversationList({required this.chat, required this.desktop});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (chat.convsLoading) return const Center(child: CircularProgressIndicator());
    final showBanner = auth.needsKeyRestore || auth.needsKeyBackup;
    if (chat.conversations.isEmpty && !showBanner) return _empty(context);

    return RefreshIndicator(
      onRefresh: chat.loadConversations,
      child: ListView.builder(
        itemCount: chat.conversations.length + (showBanner ? 1 : 0),
        itemBuilder: (ctx, i) {
          // Key restore/backup banner at the top
          if (showBanner && i == 0) {
            return _KeyRestoreBanner(auth: auth, chat: chat);
          }
          final convIdx = showBanner ? i - 1 : i;
          final conv = chat.conversations[convIdx];
          final isSelected = desktop && chat.selectedConvId == conv.id;
          return Column(
            children: [
              ConversationTile(
                conversation: conv,
                isSelected: isSelected,
                onTap: desktop
                    ? () => chat.selectConversation(conv)
                    : null,
              )
                  .animate()
                  .fadeIn(delay: (convIdx * 40).ms)
                  .slideX(begin: 0.05, end: 0),
              if (!desktop) const Divider(height: 1, indent: 76),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 64, color: ZippTheme.textSecondary.withAlpha(60)),
            const SizedBox(height: 16),
            Text('No conversations yet',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: ZippTheme.textSecondary)),
            const SizedBox(height: 8),
            Text('Tap + to start chatting',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _KeyRestoreBanner extends StatelessWidget {
  final AuthProvider auth;
  final ChatProvider chat;

  const _KeyRestoreBanner({required this.auth, required this.chat});

  @override
  Widget build(BuildContext context) {
    final isBackup = auth.needsKeyBackup && !auth.needsKeyRestore;
    final title = isBackup ? 'Back up encryption key' : 'Encryption key needed';
    final subtitle = isBackup
        ? 'Enter your password to back up your key for other devices.'
        : 'Enter your password to decrypt messages.';
    final buttonLabel = isBackup ? 'Back up' : 'Unlock';

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ZippTheme.accent1.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZippTheme.accent1.withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(Icons.key, color: ZippTheme.accent2, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _showRestoreDialog(context),
            style: FilledButton.styleFrom(
              backgroundColor: ZippTheme.accent1,
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }

  void _showRestoreDialog(BuildContext context) {
    final controller = TextEditingController();
    var loading = false;
    String? errorMsg;
    final isBackup = auth.needsKeyBackup && !auth.needsKeyRestore;
    final dialogTitle = isBackup ? 'Back up encryption key' : 'Unlock encryption';
    final dialogDesc = isBackup
        ? 'Enter your account password to back up your encryption key for use on other devices.'
        : 'Enter your account password to restore your encryption key.';
    final buttonText = isBackup ? 'Back up' : 'Unlock';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: ZippTheme.surface,
          title: Text(dialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dialogDesc),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  errorText: errorMsg,
                ),
                onSubmitted: loading ? null : (_) => _restore(ctx, controller, setState, (l) => loading = l, (e) => errorMsg = e, isBackup),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: loading ? null : () => _restore(ctx, controller, setState, (l) => loading = l, (e) => errorMsg = e, isBackup),
              child: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restore(
    BuildContext ctx,
    TextEditingController controller,
    void Function(void Function()) setState,
    void Function(bool) setLoading,
    void Function(String?) setError,
    bool isBackup,
  ) async {
    final password = controller.text.trim();
    if (password.isEmpty) return;

    setState(() { setLoading(true); setError(null); });

    bool ok;
    if (isBackup) {
      ok = await auth.createKeyBackup(password);
    } else {
      ok = await auth.restoreKeyFromBackup(password);
    }
    if (!ctx.mounted) return;

    if (ok) {
      Navigator.pop(ctx);
      chat.keyPair = auth.keyPair;
      chat.currentUserId = auth.user?.id;
      chat.loadConversations();
    } else {
      final errorText = isBackup
          ? 'Failed to create backup. Check your password.'
          : 'Wrong password or restore failed.';
      setState(() { setLoading(false); setError(errorText); });
    }
  }
}

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
