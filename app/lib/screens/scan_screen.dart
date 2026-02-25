import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/l10n.dart';
import '../core/permissions.dart';

/// QR code scanner for joining a family group
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _scanned = false;
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final granted = await Permissions.requestCameraPermission(context);
    if (mounted) setState(() => _permissionGranted = granted);
    if (!granted && mounted) Navigator.pop(context);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    try {
      final data = jsonDecode(barcode!.rawValue!) as Map<String, dynamic>;
      if (data['type'] != 'nanochat_invite') return;

      // Check expiry
      final expiresRaw = data['expires_at'] ?? data['expiresAt'];
      if (expiresRaw != null) {
        final expires = DateTime.fromMillisecondsSinceEpoch(
        (expiresRaw as num).toInt() * 1000);
        if (DateTime.now().isAfter(expires)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppL10n.t(context, 'qr_expired'),
                style: const TextStyle(fontSize: 18))),
          );
          return;
        }
      }

      _scanned = true;
      Navigator.pushReplacementNamed(context, '/join-group', arguments: data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    return Scaffold(
      appBar: AppBar(title: Text(t('scan_join'))),
      body: !_permissionGranted
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.primary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Text(
              t('scan_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
            ),
          ),
        ],
      ),
    );
  }
}
