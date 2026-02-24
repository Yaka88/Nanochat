import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/api.dart';
import '../core/auth_provider.dart';
import '../core/socket_provider.dart';
import '../core/storage.dart';
import '../core/l10n.dart';
import '../models/group.dart';
import '../widgets/incoming_call_dialog.dart';
import '../widgets/member_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Group> _groups = [];
  List<GroupMember> _members = [];
  Group? _currentGroup;
  bool _loading = true;
  Timer? _ringTimer;
  bool _incomingDialogOpen = false;
  String? _pendingCallerUserId;
  bool _incomingHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupSocketHandlers();
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopIncomingRing();
    final socket = context.read<SocketProvider>();
    socket.onCallRequest = null;
    socket.onCallEnded = null;
    super.dispose();
  }

  void _startIncomingRing() {
    _stopIncomingRing();
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
    _ringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    });
  }

  void _stopIncomingRing() {
    _ringTimer?.cancel();
    _ringTimer = null;
  }

  void _setupSocketHandlers() {
    final socket = context.read<SocketProvider>();
    socket.onCallRequest = (data) {
      if (!mounted) return;
      if (_incomingDialogOpen) return;
      final callerName = (data['callerName'] ?? data['name'] ?? 'Unknown') as String;
      final callerUserId = (data['callerUserId'] ?? data['userId'] ?? '') as String;
      final isVideo = (data['isVideo'] ?? true) as bool;
      if (callerUserId.isEmpty) return;

      _incomingDialogOpen = true;
      _pendingCallerUserId = callerUserId;
      _incomingHandled = false;
      _startIncomingRing();

      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => IncomingCallDialog(
            callerName: callerName,
            isVideo: isVideo,
            onAccept: () {
              _incomingHandled = true;
              _stopIncomingRing();
              // call:accept is emitted by CallScreen after media init completes
              Navigator.of(context).pop();
              _incomingDialogOpen = false;
              _pendingCallerUserId = null;
              Navigator.pushNamed(context, '/call', arguments: {
                'userId': callerUserId,
                'name': callerName,
                'isVideo': isVideo,
                'isIncoming': true,
              });
            },
            onReject: () {
              _incomingHandled = true;
              _stopIncomingRing();
              socket.emit('call:reject', {'targetUserId': callerUserId});
              Navigator.of(context).pop();
              _incomingDialogOpen = false;
              _pendingCallerUserId = null;
            },
          ),
        ),
      ).then((_) {
        if (!_incomingHandled && _pendingCallerUserId != null) {
          socket.emit('call:reject', {'targetUserId': _pendingCallerUserId});
        }
        _stopIncomingRing();
        _incomingDialogOpen = false;
        _pendingCallerUserId = null;
        _incomingHandled = false;
      });
    };

    socket.onCallEnded = (data) {
      final fromUserId = data['fromUserId']?.toString();
      if (!_incomingDialogOpen || fromUserId == null) return;
      if (fromUserId != _pendingCallerUserId) return;

      _incomingHandled = true;
      _stopIncomingRing();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _incomingDialogOpen = false;
      _pendingCallerUserId = null;
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final socket = context.read<SocketProvider>();
    if (state == AppLifecycleState.resumed) {
      if (socket.isConnected) {
        // Already connected: just refresh group rooms and members
        socket.refreshGroups();
      } else {
        socket.connect();
      }
      _loadMembers();
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final res = await Api.getGroups();
      final groups = (res['groups'] as List)
          .map((g) => Group.fromJson(g))
          .toList();
      setState(() => _groups = groups);

      // Pick last group or first
      final lastId = await LocalStorage.getLastGroupId();
      final current = groups.isEmpty
          ? null
          : groups.firstWhere((g) => g.id == lastId,
              orElse: () => groups.first);
      setState(() => _currentGroup = current);

      // Connect WebSocket early so presence:snapshot arrives before UI renders
      if (mounted) {
        final socket = context.read<SocketProvider>();
        if (socket.isConnected) {
          socket.refreshGroups();
        } else {
          await socket.connect();
        }
      }

      if (current != null) {
        await LocalStorage.setLastGroupId(current.id);
        await _loadMembers();
      }
    } catch (e) {
      debugPrint('Load error: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _loadMembers() async {
    if (_currentGroup == null) return;
    try {
      final res = await Api.getGroupMembers(_currentGroup!.id);
      final rawMembers = (res['members'] as List?) ?? const [];
      final members = rawMembers
          .whereType<Map>()
          .map((m) => GroupMember.fromJson(Map<String, dynamic>.from(m)))
          .toList();

      // Update online status cache
      if (mounted) {
        context.read<SocketProvider>().updateBulkOnlineStatus(rawMembers);
      }

      final myId = context.read<AuthProvider>().user?.id;
      members.removeWhere((m) => m.userId == myId);

      setState(() => _members = members);
    } catch (e) {
      debugPrint('Members error: $e');
    }
  }

  void _switchGroup(Group group) async {
    setState(() => _currentGroup = group);
    await LocalStorage.setLastGroupId(group.id);
    await _loadMembers();
  }

  void _onVideoCall(GroupMember m) {
    Navigator.pushNamed(context, '/call', arguments: {
      'userId': m.userId,
      'name': m.nameInGroup,
      'isVideo': true,
      'isIncoming': false,
    });
  }

  void _onVoiceCall(GroupMember m) {
    Navigator.pushNamed(context, '/call', arguments: {
      'userId': m.userId,
      'name': m.nameInGroup,
      'isVideo': false,
      'isIncoming': false,
    });
  }

  void _onMessage(GroupMember m) {
    Navigator.pushNamed(context, '/voice-message', arguments: {
      'userId': m.userId,
      'name': m.nameInGroup,
      'groupId': _currentGroup!.id,
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    final auth = context.watch<AuthProvider>();
    final socket = context.watch<SocketProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nanochat'),
        actions: [
          if (_groups.length > 1 || _groups.isNotEmpty)
            _GroupDropdown(
              groups: _groups,
              current: _currentGroup,
              onChanged: _switchGroup,
            ),
          IconButton(
            icon: const Icon(Icons.settings, size: 28),
            tooltip: t('settings'),
            onPressed: () async {
              await Navigator.pushNamed(context, '/settings');
              _loadData();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
            ? _EmptyState(
              isHost: auth.isHost,
              isVerifiedHost: auth.isHost && (auth.user?.emailVerified ?? false),
            )
              : RefreshIndicator(
                  onRefresh: _loadMembers,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _members.length +
                        ((auth.isHost && _currentGroup != null) ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _members.length) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          child: ElevatedButton.icon(
                            onPressed: _showInviteDialog,
                            icon: const Icon(Icons.qr_code_2, size: 28),
                            label: Text(
                              AppL10n.t(context, 'share_qr'),
                              style: const TextStyle(fontSize: 20),
                            ),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 64),
                            ),
                          ),
                        );
                      }

                      final m = _members[i];
                      final online = socket.isUserOnline(m.userId);
                      return MemberCard(
                        member: m,
                        isOnline: online,
                        onVideo: online ? () => _onVideoCall(m) : null,
                        onVoice: online ? () => _onVoiceCall(m) : null,
                        onMessage: () => _onMessage(m),
                      );
                    },
                  ),
                ),
    );
  }

  void _showInviteDialog() async {
    try {
      final res = await Api.getInviteQR(_currentGroup!.id);
      final payload = (res['invite'] is Map<String, dynamic>)
          ? (res['invite'] as Map<String, dynamic>)
          : res;
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => _InviteDialog(
          inviteData: payload,
          groupName: _currentGroup!.name,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}

class _GroupDropdown extends StatelessWidget {
  final List<Group> groups;
  final Group? current;
  final ValueChanged<Group> onChanged;

  const _GroupDropdown({
    required this.groups,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Group>(
      onSelected: onChanged,
      offset: const Offset(0, 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(current?.name ?? '',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const Icon(Icons.arrow_drop_down, size: 28),
          ],
        ),
      ),
      itemBuilder: (_) => groups
          .map((g) => PopupMenuItem(
                value: g,
                child: Text(g.name, style: const TextStyle(fontSize: 20)),
              ))
          .toList(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isHost;
  final bool isVerifiedHost;
  const _EmptyState({required this.isHost, required this.isVerifiedHost});

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.home_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(t('no_groups'),
              style: TextStyle(fontSize: 22, color: Colors.grey[600])),
          const SizedBox(height: 24),
          if (isHost)
            ElevatedButton.icon(
              onPressed: isVerifiedHost
                  ? () => Navigator.pushNamed(context, '/create-group')
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请先完成邮箱验证，再创建家庭')),
                      );
                    },
              icon: const Icon(Icons.add, size: 28),
              label: Text(t('create_group')),
            ),
        ],
      ),
    );
  }
}

class _InviteDialog extends StatelessWidget {
  final Map<String, dynamic> inviteData;
  final String groupName;

  const _InviteDialog({required this.inviteData, required this.groupName});

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    return AlertDialog(
      title: Text(t('invite_qr'), style: const TextStyle(fontSize: 24)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: jsonEncode(inviteData),
              padding: const EdgeInsets.all(12),
              version: QrVersions.auto,
            ),
          ),
          const SizedBox(height: 12),
          Text(groupName, style: const TextStyle(fontSize: 20)),
          Text('24h', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('confirm'), style: const TextStyle(fontSize: 20)),
        ),
      ],
    );
  }
}
