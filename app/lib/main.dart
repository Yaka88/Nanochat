import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/theme.dart';
import 'app/routes.dart';
import 'core/auth_provider.dart';
import 'core/socket_provider.dart';
import 'core/l10n.dart';
import 'core/callkit_foreground.dart';
import 'core/push_service.dart';
import 'core/storage.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';

import 'package:permission_handler/permission_handler.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseReady = false;

  // Initialize Firebase first (required for FCM push notifications)
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('[Main] Firebase init failed: $e');
  }

  // Register FCM background message handler (only if Firebase is ready)
  if (firebaseReady) {
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('[Main] FCM background handler registration failed: $e');
    }
  }

  // Start UI first to avoid blocking app launch on vendor-specific permission pages.
  runApp(NanochatApp(firebaseReady: firebaseReady));
}

class NanochatApp extends StatefulWidget {
  const NanochatApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<NanochatApp> createState() => _NanochatAppState();
}

class _NanochatAppState extends State<NanochatApp> with WidgetsBindingObserver {
  AppLifecycleState? _lifecycleState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    _setupCallKitListener();
    unawaited(_bootstrapServices());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  Future<void> _waitForResumed({Duration timeout = const Duration(seconds: 8)}) async {
    if (_lifecycleState == AppLifecycleState.resumed) return;
    final started = DateTime.now();
    while (DateTime.now().difference(started) < timeout) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (_lifecycleState == AppLifecycleState.resumed) return;
    }
  }

  Future<void> _bootstrapServices() async {
    try {
      await Permission.notification.request().timeout(
        const Duration(seconds: 8),
      );
    } on TimeoutException {
      debugPrint('[Main] Notification permission request timed out');
    } catch (e) {
      debugPrint('[Main] Notification permission request failed: $e');
    }

    try {
      await Permission.ignoreBatteryOptimizations.request().timeout(
        const Duration(seconds: 8),
      );
    } on TimeoutException {
      debugPrint('[Main] Battery optimization permission request timed out');
    } catch (e) {
      debugPrint('[Main] Battery optimization permission failed: $e');
    }


    // Initialize push notification service (FCM token registration)
    if (widget.firebaseReady) {
      try {
        await PushService.initialize().timeout(const Duration(seconds: 10));
      } on TimeoutException {
        debugPrint('[Main] Push service init timed out');
      } catch (e) {
        debugPrint('[Main] Push service init failed: $e');
      }
    }
  }

  void _setupCallKitListener() {
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;

      if (event.event == Event.actionCallAccept) {
        debugPrint('[Main] CallKit actionCallAccept received');
        await CallkitForeground.tryBringToForeground();

        // Wait for the app to fully resume and widget tree to be ready.
        // On some devices, coming from deep background can take significant time.
        await Future.delayed(const Duration(milliseconds: 500));
        await _waitForResumed();

        final bodyRaw = event.body;
        final body = bodyRaw is Map ? bodyRaw : const <dynamic, dynamic>{};
        final extraRaw = body['extra'];
        final extra = extraRaw is Map ? extraRaw : const <dynamic, dynamic>{};

        var callerUserId =
            extra['callerUserId']?.toString() ?? body['callerUserId']?.toString() ?? '';
        var isVideo = extra['isVideo'] == true ||
            extra['isVideo'] == 'true' ||
            body['isVideo'] == true ||
            body['isVideo'] == 'true';
        var callerName = body['nameCaller']?.toString() ??
            extra['callerName']?.toString() ??
            'Unknown';

        if (callerUserId.isEmpty) {
          final snap = await LocalStorage.readRecentIncomingCallSnapshot();
          if (snap != null) {
            callerUserId = snap['callerUserId']?.toString() ?? '';
            callerName = snap['callerName']?.toString() ?? callerName;
            isVideo = snap['isVideo'] == true;
            debugPrint('[Main] CallKit accept: recovered caller info from local snapshot');
          }
        }

        if (callerUserId.isEmpty) {
          debugPrint('[Main] CallKit accept: callerUserId is empty, aborting');
          return;
        }

        // Wait for navigator to become available (retry up to 5 seconds)
        NavigatorState? nav;
        for (var i = 0; i < 20; i++) {
          nav = navigatorKey.currentState;
          if (nav != null) break;
          await Future.delayed(const Duration(milliseconds: 250));
        }
        if (nav == null) {
          debugPrint('[Main] CallKit accept: navigator not available after 5s, aborting');
          return;
        }

        // Check if the current route is already a CallScreen
        bool isOnCallScreen = false;
        nav.popUntil((route) {
          if (route.settings.name == '/call') {
            isOnCallScreen = true;
          }
          return true; // don't actually pop
        });
        if (isOnCallScreen) {
          debugPrint('[Main] CallKit accept: already on call screen, skipping');
          return;
        }

        try {
          final ctx = navigatorKey.currentContext;
          if (ctx != null) {
            final socket = ctx.read<SocketProvider>();
            // CRITICAL: use forceIfStale to detect dead TCP connections.
            // When app was in background, Android kills the TCP silently
            // but socket_io still reports connected=true.
            var ok = await socket.ensureConnected(
              timeout: const Duration(seconds: 12),
              forceIfStale: true,
            );
            if (!ok) {
              await socket.reconnect();
              ok = await socket.ensureConnected(timeout: const Duration(seconds: 15));
            }
            debugPrint('[Main] CallKit accept: socket ready=$ok');
          }
        } catch (e) {
          debugPrint('[Main] CallKit accept: ensureConnected failed: $e');
        }

        debugPrint('[Main] CallKit accept: navigating to /call for $callerUserId');
        nav.pushNamed('/call', arguments: {
          'userId': callerUserId,
          'name': callerName,
          'isVideo': isVideo,
          'isIncoming': true,
        });
        await LocalStorage.clearIncomingCallSnapshot();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ChangeNotifierProvider(create: (_) => SocketProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Nanochat',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            localizationsDelegates: AppL10n.delegates,
            supportedLocales: AppL10n.supportedLocales,
            home: auth.isLoading
                ? const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  )
                : (auth.isLoggedIn
                    ? const HomeScreen()
                    : const WelcomeScreen()),
            onGenerateRoute: AppRoutes.generate,
          );
        },
      ),
    );
  }
}
