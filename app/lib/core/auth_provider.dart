import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/storage.dart';
import '../core/push_service.dart';
import '../models/user.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _loading = true;

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _loading;
  bool get isHost => _user?.isRegistered ?? false;

  Future<void> init() async {
    _loading = true;
    notifyListeners();
    try {
      final token = await LocalStorage.getToken();
      if (token != null) {
        final data = await Api.getMe();
        _user = User.fromJson(data['user']);
        // Re-register push token on auto-login (token may have changed)
        PushService.registerToken();
      }
    } catch (_) {
      // Token expired or invalid, try device login
      await _tryDeviceLogin();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _tryDeviceLogin() async {
    final userId = await LocalStorage.getUserId();
    final deviceId = await LocalStorage.getDeviceId();
    if (userId != null && deviceId != null) {
      try {
        final data = await Api.loginById(userId: userId, deviceId: deviceId);
        await LocalStorage.setToken(data['token']);
        _user = User.fromJson(data['user']);
        // Register push token with server
        PushService.registerToken();
      } catch (_) {
        await LocalStorage.clear();
      }
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String nickname,
  }) async {
    final deviceId = await LocalStorage.getOrCreateDeviceId();
    final data = await Api.register(
      email: email,
      password: password,
      nickname: nickname,
      deviceId: deviceId,
    );
    await LocalStorage.setToken(data['token']);
    await LocalStorage.setUserId(data['user']['id']);
    await LocalStorage.setIsRegistered(true);
    _user = User.fromJson(data['user']);
    notifyListeners();
    // Register push token with server
    PushService.registerToken();
  }

  Future<void> login({required String email, required String password}) async {
    final deviceId = await LocalStorage.getOrCreateDeviceId();
    final data = await Api.login(email: email, password: password, deviceId: deviceId);
    await LocalStorage.setToken(data['token']);
    await LocalStorage.setUserId(data['user']['id']);
    await LocalStorage.setIsRegistered(true);
    _user = User.fromJson(data['user']);
    notifyListeners();
    // Register push token with server
    PushService.registerToken();
  }

  Future<void> loginById({
    required String userId,
    required String deviceId,
  }) async {
    final data = await Api.loginById(userId: userId, deviceId: deviceId);
    await LocalStorage.setToken(data['token']);
    await LocalStorage.setUserId(userId);
    await LocalStorage.setDeviceId(deviceId);
    _user = User.fromJson(data['user']);
    notifyListeners();
    // Register push token with server
    PushService.registerToken();
  }

  Future<void> logout() async {
    await LocalStorage.clear();
    _user = null;
    notifyListeners();
  }

  Future<void> upgradeToRegistered({
    required String email,
    required String password,
  }) async {
    final deviceId = await LocalStorage.getOrCreateDeviceId();
    final data = await Api.upgradeToRegistered(email: email, password: password, deviceId: deviceId);
    await LocalStorage.setToken(data['token']);
    await LocalStorage.setIsRegistered(true);
    _user = User.fromJson(data['user']);
    notifyListeners();
  }

  Future<void> resendVerificationEmail() async {
    final data = await Api.resendVerificationEmail();
    if (data['user'] is Map<String, dynamic>) {
      _user = User.fromJson(data['user']);
      notifyListeners();
    }
  }

  Future<void> updateAvatar(String filePath) async {
    final data = await Api.updateMyAvatar(filePath);
    _user = User.fromJson(data['user']);
    notifyListeners();
  }
}
