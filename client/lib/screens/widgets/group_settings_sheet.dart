import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/conversation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import 'group_avatar.dart';

class GroupSettingsSheet extends StatefulWidget {
  final String conversationId;
  const GroupSettingsSheet({super.key, required this.conversationId});

  @override
  State<GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

class _GroupSettingsSheetState extends State<GroupSettingsSheet> {
  bool _editing = false;
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String? _myRole(Conversation conv, String myId) {
    return conv.participants
        .cast<ConversationParticipant?>()
        .firstWhere((p) => p!.id == myId, orElse: () => null)
        ?.role;
  }

  Future<void> _rename(ChatProvider chat) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      await chat.renameGroup(widget.conversationId, name);
      if (mounted) setState(() => _editing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _removeMember(ChatProvider chat, String userId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Remove $name from the group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await chat.removeMember(widget.conversationId, userId);
    }
  }

  Future<void> _changeRole(ChatProvider chat, String userId, String currentRole) async {
    final newRole = currentRole == 'ADMIN' ? 'MEMBER' : 'ADMIN';
    await chat.changeRole(widget.conversationId, userId, newRole);
  }

  Future<void> _leaveGroup(ChatProvider chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await chat.leaveGroup(widget.conversationId);
      if (mounted) {
        Navigator.of(context).pop();
        context.go('/');
      }
    }
  }

  Future<void> _showInviteDialog(ChatProvider chat) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZippTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _InviteMembersSheet(conversationId: widget.conversationId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();
    final api = context.read<ApiService>();
    final myId = auth.user?.id ?? '';
    final conv = chat.conversationById(widget.conversationId);

    if (conv == null) return const Center(child: Text('Conversation not found'));

    final myRole = _myRole(conv, myId);
    final isAdmin = myRole == 'ADMIN';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(16),
        children: [
          // Group avatar + name
          Center(
            child: GroupAvatar(
              participants: conv.participants,
              currentUserId: myId,
              size: 80,
              api: api,
            ),
          ),
          const SizedBox(height: 12),
          if (_editing) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Group name'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () => _rename(chat),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _editing = false),
                ),
              ],
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  conv.displayName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _nameCtrl.text = conv.name ?? '';
                      setState(() => _editing = true);
                    },
                    child: const Icon(Icons.edit, size: 18, color: ZippTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ],
          Text(
            '${conv.participants.length} members',
            textAlign: TextAlign.center,
            style: const TextStyle(color: ZippTheme.textSecondary),
          ),
          const SizedBox(height: 24),

          // Invite button
          if (isAdmin)
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: ZippTheme.accent1,
                child: Icon(Icons.person_add, color: Colors.white, size: 20),
              ),
              title: const Text('Invite members'),
              onTap: () => _showInviteDialog(chat),
            ),

          const Divider(height: 24),

          // Member list
          const Text('Members', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          ...conv.participants.map((p) {
            final isMe = p.id == myId;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: ZippTheme.surfaceVariant,
                backgroundImage: p.avatarUrl != null ? NetworkImage(api.resolveUrl(p.avatarUrl!)) : null,
                child: p.avatarUrl == null
                    ? Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                        style: const TextStyle(color: ZippTheme.accent1))
                    : null,
              ),
              title: Row(
                children: [
                  Text(isMe ? '${p.name} (You)' : p.name),
                  if (p.role == 'ADMIN') ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ZippTheme.accent1.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Admin', style: TextStyle(fontSize: 11, color: ZippTheme.accent1)),
                    ),
                  ],
                ],
              ),
              subtitle: Text('@${p.username}', style: const TextStyle(color: ZippTheme.textSecondary)),
              trailing: isAdmin && !isMe
                  ? PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'role') _changeRole(chat, p.id, p.role);
                        if (action == 'remove') _removeMember(chat, p.id, p.name);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'role',
                          child: Text(p.role == 'ADMIN' ? 'Demote to Member' : 'Promote to Admin'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    )
                  : null,
            );
          }),

          const Divider(height: 32),

          // Leave group
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.red),
            title: const Text('Leave group', style: TextStyle(color: Colors.red)),
            onTap: () => _leaveGroup(chat),
          ),
        ],
      ),
    );
  }
}

// ── Invite members sub-sheet ─────────────────────────────────────────────────

class _InviteMembersSheet extends StatefulWidget {
  final String conversationId;
  const _InviteMembersSheet({required this.conversationId});

  @override
  State<_InviteMembersSheet> createState() => _InviteMembersSheetState();
}

class _InviteMembersSheetState extends State<_InviteMembersSheet> {
  final _searchCtrl = TextEditingController();
  final List<Map<String, dynamic>> _selected = [];
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _inviting = false;
  bool _shareHistory = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      _results = await context.read<ApiService>().searchUsers(q);
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _invite() async {
    if (_selected.isEmpty) return;
    setState(() => _inviting = true);
    try {
      final chat = context.read<ChatProvider>();
      await chat.inviteMembers(
        conversationId: widget.conversationId,
        userIds: _selected.map((u) => u['id'] as String).toList(),
        shareHistory: _shareHistory,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final conv = chat.conversationById(widget.conversationId);
    final existingIds = conv?.participants.map((p) => p.id).toSet() ?? {};
    final myId = context.read<AuthProvider>().user?.id;
    final api = context.read<ApiService>();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Invite Members', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(hintText: 'Search users...', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => _search(v.trim()),
                ),
                const SizedBox(height: 8),
                if (_selected.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _selected.map((u) {
                      final name = u['displayName'] as String? ?? u['username'] as String;
                      return Chip(
                        label: Text(name, style: const TextStyle(fontSize: 13)),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => setState(() => _selected.removeWhere((s) => s['id'] == u['id'])),
                        backgroundColor: ZippTheme.surfaceVariant,
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Share conversation history'),
                  subtitle: const Text('New members can see past messages', style: TextStyle(fontSize: 12, color: ZippTheme.textSecondary)),
                  value: _shareHistory,
                  onChanged: (v) => setState(() => _shareHistory = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) {
                      final u = _results[i];
                      final uid = u['id'] as String;
                      if (uid == myId || existingIds.contains(uid)) return const SizedBox.shrink();
                      final name = u['displayName'] as String? ?? u['username'] as String;
                      final avatarUrl = u['avatarUrl'] as String?;
                      final selected = _selected.any((s) => s['id'] == uid);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: ZippTheme.surfaceVariant,
                          backgroundImage: avatarUrl != null ? NetworkImage(api.resolveUrl(avatarUrl)) : null,
                          child: avatarUrl == null
                              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: ZippTheme.accent1))
                              : null,
                        ),
                        title: Text(name),
                        subtitle: Text('@${u['username']}', style: const TextStyle(color: ZippTheme.textSecondary)),
                        trailing: selected
                            ? const Icon(Icons.check_circle, color: ZippTheme.accent1)
                            : const Icon(Icons.circle_outlined, color: ZippTheme.textSecondary),
                        onTap: () => setState(() {
                          if (selected) {
                            _selected.removeWhere((s) => s['id'] == uid);
                          } else {
                            _selected.add(u);
                          }
                        }),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _inviting || _selected.isEmpty ? null : _invite,
                child: _inviting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Invite ${_selected.length} member${_selected.length == 1 ? '' : 's'}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
