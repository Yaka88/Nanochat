import 'package:shared_preferences/shared_preferences.dart';

class LocalStorage {
  static const _keyToken = 'auth_token';
  static const _keyUserId = 'user_id';
  static const _keyDeviceId = 'device_id';
  static const _keyIsRegistered = 'is_registered';
  static const _keyLastGroupId = 'last_group_id';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  // Token
  static Future<String?> getToken() async =>
      (await _prefs).getString(_keyToken);

  static Future<void> setToken(String token) async =>
      (await _prefs).setString(_keyToken, token);

  // User ID
  static Future<String?> getUserId() async =>
      (await _prefs).getString(_keyUserId);

  static Future<void> setUserId(String id) async =>
      (await _prefs).setString(_keyUserId, id);

  // Device ID
  static Future<String?> getDeviceId() async =>
      (await _prefs).getString(_keyDeviceId);

  static Future<void> setDeviceId(String id) async =>
      (await _prefs).setString(_keyDeviceId, id);

  // Is Registered (Host)
  static Future<bool> getIsRegistered() async =>
      (await _prefs).getBool(_keyIsRegistered) ?? false;

  static Future<void> setIsRegistered(bool val) async =>
      (await _prefs).setBool(_keyIsRegistered, val);

  // Last Group
  static Future<String?> getLastGroupId() async =>
      (await _prefs).getString(_keyLastGroupId);

  static Future<void> setLastGroupId(String id) async =>
      (await _prefs).setString(_keyLastGroupId, id);

  // Clear all
  static Future<void> clear() async => (await _prefs).clear();
}
