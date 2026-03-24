import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Background service entry point.
///
/// This runs in a SEPARATE Dart isolate.  Its ONLY job is to keep the Android
/// foreground-service notification alive so the OS doesn't kill our process.
/// All networking (WebSocket, call signaling, WebRTC) runs in the **main**
/// isolate via [SocketProvider].  Having a second socket here would cause
/// duplicate connections on the server and break call routing.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Pure keep-alive – no socket, no CallKit handling.
  // The foreground notification alone keeps the Android process alive
  // so the main isolate's SocketProvider stays connected.
  service.on('stopService').listen((_) {
    service.stopSelf();
  });
}

class BackgroundServiceManager {
  static bool _configured = false;

  static Future<void> initialize() async {
    if (_configured) return;
    final service = FlutterBackgroundService();

    // Notification channel for Android Foreground Service
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'nanochat_foreground', // id
      'Nanochat Background Service', // name
      description: 'Keeps Nanochat awake to receive calls.', // description
      importance: Importance.low, // importance must be at low or higher level
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'nanochat_foreground',
        initialNotificationTitle: 'Nanochat',
        initialNotificationContent: 'Ready to receive calls',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        // iOS: Do NOT auto-start the background socket service.
        // iOS aggressively kills background processes, making WebSocket
        // connections unreliable. Instead, we rely on FCM push notifications
        // (via APNs VoIP pushes) to wake the app and show incoming calls.
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _configured = true;
  }

  /// Ensure the Android foreground service is running.
  /// Safe to call repeatedly after login/app resume.
  static Future<void> ensureStarted() async {
    final service = FlutterBackgroundService();
    await initialize();
    final running = await service.isRunning();
    if (!running) {
      await service.startService();
    }
  }

  /// Ask the background isolate to stop itself.
  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }
}
