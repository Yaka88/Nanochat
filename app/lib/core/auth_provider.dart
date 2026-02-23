import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/storage.dart';
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
    final data = await Api.register(
      email: email,
      password: password,
      nickname: nickname,
    );
    await LocalStorage.setToken(data['token']);
    await LocalStorage.setUserId(data['user']['id']);
    await LocalStorage.setIsRegistered(true);
    _user = User.fromJson(data['user']);
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) async {
    final data = await Api.login(email: email, password: password);
    await LocalStorage.setToken(data['token']);
    await LocalStorage.setUserId(data['user']['id']);
    await LocalStorage.setIsRegistered(true);
    _user = User.fromJson(data['user']);
    notifyListeners();
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
  }

  Future<void> logout() async {
    await LocalStorage.clear();
    _user = null;
    notifyListeners();
  }

  Future<void> updateAvatar(String filePath) async {
    final data = await Api.updateMyAvatar(filePath);
    _user = User.fromJson(data['user']);
    notifyListeners();
  }
}
