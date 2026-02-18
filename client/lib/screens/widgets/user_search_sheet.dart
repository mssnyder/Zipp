import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';

class UserSearchSheet extends StatefulWidget {
  const UserSearchSheet({super.key});

  @override
  State<UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<UserSearchSheet> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      _users = await api.searchUsers(q);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _startChat(Map<String, dynamic> user) async {
    final chat = context.read<ChatProvider>();
    Navigator.of(context).pop();
    final conv = await chat.getOrCreateConversation(user['id'] as String);
    if (mounted) {
      context.push(
        '/chat/${conv.id}?pid=${user['id']}&name=${Uri.encodeComponent(user['displayName'] ?? user['username'])}',
      );
    }
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search by username…',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => _search(v.trim()),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _users.isEmpty
                      ? Center(
                          child: Text(
                            _ctrl.text.isEmpty ? 'Start typing to search' : 'No users found',
                            style: const TextStyle(color: ZippTheme.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          itemCount: _users.length,
                          itemBuilder: (ctx, i) {
                            final u = _users[i];
                            final name = u['displayName'] as String? ?? u['username'] as String;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: ZippTheme.surfaceVariant,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: ZippTheme.accent1),
                                ),
                              ),
                              title: Text(name),
                              subtitle: Text(
                                '@${u['username']}',
                                style: const TextStyle(color: ZippTheme.textSecondary),
                              ),
                              onTap: () => _startChat(u),
                            );
                          },
                        ),
            ),
          ],
        ),
      );
}
