import 'package:flutter/material.dart';
import '../screens/welcome_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../screens/scan_screen.dart';
import '../screens/join_group_screen.dart';
import '../screens/home_screen.dart';
import '../screens/create_group_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/call_screen.dart';
import '../screens/voice_message_screen.dart';

class AppRoutes {
  static Map<String, dynamic> _safeArgs(RouteSettings settings) {
    final args = settings.arguments;
    if (args is Map<String, dynamic>) return args;
    return const <String, dynamic>{};
  }

  static Route<dynamic> generate(RouteSettings settings) {
    switch (settings.name) {
      case '/welcome':
        return _page(const WelcomeScreen());
      case '/login':
        return _page(const LoginScreen());
      case '/register':
        return _page(const RegisterScreen());
      case '/scan':
        return _page(const ScanScreen());
      case '/join-group':
        final args = _safeArgs(settings);
        if (args.isEmpty) return _page(const WelcomeScreen());
        return _page(JoinGroupScreen(inviteData: args));
      case '/home':
        return _page(const HomeScreen());
      case '/create-group':
        return _page(const CreateGroupScreen());
      case '/settings':
        return _page(const SettingsScreen());
      case '/call':
        final args = _safeArgs(settings);
        final userId = args['userId'];
        final name = args['name'];
        final isVideo = args['isVideo'];
        final isIncoming = args['isIncoming'] == true;
        if (userId is! String || name is! String || isVideo is! bool) {
          return _page(const HomeScreen());
        }
        return _page(CallScreen(
          targetUserId: userId,
          targetName: name,
          isVideo: isVideo,
          isIncoming: isIncoming,
        ));
      case '/voice-message':
        final args = _safeArgs(settings);
        final userId = args['userId'];
        final name = args['name'];
        final groupId = args['groupId'];
        if (userId is! String || name is! String || groupId is! String) {
          return _page(const HomeScreen());
        }
        return _page(VoiceMessageScreen(
          targetUserId: userId,
          targetName: name,
          groupId: groupId,
        ));
      default:
        return _page(const WelcomeScreen());
    }
  }

  static MaterialPageRoute _page(Widget child) {
    return MaterialPageRoute(builder: (_) => child);
  }
}
