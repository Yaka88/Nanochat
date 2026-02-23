import 'package:flutter/material.dart';
import '../core/l10n.dart';

/// Welcome screen with 3 login options: Scan, Register, Login
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              const Spacer(),
              // Logo
              Icon(Icons.chat_bubble_rounded,
                  size: 80, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text('Nanochat',
                  style: Theme.of(context).textTheme.headlineLarge),
              const Spacer(),
              // 1. Scan to Join
              _WelcomeButton(
                icon: Icons.qr_code_scanner,
                label: t('scan_join'),
                desc: t('scan_join_desc'),
                color: Theme.of(context).colorScheme.primary,
                onTap: () => Navigator.pushNamed(context, '/scan'),
              ),
              const SizedBox(height: 16),
              // 2. Email Register
              _WelcomeButton(
                icon: Icons.email_outlined,
                label: t('email_register'),
                desc: t('email_register_desc'),
                color: Colors.teal,
                onTap: () => Navigator.pushNamed(context, '/register'),
              ),
              const SizedBox(height: 16),
              // 3. Existing Account Login
              _WelcomeButton(
                icon: Icons.person_outline,
                label: t('existing_login'),
                desc: t('existing_login_desc'),
                color: Colors.deepOrange,
                onTap: () => Navigator.pushNamed(context, '/login'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final Color color;
  final VoidCallback onTap;

  const _WelcomeButton({
    required this.icon,
    required this.label,
    required this.desc,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Row(
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    const SizedBox(height: 4),
                    Text(desc,
                        style: TextStyle(fontSize: 16, color: Colors.grey[700])),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}
