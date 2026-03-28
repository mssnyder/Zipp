import 'package:flutter/material.dart';
import '../../models/conversation.dart';
import '../../services/api_service.dart';

const _colors = [
  Color(0xFF5C6BC0), // indigo
  Color(0xFF26A69A), // teal
  Color(0xFFEF5350), // red
  Color(0xFFAB47BC), // purple
  Color(0xFF42A5F5), // blue
  Color(0xFF66BB6A), // green
  Color(0xFFFFA726), // orange
  Color(0xFFEC407A), // pink
];

class GroupAvatar extends StatelessWidget {
  final List<ConversationParticipant> participants;
  final String? currentUserId;
  final double size;
  final ApiService api;

  const GroupAvatar({
    super.key,
    required this.participants,
    this.currentUserId,
    this.size = 44,
    required this.api,
  });

  @override
  Widget build(BuildContext context) {
    final others = participants.where((p) => p.id != currentUserId).take(4).toList();
    final count = others.length;

    if (count == 0) {
      return _buildContainer(
        children: [_buildCell(null, null, 0, Rect.fromLTWH(0, 0, size, size))],
      );
    }

    if (count == 1) {
      return _buildContainer(children: [
        _buildCell(others[0], others[0].avatarUrl, 0, Rect.fromLTWH(0, 0, size, size)),
      ]);
    }

    if (count == 2) {
      final half = size / 2;
      return _buildContainer(children: [
        _buildCell(others[0], others[0].avatarUrl, 0, Rect.fromLTWH(0, 0, half, size)),
        _buildCell(others[1], others[1].avatarUrl, 1, Rect.fromLTWH(half, 0, half, size)),
      ]);
    }

    if (count == 3) {
      final half = size / 2;
      return _buildContainer(children: [
        _buildCell(others[0], others[0].avatarUrl, 0, Rect.fromLTWH(0, 0, half, half)),
        _buildCell(others[1], others[1].avatarUrl, 1, Rect.fromLTWH(half, 0, half, half)),
        _buildCell(others[2], others[2].avatarUrl, 2, Rect.fromLTWH(0, half, size, half)),
      ]);
    }

    // 4+ members: four quadrants
    final half = size / 2;
    return _buildContainer(children: [
      for (int i = 0; i < 4 && i < others.length; i++)
        _buildCell(
          others[i],
          others[i].avatarUrl,
          i,
          Rect.fromLTWH(i % 2 == 0 ? 0 : half, i < 2 ? 0 : half, half, half),
        ),
    ]);
  }

  Widget _buildContainer({required List<Widget> children}) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(children: children),
      ),
    );
  }

  Widget _buildCell(ConversationParticipant? p, String? avatarUrl, int index, Rect rect) {
    final color = _colors[index % _colors.length];
    final fontSize = size * (rect.width == size && rect.height == size ? 0.38 : 0.28);

    Widget content;
    if (avatarUrl != null) {
      content = Image.network(
        api.resolveUrl(avatarUrl),
        fit: BoxFit.cover,
        width: rect.width,
        height: rect.height,
        errorBuilder: (_, e, s) => _initials(p, fontSize, color),
      );
    } else {
      content = _initials(p, fontSize, color);
    }

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: content,
    );
  }

  Widget _initials(ConversationParticipant? p, double fontSize, Color bg) {
    final text = p != null && p.name.isNotEmpty ? p.name[0].toUpperCase() : '?';
    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: fontSize),
      ),
    );
  }
}
