import 'package:flutter/material.dart';
import 'app/themes/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'core/api/api_client.dart';
import 'core/auth/session_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const NanochatApp());
}

class NanochatApp extends StatefulWidget {
  const NanochatApp({Key? key}) : super(key: key);

  @override
  State<NanochatApp> createState() => _NanochatAppState();
}

class _NanochatAppState extends State<NanochatApp> {
  final ApiClient _apiClient = ApiClient();
  Widget _home = const Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      if (await SessionStore.hasAuthToken()) {
        if (!mounted) return;
        setState(() => _home = const HomeScreen());
        return;
      }

      final userId = await SessionStore.getUserId();
      final deviceId = await SessionStore.getDeviceId();
      if (userId != null && userId.isNotEmpty && deviceId != null && deviceId.isNotEmpty) {
        final response = await _apiClient.loginById(userId: userId, deviceId: deviceId);
        final token = (response['token'] ?? '').toString();
        final user = Map<String, dynamic>.from(response['user'] as Map? ?? {});
        final refreshUserId = (user['id'] ?? '').toString();
        final lastGroupId = user['lastGroupId']?.toString();

        if (token.isNotEmpty && refreshUserId.isNotEmpty) {
          await SessionStore.saveSession(
            token: token,
            userId: refreshUserId,
            lastGroupId: lastGroupId,
            deviceId: deviceId,
          );
          if (!mounted) return;
          setState(() => _home = const HomeScreen());
          return;
        }
      }
    } catch (_) {
      await SessionStore.clear();
    }

    if (!mounted) return;
    setState(() => _home = const LoginScreen());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nanochat',
      theme: AppTheme.lightTheme,
      home: _home,
      debugShowCheckedModeBanner: false,
    );
  }
}
