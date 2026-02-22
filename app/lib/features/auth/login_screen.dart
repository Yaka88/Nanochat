import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session_store.dart';
import '../../core/utils/error_utils.dart';
import '../home/home_screen.dart';
import 'join_group_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final ApiClient _apiClient = ApiClient();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _deviceIdController = TextEditingController(
    text: 'nanochat-device-001',
  );

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initDeviceId();
  }

  Future<void> _initDeviceId() async {
    final saved = await SessionStore.getDeviceId();
    if (!mounted) {
      return;
    }
    _deviceIdController.text =
        (saved != null && saved.isNotEmpty) ? saved : const Uuid().v4();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    _userIdController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  Future<void> _loginByEmail() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.loginWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await _saveSessionAndEnterHome(response);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _registerByEmail() async {
    setState(() => _isLoading = true);
    try {
      final nickname = _nicknameController.text.trim();
      if (nickname.isEmpty) {
        throw Exception('请输入昵称');
      }

      final response = await _apiClient.registerWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        nickname: nickname,
      );

      if (!mounted) {
        return;
      }

      final message = (response['message'] ?? '注册成功，请前往邮箱验证').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loginByUserId() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.loginById(
        userId: _userIdController.text.trim(),
        deviceId: _deviceIdController.text.trim(),
      );
      await _saveSessionAndEnterHome(response);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSessionAndEnterHome(Map<String, dynamic> response) async {
    final token = (response['token'] ?? '').toString();
    final user = Map<String, dynamic>.from(response['user'] as Map? ?? {});
    final userId = (user['id'] ?? '').toString();
    final lastGroupId = user['lastGroupId']?.toString();

    if (token.isEmpty || userId.isEmpty) {
      throw Exception('登录响应缺少 token 或 userId');
    }

    await SessionStore.saveSession(
      token: token,
      userId: userId,
      lastGroupId: lastGroupId,
      deviceId: _deviceIdController.text.trim(),
    );

    if (!mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _showError(Object error) {
    final message = extractErrorMessage(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('登录失败: $message')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('欢迎使用 Nanochat')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.family_restroom, size: 100, color: Colors.blue),
              const SizedBox(height: 48),
              
              TextField(
                controller: _userIdController,
                decoration: const InputDecoration(
                  labelText: 'Member User ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deviceIdController,
                decoration: const InputDecoration(
                  labelText: 'Device ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _loginByUserId,
                icon: const Icon(Icons.qr_code_scanner, size: 24),
                label: Text(_isLoading ? '登录中...' : 'Member 登录（已有 user_id）'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const JoinGroupScreen(),
                          ),
                        );
                      },
                icon: const Icon(Icons.qr_code),
                label: const Text('扫码加入家庭（新成员）'),
              ),
              
              const SizedBox(height: 32),
              
              TextField(
                controller: _nicknameController,
                decoration: const InputDecoration(
                  labelText: 'Nickname',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _loginByEmail,
                icon: const Icon(Icons.email, size: 32),
                label: Text(_isLoading ? '登录中...' : '✉️ 邮箱登录（Host）'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 80),
                  textStyle: const TextStyle(fontSize: 22),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _registerByEmail,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(_isLoading ? '提交中...' : '邮箱注册（Host）'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
