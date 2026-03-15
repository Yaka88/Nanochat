import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/theme.dart';
import 'app/routes.dart';
import 'core/auth_provider.dart';
import 'core/socket_provider.dart';
import 'core/l10n.dart';
import 'core/background_service.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/call_screen.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundServiceManager.initialize();
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
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event!.event == Event.actionCallAccept) {
        final body = event.body as Map<dynamic, dynamic>;
        final extra = body['extra'] as Map<dynamic, dynamic>? ?? {};
        final callerUserId = extra['callerUserId']?.toString() ?? '';
        final isVideo = extra['isVideo'] == true || extra['isVideo'] == 'true';
        final callerName = body['nameCaller']?.toString() ?? 'Unknown';

        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => CallScreen(
            targetUserId: callerUserId,
            targetName: callerName,
            isVideo: isVideo,
            isIncoming: true,
          ),
        ));
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
