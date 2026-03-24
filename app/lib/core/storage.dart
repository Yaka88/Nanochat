import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LocalStorage {
  static const _keyToken = 'auth_token';
  static const _keyUserId = 'user_id';
  static const _keyDeviceId = 'device_id';
  static const _keyIsRegistered = 'is_registered';
  static const _keyLastGroupId = 'last_group_id';
    static const _keyAppForeground = 'app_foreground';
    static const _keyLastIncomingCaller = 'last_incoming_caller';
    static const _keyLastIncomingAtMs = 'last_incoming_at_ms';
    static const _keyLastIncomingCallerName = 'last_incoming_caller_name';
    static const _keyLastIncomingIsVideo = 'last_incoming_is_video';

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

  /// Returns the stored device ID, or generates a new UUID v4 and persists it.
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await _prefs;
    var id = prefs.getString(_keyDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

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

  // App lifecycle state (shared between main isolate and background service)
  static Future<bool> isAppForeground() async =>
      (await _prefs).getBool(_keyAppForeground) ?? false;

  static Future<void> setAppForeground(bool val) async =>
      (await _prefs).setBool(_keyAppForeground, val);

    /// Returns true if an incoming-call UI should be shown for this caller now.
    /// Prevents duplicate CallKit popups from multiple isolates/sockets.
    static Future<bool> shouldShowIncomingCall(
        String callerUserId, {
        int windowSeconds = 8,
    }) async {
        final prefs = await _prefs;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final lastCaller = prefs.getString(_keyLastIncomingCaller);
        final lastAtMs = prefs.getInt(_keyLastIncomingAtMs) ?? 0;
        final withinWindow = nowMs - lastAtMs < windowSeconds * 1000;

        if (withinWindow && lastCaller == callerUserId) {
            return false;
        }

        await prefs.setString(_keyLastIncomingCaller, callerUserId);
        await prefs.setInt(_keyLastIncomingAtMs, nowMs);
        return true;
    }

    /// Persist minimal incoming-call payload so accept callbacks that miss
    /// `extra` can still recover target info after app is restored from background.
    static Future<void> saveIncomingCallSnapshot({
        required String callerUserId,
        required String callerName,
        required bool isVideo,
    }) async {
        final prefs = await _prefs;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await prefs.setString(_keyLastIncomingCaller, callerUserId);
        await prefs.setString(_keyLastIncomingCallerName, callerName);
        await prefs.setBool(_keyLastIncomingIsVideo, isVideo);
        await prefs.setInt(_keyLastIncomingAtMs, nowMs);
    }

    /// Read recent incoming-call payload, returns null when stale.
    static Future<Map<String, dynamic>?> readRecentIncomingCallSnapshot({
        int maxAgeSeconds = 90,
    }) async {
        final prefs = await _prefs;
        final callerUserId = prefs.getString(_keyLastIncomingCaller);
        final callerName = prefs.getString(_keyLastIncomingCallerName);
        final isVideo = prefs.getBool(_keyLastIncomingIsVideo);
        final atMs = prefs.getInt(_keyLastIncomingAtMs) ?? 0;
        if (callerUserId == null || callerUserId.isEmpty) return null;

        final ageMs = DateTime.now().millisecondsSinceEpoch - atMs;
        if (ageMs > maxAgeSeconds * 1000) return null;

        return {
            'callerUserId': callerUserId,
            'callerName': callerName ?? 'Unknown',
            'isVideo': isVideo ?? false,
        };
    }

    static Future<void> clearIncomingCallSnapshot() async {
        final prefs = await _prefs;
        await prefs.remove(_keyLastIncomingCaller);
        await prefs.remove(_keyLastIncomingCallerName);
        await prefs.remove(_keyLastIncomingIsVideo);
        await prefs.remove(_keyLastIncomingAtMs);
    }

  // Clear all
  static Future<void> clear() async => (await _prefs).clear();
}
