import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api.dart';
import 'storage.dart';

class SocketProvider extends ChangeNotifier {
  io.Socket? _socket;
  final Map<String, bool> _onlineStatus = {};
  bool _hasPresenceSnapshot = false;
  List<Map<String, dynamic>>? _cachedIceServers;
  DateTime? _iceServersCachedAt;

  bool isUserOnline(String userId) => _onlineStatus[userId] ?? !_hasPresenceSnapshot;

  /// Ensure there is an active socket connection before call signaling.
  /// Returns true when connected within timeout, otherwise false.
  Future<bool> ensureConnected({Duration timeout = const Duration(seconds: 20)}) async {
    if (isConnected) return true;

    if (_socket == null) {
      await connect();
    } else {
      _socket!.connect();
    }
    if (isConnected) return true;

    final startedAt = DateTime.now();
    var tick = 0;
    while (DateTime.now().difference(startedAt) < timeout) {
      await Future.delayed(const Duration(milliseconds: 250));
      if (isConnected) return true;

      tick++;
      // Retry connect periodically while waiting.
      if (tick % 8 == 0) {
        if (_socket == null) {
          await connect();
        } else if (!(_socket!.connected)) {
          _socket!.connect();
        }
      }
    }

    return false;
  }

  bool get isConnected => _socket?.connected == true;

  Future<void> connect() async {
    if (_socket?.connected == true) return;

    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }

    _onlineStatus.clear();
    _hasPresenceSnapshot = false;
    _cachedIceServers = null;

    final token = await LocalStorage.getToken();
    final deviceId = await LocalStorage.getOrCreateDeviceId();
    if (token == null) return;

    _socket = io.io(
      Api.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({'Authorization': 'Bearer $token', 'x-device-id': deviceId})
          .setAuth({'token': token, 'deviceId': deviceId})
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[WS] Connected');
      // Refresh group rooms on every reconnect so presence stays in sync
      _socket!.emit('groups:refresh');
    });
    _socket!.onDisconnect((_) => debugPrint('[WS] Disconnected'));

    _socket!.on('presence:snapshot', (data) {
      final ids = (data is Map ? data['onlineUserIds'] : null) as List<dynamic>?;
      if (ids == null) return;
      _hasPresenceSnapshot = true;

      // Build the set of currently-online user IDs from the snapshot
      final snapshotOnline = <String>{};
      for (final id in ids) {
        final userId = id?.toString();
        if (userId == null || userId.isEmpty) continue;
        snapshotOnline.add(userId);
      }

      // Mark users not in the snapshot as offline,
      // mark users in the snapshot as online.
      final allKnown = _onlineStatus.keys.toList();
      for (final uid in allKnown) {
        _onlineStatus[uid] = snapshotOnline.contains(uid);
      }
      // Also add any new users from the snapshot
      for (final uid in snapshotOnline) {
        _onlineStatus[uid] = true;
      }

      notifyListeners();
    });

    _socket!.on('user:online', (data) {
      _onlineStatus[data['userId']] = true;
      notifyListeners();
    });

    _socket!.on('user:offline', (data) {
      _onlineStatus[data['userId']] = false;
      notifyListeners();
    });

    // Call events
    _socket!.on('call:request', (data) => _onCallRequestCtrl.add(data));
    _socket!.on('call:accept', (data) => _onCallAcceptedCtrl.add(data));
    _socket!.on('call:reject', (data) => _onCallRejectedCtrl.add(data));
    _socket!.on('call:end', (data) => _onCallEndedCtrl.add(data));
    _socket!.on('call:error', (data) => _onCallErrorCtrl.add(data));

    // WebRTC signaling
    _socket!.on('signal:offer', (data) => _onSignalOfferCtrl.add(data));
    _socket!.on('signal:answer', (data) => _onSignalAnswerCtrl.add(data));
    _socket!.on('signal:ice', (data) => _onSignalIceCtrl.add(data));

    // Voice message
    _socket!.on('message:new', (data) {
      _onNewMessageCtrl.add(data);
      notifyListeners();
    });

    // Force Logout
    _socket!.on('force_logout', (data) {
      _onForceLogoutCtrl.add(data);
      disconnect();
    });
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _onlineStatus.clear();
    _hasPresenceSnapshot = false;
    _cachedIceServers = null;
    _iceServersCachedAt = null;
  }

  /// Emit explicit logout event so the server marks this user offline.
  /// Waits briefly so the event is sent before the socket is disposed.
  Future<void> emitLogout() async {
    _socket?.emit('user:logout');
    // Give the event a moment to reach the server before disconnect
    await Future.delayed(const Duration(milliseconds: 300));
  }

  /// Force a full reconnection (dispose old socket, create new one).
  /// Use after login, registration, or group join to ensure fresh state.
  Future<void> reconnect() async {
    disconnect();
    await ensureConnected();
  }

  /// Tell the server we joined a new group so it adds us to the room.
  void notifyGroupJoined(String groupId) {
    _socket?.emit('group:joined', {'groupId': groupId});
  }

  /// Ask the server to refresh all group rooms (e.g., after app resume).
  void refreshGroups() {
    _socket?.emit('groups:refresh');
  }

  /// Fetch TURN/STUN ICE servers from the server.
  /// Returns cached value if available and not expired; otherwise queries via socket ack.
  Future<List<Map<String, dynamic>>> getIceServers() async {
    // Invalidate cache after 20 hours (TURN credentials have 24h TTL)
    if (_cachedIceServers != null && _iceServersCachedAt != null) {
      final age = DateTime.now().difference(_iceServersCachedAt!);
      if (age.inHours >= 20) {
        _cachedIceServers = null;
        _iceServersCachedAt = null;
      }
    }
    if (_cachedIceServers != null) return _cachedIceServers!;

    final completer = Completer<List<Map<String, dynamic>>>();

    if (_socket?.connected != true) {
      // Fallback: public STUN only
      return [
        {'urls': 'stun:chat.bluelaser.cn:3478'},
        {'urls': 'stun:stun.l.google.com:19302'},
      ];
    }

    // Use ack callback
    _socket!.emitWithAck('get:ice-servers', {}, ack: (data) {
      if (data is Map && data['iceServers'] is List) {
        final servers = (data['iceServers'] as List)
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList();
        _cachedIceServers = servers;
        _iceServersCachedAt = DateTime.now();
        if (!completer.isCompleted) completer.complete(servers);
      } else {
        if (!completer.isCompleted) {
          completer.complete([
            {'urls': 'stun:chat.bluelaser.cn:3478'},
            {'urls': 'stun:stun.l.google.com:19302'},
          ]);
        }
      }
    });

    // Also listen for non-ack response as fallback
    _socket!.once('ice-servers', (data) {
      if (completer.isCompleted) return;
      if (data is Map && data['iceServers'] is List) {
        final servers = (data['iceServers'] as List)
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList();
        _cachedIceServers = servers;
        _iceServersCachedAt = DateTime.now();
        completer.complete(servers);
      }
    });

    // Timeout after 5s
    Future.delayed(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        completer.complete([
          {'urls': 'stun:chat.bluelaser.cn:3478'},
          {'urls': 'stun:stun.l.google.com:19302'},
        ]);
      }
    });

    return completer.future;
  }

  void emit(String event, dynamic data) => _socket?.emit(event, data);

  final _onCallRequestCtrl = StreamController<dynamic>.broadcast();
  final _onCallAcceptedCtrl = StreamController<dynamic>.broadcast();
  final _onCallRejectedCtrl = StreamController<dynamic>.broadcast();
  final _onCallEndedCtrl = StreamController<dynamic>.broadcast();
  final _onCallErrorCtrl = StreamController<dynamic>.broadcast();
  final _onSignalOfferCtrl = StreamController<dynamic>.broadcast();
  final _onSignalAnswerCtrl = StreamController<dynamic>.broadcast();
  final _onSignalIceCtrl = StreamController<dynamic>.broadcast();
  final _onNewMessageCtrl = StreamController<dynamic>.broadcast();
  final _onForceLogoutCtrl = StreamController<dynamic>.broadcast();

  Stream<dynamic> get onCallRequestStream => _onCallRequestCtrl.stream;
  Stream<dynamic> get onCallAcceptedStream => _onCallAcceptedCtrl.stream;
  Stream<dynamic> get onCallRejectedStream => _onCallRejectedCtrl.stream;
  Stream<dynamic> get onCallEndedStream => _onCallEndedCtrl.stream;
  Stream<dynamic> get onCallErrorStream => _onCallErrorCtrl.stream;
  Stream<dynamic> get onSignalOfferStream => _onSignalOfferCtrl.stream;
  Stream<dynamic> get onSignalAnswerStream => _onSignalAnswerCtrl.stream;
  Stream<dynamic> get onSignalIceStream => _onSignalIceCtrl.stream;
  Stream<dynamic> get onNewMessageStream => _onNewMessageCtrl.stream;
  Stream<dynamic> get onForceLogoutStream => _onForceLogoutCtrl.stream;

  void updateBulkOnlineStatus(List<dynamic> members) {
    for (final m in members) {
      if (m is! Map) continue;
      final userId = (m['userId'] ?? m['id'])?.toString();
      if (userId == null || userId.isEmpty) continue;
      // Only use API data to seed users we haven't heard from via WebSocket.
      // If we already have a status for this user, don't overwrite it;
      // the WebSocket presence events are more authoritative.
      if (!_onlineStatus.containsKey(userId)) {
        final apiOnline = m['isOnline'] == true;
        // Before first realtime snapshot arrives, avoid seeding 'false'
        // from possibly stale API data to prevent false offline UI state.
        if (apiOnline || _hasPresenceSnapshot) {
          _onlineStatus[userId] = apiOnline;
        }
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _onCallRequestCtrl.close();
    _onCallAcceptedCtrl.close();
    _onCallRejectedCtrl.close();
    _onCallEndedCtrl.close();
    _onCallErrorCtrl.close();
    _onSignalOfferCtrl.close();
    _onSignalAnswerCtrl.close();
    _onSignalIceCtrl.close();
    _onNewMessageCtrl.close();
    _onForceLogoutCtrl.close();
    super.dispose();
  }
}
