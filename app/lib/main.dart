import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/theme.dart';
import 'app/routes.dart';
import 'core/auth_provider.dart';
import 'core/socket_provider.dart';
import 'core/l10n.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NanochatApp());
}

class NanochatApp extends StatelessWidget {
  const NanochatApp({super.key});

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
