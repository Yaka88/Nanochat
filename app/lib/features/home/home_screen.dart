import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../core/api/api_client.dart';
import '../../core/api/socket_service.dart';
import '../../core/auth/session_store.dart';
import '../../core/utils/error_utils.dart';
import '../auth/login_screen.dart';
import '../call/call_screen.dart';
import '../voice_message/voice_message_screen.dart';

class GroupMember {
  final String id;
  final String displayName;
  final bool isOnline;
  
  GroupMember({
    required this.id,
    required this.displayName,
    required this.isOnline,
  });

  GroupMember copyWith({bool? isOnline}) {
    return GroupMember(
      id: id,
      displayName: displayName,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: (json['id'] ?? '').toString(),
      displayName: (json['nameInGroup'] ?? json['nickname'] ?? '').toString(),
      isOnline: json['isOnline'] == true,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiClient _apiClient = ApiClient();
  final SocketService _socketService = SocketService();

  bool _isLoading = true;
  String? _error;
  String? _groupId;
  String _groupName = 'Home';
  String? _currentUserId;
  List<GroupMember> _members = <GroupMember>[];

  @override
  void initState() {
    super.initState();
    _initializeHome();
  }

  @override
  void dispose() {
    _socketService.disconnect();
    super.dispose();
  }

  Future<void> _initializeHome() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final mePayload = await _apiClient.getMe();
      final user = Map<String, dynamic>.from(mePayload['user'] as Map? ?? {});
      final groups = (user['groups'] as List?) ?? <dynamic>[];

      if (groups.isEmpty) {
        throw Exception('当前账号尚未加入家庭');
      }

      _currentUserId = user['id']?.toString();
      final lastGroupId = user['lastGroupId']?.toString();
      final localLastGroupId = await SessionStore.getLastGroupId();
      final selectedGroupId = _pickGroupId(
        groups: groups,
        preferredIds: [lastGroupId, localLastGroupId],
      );

      final selectedGroup = groups.firstWhere(
        (entry) =>
            (entry as Map<String, dynamic>)['id']?.toString() == selectedGroupId,
        orElse: () => groups.first,
      ) as Map<String, dynamic>;

      _groupId = selectedGroupId;
      _groupName = (selectedGroup['name'] ?? 'Home').toString();
      await SessionStore.setLastGroupId(selectedGroupId);

      final membersJson = await _apiClient.getGroupMembers(selectedGroupId);
      _members = membersJson.map(GroupMember.fromJson).toList();

      _bindSocketHandlers();
      _socketService.connect();
    } catch (error) {
      _error = extractErrorMessage(error);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _pickGroupId({
    required List<dynamic> groups,
    required List<String?> preferredIds,
  }) {
    for (final preferred in preferredIds) {
      if (preferred == null || preferred.isEmpty) {
        continue;
      }

      final exists = groups.any((entry) {
        final group = entry as Map<String, dynamic>;
        return group['id']?.toString() == preferred;
      });

      if (exists) {
        return preferred;
      }
    }

    return (groups.first as Map<String, dynamic>)['id'].toString();
  }

  void _bindSocketHandlers() {
    _socketService.setHandlers(
      onUserOnline: (data) => _updateOnlineState(data, true),
      onUserOffline: (data) => _updateOnlineState(data, false),
      onCallIncoming: _handleIncomingCall,
      onCallRejected: (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('对方已拒绝通话')),
        );
      },
      onCallEnded: (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通话已结束')),
        );
      },
      onCallError: (data) {
        if (!mounted) return;
        final message = (data['message'] ?? '通话失败').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      },
    );
  }

  void _updateOnlineState(Map<String, dynamic> data, bool online) {
    final incomingGroupId = data['groupId']?.toString();
    final userId = data['userId']?.toString();

    if (incomingGroupId != _groupId || userId == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _members = _members
          .map((member) =>
              member.id == userId ? member.copyWith(isOnline: online) : member)
          .toList();
    });
  }

  Future<void> _handleIncomingCall(Map<String, dynamic> data) async {
    if (!mounted) {
      return;
    }

    final callerId = data['callerId']?.toString();
    final callType = data['callType']?.toString() ?? 'voice';
    final groupId = data['groupId']?.toString() ?? _groupId;
    if (callerId == null || groupId == null) {
      return;
    }

    final callerName = _members
        .firstWhere(
          (member) => member.id == callerId,
          orElse: () => GroupMember(
            id: callerId,
            displayName: '家庭成员',
            isOnline: true,
          ),
        )
        .displayName;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('来电提醒'),
        content: Text('$callerName 发起了${callType == 'video' ? '视频' : '语音'}通话'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('拒绝'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('接听'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      _socketService.acceptCall(callerId: callerId);
      if (!mounted) {
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            isVideo: callType == 'video',
            name: callerName,
            targetUserId: callerId,
            groupId: groupId,
            socketService: _socketService,
          ),
        ),
      );
      return;
    }

    _socketService.rejectCall(callerId: callerId, reason: 'busy');
  }

  void _startCall(GroupMember member, bool isVideo) {
    if (_groupId == null) {
      return;
    }

    _socketService.requestCall(
      targetUserId: member.id,
      groupId: _groupId!,
      callType: isVideo ? 'video' : 'voice',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          isVideo: isVideo,
          name: member.displayName,
          targetUserId: member.id,
          groupId: _groupId!,
          socketService: _socketService,
        ),
      ),
    );
  }

  Future<void> _showInvitePayload() async {
    if (_groupId == null) {
      return;
    }

    try {
      final response = await _apiClient.getGroupInvite(_groupId!);
      final invite = Map<String, dynamic>.from(response['invite'] as Map? ?? {});
      final inviteText = const JsonEncoder.withIndent('  ').convert(invite);

      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('邀请二维码内容'),
            content: SingleChildScrollView(
              child: SelectableText(inviteText),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: inviteText));
                  if (!mounted) return;
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('邀请码已复制')),
                  );
                },
                child: const Text('复制'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      final message = extractErrorMessage(error);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成邀请失败: $message')),
      );
    }
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    _socketService.disconnect();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nanochat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _initializeHome,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Nanochat [$_groupName ▼]'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, size: 36),
            onPressed: _logout,
          )
        ],
      ),
      body: ListView.separated(
        itemCount: _members.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1),
        itemBuilder: (context, index) {
          if (index == _members.length) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: _showInvitePayload,
                icon: const Icon(Icons.add, size: 32),
                label: const Text('➕ 邀请新成员'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 80),
                  backgroundColor: Colors.blueGrey,
                  textStyle: const TextStyle(fontSize: 24),
                ),
              ),
            );
          }

          final m = _members[index];
          final isSelf = m.id == _currentUserId;
          final canCall = m.isOnline && !isSelf;
          
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(m.displayName, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    Icon(
                      m.isOnline ? Icons.circle : Icons.circle_outlined,
                      color: m.isOnline ? Colors.green : Colors.grey,
                      size: 24,
                    ),
                    Text(
                      isSelf
                          ? ' 我'
                          : (m.isOnline ? ' 在线' : ' 离线'),
                      style: TextStyle(
                        fontSize: 24,
                        color: isSelf
                            ? Colors.blue
                            : (m.isOnline ? Colors.green : Colors.grey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 📹 视频
                    ElevatedButton(
                      onPressed: canCall ? () => _startCall(m, true) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canCall ? Colors.blue : Colors.grey,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.videocam, size: 36, color: Colors.white),
                          Text('视频', style: TextStyle(fontSize: 20, color: Colors.white)),
                        ],
                      ),
                    ),
                    
                    // 📞 语音
                    ElevatedButton(
                      onPressed: canCall ? () => _startCall(m, false) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canCall ? Colors.green : Colors.grey,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.phone, size: 36, color: Colors.white),
                          Text('语音', style: TextStyle(fontSize: 20, color: Colors.white)),
                        ],
                      ),
                    ),
                    
                    // 🎤 留言
                    ElevatedButton(
                      onPressed: isSelf
                          ? null
                          : () {
                              if (_groupId == null) {
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VoiceMessageScreen(
                                    name: m.displayName,
                                    receiverUserId: m.id,
                                    groupId: _groupId!,
                                  ),
                                ),
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelf ? Colors.grey : Colors.orange,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.mic, size: 36, color: Colors.white),
                          Text('留言', style: TextStyle(fontSize: 20, color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
