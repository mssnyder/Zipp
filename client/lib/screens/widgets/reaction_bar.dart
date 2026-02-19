import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/reaction.dart';

class ReactionBar extends StatelessWidget {
  final List<Reaction> reactions;
  final String myUserId;

  const ReactionBar({super.key, required this.reactions, required this.myUserId});

  @override
  Widget build(BuildContext context) {
    // Group by emoji
    final groups = <String, List<Reaction>>{};
    for (final r in reactions) {
      groups.putIfAbsent(r.emoji, () => []).add(r);
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: groups.entries.map((e) {
        final iMine = e.value.any((r) => r.userId == myUserId);
        final names = e.value
            .map((r) => r.displayName ?? 'Unknown')
            .toList();
        return Tooltip(
          message: names.join(', '),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: iMine
                  ? ZippTheme.accent1.withAlpha(60)
                  : ZippTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: iMine ? ZippTheme.accent1.withAlpha(150) : ZippTheme.border,
              ),
            ),
            child: Text(
              '${e.key} ${e.value.length}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        );
      }).toList(),
    );
  }
}
