import 'package:flutter/material.dart';
import '../core/l10n.dart';

/// Full-screen incoming call UI
class IncomingCallDialog extends StatelessWidget {
  final String callerName;
  final bool isVideo;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const IncomingCallDialog({
    super.key,
    required this.callerName,
    required this.isVideo,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Icon(
              isVideo ? Icons.videocam : Icons.phone,
              size: 64,
              color: Colors.white70,
            ),
            const SizedBox(height: 16),
            Text(t('incoming_call'),
                style: const TextStyle(fontSize: 22, color: Colors.white70)),
            const SizedBox(height: 12),
            Text(callerName,
                style: const TextStyle(
                    fontSize: 36,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
            const Spacer(flex: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject
                _RoundButton(
                  icon: Icons.call_end,
                  label: t('reject'),
                  color: Colors.red,
                  onTap: onReject,
                ),
                // Accept
                _RoundButton(
                  icon: isVideo ? Icons.videocam : Icons.phone,
                  label: t('accept'),
                  color: Colors.green,
                  onTap: onAccept,
                ),
              ],
            ),
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 10),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 18)),
      ],
    );
  }
}
