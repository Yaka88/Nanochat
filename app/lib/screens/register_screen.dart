import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/auth_provider.dart';
import '../core/l10n.dart';

/// Host registration: email + password + nickname + avatar
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _nickCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _nickCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final t = (String k) => AppL10n.t(context, k);
    if (_emailCtrl.text.isEmpty ||
        _passCtrl.text.isEmpty ||
        _nickCtrl.text.isEmpty) return;
    if (_passCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().register(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
            nickname: _nickCtrl.text.trim(),
          );
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t('email_register')),
            content: const Text('请查收验证邮件', style: TextStyle(fontSize: 18)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t('confirm'), style: const TextStyle(fontSize: 18)),
              ),
            ],
          ),
        );
        Navigator.pushNamedAndRemoveUntil(context, '/create-group', (_) => false);
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
      appBar: AppBar(title: Text(t('email_register'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            TextField(
              controller: _nickCtrl,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                labelText: t('nickname'),
                prefixIcon: const Icon(Icons.person, size: 28),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                labelText: t('email'),
                prefixIcon: const Icon(Icons.email, size: 28),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                labelText: t('password'),
                prefixIcon: const Icon(Icons.lock, size: 28),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                labelText: t('confirm_password'),
                prefixIcon: const Icon(Icons.lock_outline, size: 28),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16)),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _register,
              child: _loading
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 3))
                  : Text(t('register')),
            ),
          ],
        ),
      ),
    );
  }
}
