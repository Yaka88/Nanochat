import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/l10n.dart';

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
    if (_nameCtrl.text.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await Api.createGroup(name: _nameCtrl.text.trim());
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
              decoration: InputDecoration(
                labelText: t('group_name'),
                prefixIcon: const Icon(Icons.edit, size: 28),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16)),
            ],
            const Spacer(),
            ElevatedButton(
              onPressed: _loading ? null : _create,
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
