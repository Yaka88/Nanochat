import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'storage.dart';

/// Top-level background message handler.
/// Must be a top-level function (not a method/closure).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM Background] Received: ${message.data}');
  await _handleCallPush(message.data);
}

/// Handle incoming call push data and show CallKit incoming call UI.
Future<void> _handleCallPush(Map<String, dynamic> data) async {
  if (data['type'] != 'call_incoming') return;

  final callerName = (data['callerName'] ?? 'Unknown') as String;
  final callerUserId = (data['callerUserId'] ?? '') as String;
  final isVideo = data['isVideo'] == 'true';

  if (callerUserId.isEmpty) return;

  final uuid = const Uuid().v4();
  final callKitParams = CallKitParams(
    id: uuid,
    nameCaller: callerName,
    appName: 'Nanochat',
    handle: 'Incoming Call',
    type: isVideo ? 1 : 0, // 0 = audio, 1 = video
    textAccept: 'Accept',
    textDecline: 'Decline',
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: true,
      subtitle: 'Missed call',
      callbackText: 'Call back',
    ),
    duration: 30000,
    extra: <String, dynamic>{'callerUserId': callerUserId, 'isVideo': isVideo},
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#0955fa',
      backgroundUrl: 'assets/test.png',
      actionColor: '#4CAF50',
      textColor: '#ffffff',
      incomingCallNotificationChannelName: 'Incoming Call',
      missedCallNotificationChannelName: 'Missed Call',
      isShowFullLockedScreen: true,
      isImportant: true,
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
}

class PushService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _initialized = false;

  /// Initialize FCM, request permissions, obtain token, and upload to server.
  /// Safe to call multiple times – only initializes once per app run.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // Request notification permissions (iOS prompts the user; Android auto-grants)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );
      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

      // On iOS, get APNs token first
      if (Platform.isIOS) {
        final apnsToken = await _messaging.getAPNSToken();
        debugPrint('[FCM] APNs token: ${apnsToken != null ? "OK" : "null"}');
        if (apnsToken == null) {
          // APNs token not yet available – listen for it later
          debugPrint('[FCM] APNs token not ready, will retry on token refresh');
        }
      }

      // Get FCM token
      final token = await _messaging.getToken();
      if (token != null) {
        await _uploadToken(token);
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        await _uploadToken(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('[FCM Foreground] Received: ${message.data}');
        await _handleCallPush(message.data);
      });

      debugPrint('[FCM] Push service initialized');
    } catch (e) {
      debugPrint('[FCM] Initialization error: $e');
    }
  }

  /// Re-register token (call after login/register when auth token changes).
  static Future<void> registerToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _uploadToken(token);
      }
    } catch (e) {
      debugPrint('[FCM] Token registration error: $e');
    }
  }

  /// Upload FCM token to the server.
  static Future<void> _uploadToken(String fcmToken) async {
    try {
      final authToken = await LocalStorage.getToken();
      if (authToken == null) return; // Not logged in yet

      final platform = Platform.isIOS ? 'ios' : 'android';
      await Api.updateDeviceToken(token: fcmToken, platform: platform);
      debugPrint('[FCM] Token uploaded ($platform)');
    } catch (e) {
      debugPrint('[FCM] Token upload error: $e');
    }
  }
}
