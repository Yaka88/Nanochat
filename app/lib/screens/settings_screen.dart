import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/auth_provider.dart';
import '../core/socket_provider.dart';
import '../core/l10n.dart';
import '../models/group.dart';
import '../widgets/avatar_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Group> _groups = [];
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final res = await Api.getGroups();
      setState(() {
        _groups = (res['groups'] as List).map((g) => Group.fromJson(g)).toList();
      });
    } catch (_) {}
  }

  Future<void> _logout() async {
    context.read<SocketProvider>().disconnect();
    await context.read<AuthProvider>().logout();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/welcome', (_) => false);
    }
  }

  Future<void> _changeAvatar() async {
    String? selectedPath;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarPicker(onChanged: (path) => selectedPath = path),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('完成'),
              ),
            ],
          ),
        );
      },
    );

    if (selectedPath == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      await context.read<AuthProvider>().updateAvatar(selectedPath!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像已更新')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: Text(t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.blue.withOpacity(0.1),
                    backgroundImage: user?.avatarUrl != null
                        ? NetworkImage(user!.avatarUrl!)
                        : null,
                    child: user?.avatarUrl == null
                        ? const Icon(Icons.person, size: 40, color: Colors.blue)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.nickname ?? '',
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold)),
                        if (user?.email != null)
                          Text(user!.email!,
                              style: TextStyle(
                                  fontSize: 16, color: Colors.grey[600])),
                        Text(auth.isHost ? 'Host' : 'Member',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[500])),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _uploadingAvatar ? null : _changeAvatar,
                          icon: _uploadingAvatar
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.photo_camera_outlined, size: 20),
                          label: const Text('更新头像', style: TextStyle(fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // My Groups
          Text(t('my_groups'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._groups.map((g) => Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: const Icon(Icons.home, size: 32),
                  title: Text(g.name, style: const TextStyle(fontSize: 20)),
                  trailing: g.creatorId == user?.id
                      ? Chip(
                          label: const Text('Host',
                              style: TextStyle(fontSize: 14)),
                          backgroundColor:
                              Colors.blue.withOpacity(0.1),
                        )
                      : null,
                ),
              )),
          if (auth.isHost) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/create-group'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56)),
              icon: const Icon(Icons.add, size: 24),
              label: Text(t('create_group'),
                  style: const TextStyle(fontSize: 18)),
            ),
          ],
          const SizedBox(height: 32),
          // Logout
          ElevatedButton.icon(
            onPressed: _logout,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.logout, size: 24),
            label: Text(t('logout')),
          ),
        ],
      ),
    );
  }
}
