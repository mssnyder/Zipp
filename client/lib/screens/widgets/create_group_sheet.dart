import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';

class CreateGroupSheet extends StatefulWidget {
  const CreateGroupSheet({super.key});

  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final List<Map<String, dynamic>> _selectedUsers = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final api = context.read<ApiService>();
      _searchResults = await api.searchUsers(q);
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  void _toggleUser(Map<String, dynamic> user) {
    setState(() {
      final idx = _selectedUsers.indexWhere((u) => u['id'] == user['id']);
      if (idx >= 0) {
        _selectedUsers.removeAt(idx);
      } else {
        _selectedUsers.add(user);
      }
    });
  }

  bool _isSelected(String userId) =>
      _selectedUsers.any((u) => u['id'] == userId);

  Future<void> _createGroup() async {
    if (_selectedUsers.isEmpty) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _creating = true);
    try {
      final chat = context.read<ChatProvider>();
      final conv = await chat.createGroup(
        participantIds: _selectedUsers.map((u) => u['id'] as String).toList(),
        name: name,
      );
      if (mounted) {
        Navigator.of(context).pop();
        context.push('/chat/${conv.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.read<AuthProvider>().user?.id;
    final api = context.read<ApiService>();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('New Group', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(hintText: 'Group name'),
                ),
                const SizedBox(height: 12),
                if (_selectedUsers.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _selectedUsers.map((u) {
                      final name = u['displayName'] as String? ?? u['username'] as String;
                      return Chip(
                        label: Text(name, style: const TextStyle(fontSize: 13)),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => _toggleUser(u),
                        backgroundColor: ZippTheme.surfaceVariant,
                      );
                    }).toList(),
                  ),
                if (_selectedUsers.isNotEmpty) const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search users to add...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => _search(v.trim()),
                ),
              ],
            ),
          ),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: _searchResults.length,
                    itemBuilder: (ctx, i) {
                      final u = _searchResults[i];
                      final uid = u['id'] as String;
                      if (uid == myId) return const SizedBox.shrink();
                      final name = u['displayName'] as String? ?? u['username'] as String;
                      final avatarUrl = u['avatarUrl'] as String?;
                      final selected = _isSelected(uid);
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
                        onTap: () => _toggleUser(u),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _creating || _selectedUsers.isEmpty || _nameCtrl.text.trim().isEmpty
                    ? null
                    : _createGroup,
                child: _creating
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Create Group (${_selectedUsers.length} members)'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
