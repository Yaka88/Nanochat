import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../core/api.dart';
import '../core/auth_provider.dart';
import '../core/socket_provider.dart';
import '../core/storage.dart';
import '../core/l10n.dart';

/// Member join screen after scanning QR code
class JoinGroupScreen extends StatefulWidget {
  final Map<String, dynamic> inviteData;
  const JoinGroupScreen({super.key, required this.inviteData});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _nickCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

    String get _groupName =>
      (widget.inviteData['group_name'] ?? widget.inviteData['groupName'] ?? '')
        .toString();
    String get _inviterName =>
      (widget.inviteData['inviter_name'] ?? widget.inviteData['inviterName'] ?? '')
        .toString();

  Future<void> _join() async {
    if (_nickCtrl.text.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final deviceId = const Uuid().v4();
      final nickname = _nickCtrl.text.trim();

      final data = await Api.joinGroupByCode(
        groupId: (widget.inviteData['group_id'] ?? widget.inviteData['groupId'])
            .toString(),
        groupName: _groupName,
        inviterName: _inviterName,
        timestamp: (widget.inviteData['timestamp'] as num).toInt(),
        signature: (widget.inviteData['signature'] ?? '').toString(),
        inviteCode:
            (widget.inviteData['invite_code'] ?? widget.inviteData['inviteCode'])
                .toString(),
        deviceId: deviceId,
        nickname: nickname,
        nameInGroup: nickname,
      );

      // Save credentials locally
      await LocalStorage.setToken(data['token']);
      await LocalStorage.setUserId(data['user']['id']);
      await LocalStorage.setDeviceId(deviceId);
      await LocalStorage.setIsRegistered(false);

      if (mounted) {
        await context.read<AuthProvider>().init();
        // Connect socket and notify about the new group
        final socket = context.read<SocketProvider>();
        await socket.reconnect();
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    return Scaffold(
      appBar: AppBar(title: Text(t('scan_join'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Group info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.home, size: 48,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(_groupName,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text('${t('invite_member')}: $_inviterName',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nickCtrl,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                labelText: t('name_in_group'),
                hintText: t('name_in_group_hint'),
                prefixIcon: const Icon(Icons.person, size: 28),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16)),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _join,
              child: _loading
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 3))
                  : Text(t('join')),
            ),
          ],
        ),
      ),
    );
  }
}
