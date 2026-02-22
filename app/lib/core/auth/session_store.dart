import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  static const String keyAuthToken = 'auth_token';
  static const String keyUserId = 'user_id';
  static const String keyLastGroupId = 'last_group_id';
  static const String keyDeviceId = 'device_id';

  static Future<void> saveSession({
    required String token,
    required String userId,
    String? lastGroupId,
    String? deviceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyAuthToken, token);
    await prefs.setString(keyUserId, userId);
    if (lastGroupId != null && lastGroupId.isNotEmpty) {
      await prefs.setString(keyLastGroupId, lastGroupId);
    }
    if (deviceId != null && deviceId.isNotEmpty) {
      await prefs.setString(keyDeviceId, deviceId);
    }
  }

  static Future<String?> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyAuthToken);
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyUserId);
  }

  static Future<String?> getLastGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyLastGroupId);
  }

  static Future<void> setLastGroupId(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLastGroupId, groupId);
  }

  static Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyDeviceId);
  }

  static Future<void> setDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyDeviceId, deviceId);
  }

  static Future<bool> hasAuthToken() async {
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyAuthToken);
    await prefs.remove(keyUserId);
    await prefs.remove(keyLastGroupId);
    await prefs.remove(keyDeviceId);
  }
}
