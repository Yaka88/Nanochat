import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/auth_provider.dart';
import '../core/l10n.dart';

/// Host login with email + password
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().login(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
          );
      if (mounted) {
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
      appBar: AppBar(title: Text(t('existing_login'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                labelText: t('email'),
                prefixIcon: const Icon(Icons.email, size: 28),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                labelText: t('password'),
                prefixIcon: const Icon(Icons.lock, size: 28),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16)),
            ],
            const Spacer(),
            ElevatedButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 3))
                  : Text(t('login')),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
