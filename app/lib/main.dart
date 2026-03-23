import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/theme.dart';
import 'app/routes.dart';
import 'core/auth_provider.dart';
import 'core/socket_provider.dart';
import 'core/l10n.dart';
import 'core/background_service.dart';
import 'core/callkit_foreground.dart';
import 'core/push_service.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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

  try {
    await Permission.ignoreBatteryOptimizations.request();
  } catch (e) {
    debugPrint('[Main] Battery optimization permission failed: $e');
  }

  try {
    await BackgroundServiceManager.initialize();
  } catch (e) {
    debugPrint('[Main] Background service init failed: $e');
  }

  // Initialize push notification service (FCM token registration)
  if (firebaseReady) {
    try {
      await PushService.initialize();
    } catch (e) {
      debugPrint('[Main] Push service init failed: $e');
    }
  }

  runApp(const NanochatApp());
}

class NanochatApp extends StatefulWidget {
  const NanochatApp({super.key});

  @override
  State<NanochatApp> createState() => _NanochatAppState();
}

class _NanochatAppState extends State<NanochatApp> {
  @override
  void initState() {
    super.initState();
    _setupCallKitListener();
  }

  void _setupCallKitListener() {
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;

      if (event.event == Event.actionCallAccept) {
        await CallkitForeground.tryBringToForeground();

        final body = event.body as Map<dynamic, dynamic>;
        final extra = body['extra'] as Map<dynamic, dynamic>? ?? {};
        final callerUserId = extra['callerUserId']?.toString() ?? '';
        final isVideo = extra['isVideo'] == true || extra['isVideo'] == 'true';
        final callerName = body['nameCaller']?.toString() ?? 'Unknown';

        // Avoid pushing a duplicate CallScreen if one is already displayed
        final nav = navigatorKey.currentState;
        if (nav == null) return;

        // Check if the current route is already a CallScreen
        bool isOnCallScreen = false;
        nav.popUntil((route) {
          if (route.settings.name == '/call') {
            isOnCallScreen = true;
          }
          return true; // don't actually pop
        });
        if (isOnCallScreen) return;

        nav.pushNamed('/call', arguments: {
          'userId': callerUserId,
          'name': callerName,
          'isVideo': isVideo,
          'isIncoming': true,
        });
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
