import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized permission helper for camera/mic access.
class Permissions {
  Permissions._();

  /// Request camera + microphone permissions for video/voice calls.
  /// Returns `true` if both are granted.
  static Future<bool> requestCallPermissions(BuildContext context,
      {required bool isVideo}) async {
    final permissions = <Permission>[Permission.microphone];
    if (isVideo) permissions.add(Permission.camera);

    final statuses = await permissions.request();

    final micGranted = statuses[Permission.microphone]?.isGranted ?? true;
    final camGranted =
        !isVideo || (statuses[Permission.camera]?.isGranted ?? true);

    if (!micGranted || !camGranted) {
      if (context.mounted) {
        _showDeniedDialog(context, isVideo ? '摄像头和麦克风' : '麦克风');
      }
      return false;
    }
    return true;
  }

  /// Request camera permission for QR scanner.
  static Future<bool> requestCameraPermission(BuildContext context) async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (context.mounted) {
        _showDeniedDialog(context, '摄像头');
      }
      return false;
    }
    return true;
  }

  static void _showDeniedDialog(BuildContext context, String permName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('权限被拒绝'),
        content: Text('请在系统设置中允许Nanochat访问$permName。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}
