import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/auth_provider.dart';
import '../core/l10n.dart';
import '../core/storage.dart';

/// Create a new family group (Host only)
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController(text: 'Home');
  bool _loading = false;
  String? _error;

  Future<void> _create() async {
    final auth = context.read<AuthProvider>();
    if (auth.isHost && !(auth.user?.emailVerified ?? false)) {
      setState(() => _error = '请先完成邮箱验证，再创建家庭');
      return;
    }
    if (_nameCtrl.text.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Api.createGroup(name: _nameCtrl.text.trim());
      final group = res['group'] as Map<String, dynamic>?;
      final groupId = group?['id']?.toString();
      if (groupId != null && groupId.isNotEmpty) {
        await LocalStorage.setLastGroupId(groupId);
      }
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      }
    } catch (e) {
      final message = e.toString();
      if (message.toLowerCase().contains('verification')) {
        setState(() => _error = '请先完成邮箱验证，再创建家庭');
      } else {
        setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    final auth = context.watch<AuthProvider>();
    final canCreate = !auth.isHost || (auth.user?.emailVerified ?? false);
    return Scaffold(
      appBar: AppBar(title: Text(t('create_group'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 48),
            Icon(Icons.home, size: 80,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 32),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: 22),
              textAlign: TextAlign.center,
              enabled: canCreate,
              decoration: InputDecoration(
                labelText: t('group_name'),
                prefixIcon: const Icon(Icons.edit, size: 28),
              ),
            ),
            if (!canCreate) ...[
              const SizedBox(height: 12),
              const Text('请先验证邮箱，再创建家庭',
                  style: TextStyle(color: Colors.orange, fontSize: 16)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16)),
            ],
            const Spacer(),
            ElevatedButton(
              onPressed: (_loading || !canCreate) ? null : _create,
              child: _loading
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 3))
                  : Text(t('create')),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
