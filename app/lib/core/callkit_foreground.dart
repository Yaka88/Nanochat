import 'package:flutter/services.dart';

class CallkitForeground {
  static const MethodChannel _channel = MethodChannel('flutter_callkit_incoming');

  static Future<void> tryBringToForeground() async {
    try {
      await _channel.invokeMethod('backToForeground');
    } catch (_) {
      // Not supported on current plugin/platform, ignore safely.
    }
  }
}
