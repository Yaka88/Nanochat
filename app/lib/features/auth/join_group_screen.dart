import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_store.dart';
import '../../core/utils/error_utils.dart';
import '../home/home_screen.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({Key? key}) : super(key: key);

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _invitePayloadController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _nameInGroupController = TextEditingController();
  final TextEditingController _deviceIdController = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _initDeviceId();
  }

  Future<void> _initDeviceId() async {
    final deviceId = await SessionStore.getDeviceId();
    if (!mounted) return;
    _deviceIdController.text =
        (deviceId != null && deviceId.isNotEmpty) ? deviceId : const Uuid().v4();
  }

  @override
  void dispose() {
    _invitePayloadController.dispose();
    _nicknameController.dispose();
    _nameInGroupController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  Future<void> _scanQrPayload() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _InviteQrScannerScreen()),
    );

    if (!mounted || raw == null || raw.trim().isEmpty) {
      return;
    }

    setState(() {
      _invitePayloadController.text = raw.trim();
    });
  }

  Future<void> _joinGroup() async {
    setState(() => _loading = true);

    try {
      final invite = _parseInvite(_invitePayloadController.text);
      final nickname = _nicknameController.text.trim();
      final nameInGroup = _nameInGroupController.text.trim();
      final deviceId = _deviceIdController.text.trim();

      if (nickname.isEmpty || nameInGroup.isEmpty || deviceId.isEmpty) {
        throw Exception('请填写完整信息');
      }

      final response = await _apiClient.joinGroupByCode(
        invite: invite,
        nickname: nickname,
        nameInGroup: nameInGroup,
        deviceId: deviceId,
      );

      final token = (response['token'] ?? '').toString();
      final user = Map<String, dynamic>.from(response['user'] as Map? ?? {});
      final userId = (user['id'] ?? '').toString();
      final group = Map<String, dynamic>.from(response['group'] as Map? ?? {});
      final groupId = (group['id'] ?? '').toString();

      if (token.isEmpty || userId.isEmpty) {
        throw Exception('入群成功但会话信息不完整');
      }

      await SessionStore.saveSession(
        token: token,
        userId: userId,
        lastGroupId: groupId,
        deviceId: deviceId,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (error) {
      final message = extractErrorMessage(error);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('入群失败: $message')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Map<String, dynamic> _parseInvite(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map) {
      throw Exception('邀请码格式不正确');
    }

    final invite = Map<String, dynamic>.from(value);
    if (invite['type']?.toString() != 'nanochat_invite') {
      throw Exception('二维码类型不支持');
    }

    const requiredKeys = [
      'group_id',
      'group_name',
      'inviter_name',
      'invite_code',
      'timestamp',
      'signature',
    ];

    for (final key in requiredKeys) {
      final item = invite[key];
      if (item == null || item.toString().isEmpty) {
        throw Exception('二维码缺少字段: $key');
      }
    }

    return invite;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码加入家庭')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ElevatedButton.icon(
            onPressed: _loading ? null : _scanQrPayload,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('打开摄像头扫码'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _invitePayloadController,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '邀请二维码内容（JSON）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nicknameController,
            decoration: const InputDecoration(
              labelText: '昵称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameInGroupController,
            decoration: const InputDecoration(
              labelText: '家庭称呼（如：妈妈）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _deviceIdController,
            decoration: const InputDecoration(
              labelText: '设备标识 Device ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loading ? null : _joinGroup,
            child: Text(_loading ? '入群中...' : '确认加入家庭'),
          ),
        ],
      ),
    );
  }
}

class _InviteQrScannerScreen extends StatefulWidget {
  const _InviteQrScannerScreen();

  @override
  State<_InviteQrScannerScreen> createState() => _InviteQrScannerScreenState();
}

class _InviteQrScannerScreenState extends State<_InviteQrScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描邀请码')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          if (capture.barcodes.isEmpty) {
            return;
          }
          final code = capture.barcodes.first.rawValue;
          if (code == null || code.trim().isEmpty) {
            return;
          }

          _handled = true;
          Navigator.pop(context, code.trim());
        },
      ),
    );
  }
}
