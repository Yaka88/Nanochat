import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../core/l10n.dart';
import '../models/group.dart';

/// Family member card: Avatar | Nickname | Video | Voice | Message
class MemberCard extends StatelessWidget {
  final GroupMember member;
  final bool isOnline;
  final VoidCallback? onVideo;
  final VoidCallback? onVoice;
  final VoidCallback? onMessage;

  const MemberCard({
    super.key,
    required this.member,
    required this.isOnline,
    this.onVideo,
    this.onVoice,
    this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            // Large Avatar
            _Avatar(avatarUrl: member.avatarUrl, isOnline: isOnline),
            const SizedBox(width: 16),
            // Nickname
            Expanded(
              child: Text(
                member.nameInGroup,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            // Action buttons: Video | Voice | Message
            _ActionButton(
              icon: Icons.videocam,
              label: t('video'),
              color: Colors.blue,
              onTap: onVideo,
            ),
            const SizedBox(width: 8),
            _ActionButton(
              icon: Icons.phone,
              label: t('voice'),
              color: Colors.green,
              onTap: onVoice,
            ),
            const SizedBox(width: 8),
            _ActionButton(
              icon: Icons.chat_bubble,
              label: t('message'),
              color: Colors.blue,
              onTap: onMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final bool isOnline;

  const _Avatar({this.avatarUrl, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: Colors.grey[200],
          backgroundImage:
              avatarUrl != null ? NetworkImage(avatarUrl!) : null,
          child: avatarUrl == null
              ? const Icon(Icons.person, size: 36, color: Colors.grey)
              : null,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: isOnline ? AppTheme.onlineGreen : AppTheme.offlineGrey,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final effectiveColor = enabled ? color : Colors.grey[400]!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: effectiveColor),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 13, color: effectiveColor)),
          ],
        ),
      ),
    );
  }
}
