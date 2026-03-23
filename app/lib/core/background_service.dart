import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'callkit_foreground.dart';
import 'storage.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final token = await LocalStorage.getToken();
  final deviceId = await LocalStorage.getOrCreateDeviceId();
  if (token == null) {
    service.stopSelf();
    return;
  }

  final socket = io.io(
    Api.socketUrl,
    io.OptionBuilder()
        .setTransports(['websocket'])
        .setExtraHeaders({'Authorization': 'Bearer $token', 'x-device-id': deviceId})
        .setAuth({'token': token, 'deviceId': deviceId})
        .enableReconnection()
        .setReconnectionAttempts(99999)
        .setReconnectionDelay(5000)
        .enableAutoConnect()
        .build(),
  );

  socket.onConnect((_) {
    debugPrint('[Background WS] Connected');
  });

  socket.on('call:request', (data) async {
    final callerName = (data['callerName'] ?? 'Unknown') as String;
    final callerUserId = (data['callerUserId'] ?? '') as String;
    final isVideo = (data['isVideo'] ?? true) as bool;
    
    // Show CallKit
    final uuid = const Uuid().v4();
    final callKitParams = CallKitParams(
      id: uuid,
      nameCaller: callerName,
      appName: 'Nanochat',
      avatar: 'https://i.pravatar.cc/100', // Optional
      handle: 'Incoming Call',
      type: isVideo ? 1 : 0, // 0 - Audio, 1 - Video
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
  });

  socket.on('call:end', (data) async {
    // If the caller hangs up before we answer, dismiss CallKit
    // Sadly, FlutterCallkitIncoming doesn't have an easy way to end all ringing calls except by ID,
    // so we'll just end all calls to be safe.
    await FlutterCallkitIncoming.endAllCalls();
  });

  // Handle Callkit actions in background
  final callKitSub = FlutterCallkitIncoming.onEvent.listen((event) async {
    switch (event!.event) {
      case Event.actionCallAccept:
        final callerUserId = event.body['extra']['callerUserId'];
        await CallkitForeground.tryBringToForeground();
        socket.emit('call:accept', {'targetUserId': callerUserId});
        await FlutterCallkitIncoming.endAllCalls();
        break;
      case Event.actionCallDecline:
        final callerUserId = event.body['extra']['callerUserId'];
        socket.emit('call:reject', {'targetUserId': callerUserId});
        break;
      default:
        break;
    }
  });

  StreamSubscription<dynamic>? stopSub;

  // When the call was answered on another device, stop ringing here
  socket.on('call:answered_elsewhere', (_) async {
    await FlutterCallkitIncoming.endAllCalls();
  });

  socket.on('force_logout', (_) {
    callKitSub.cancel();
    stopSub?.cancel();
    socket.dispose();
    service.stopSelf();
  });

  stopSub = service.on('stopService').listen((event) {
    callKitSub.cancel();
    stopSub?.cancel();
    socket.dispose();
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

    if (DateTime.now().year > 2000) { // Just a sanity check to run async
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

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
