import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'storage.dart';

class SocketProvider extends ChangeNotifier {
  io.Socket? _socket;
  final Map<String, bool> _onlineStatus = {};
  List<Map<String, dynamic>>? _cachedIceServers;

  bool isUserOnline(String userId) => _onlineStatus[userId] ?? false;

  bool get isConnected => _socket?.connected == true;

  Future<void> connect() async {
    if (_socket?.connected == true) return;

    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }

    _onlineStatus.clear();
    _cachedIceServers = null;

    final token = await LocalStorage.getToken();
    if (token == null) return;

    _socket = io.io(
      'https://chat.bluelaser.cn',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
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
      // Clear stale status before applying the authoritative snapshot
      _onlineStatus.clear();
      for (final id in ids) {
        final userId = id?.toString();
        if (userId == null || userId.isEmpty) continue;
        _onlineStatus[userId] = true;
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
    _socket!.on('call:request', (data) {
      _onCallRequest?.call(data);
    });

    _socket!.on('call:accept', (data) {
      _onCallAccepted?.call(data);
    });

    _socket!.on('call:reject', (data) {
      _onCallRejected?.call(data);
    });

    _socket!.on('call:end', (data) {
      _onCallEnded?.call(data);
    });

    _socket!.on('call:error', (data) {
      _onCallError?.call(data);
    });

    // WebRTC signaling
    _socket!.on('signal:offer', (data) => _onSignalOffer?.call(data));
    _socket!.on('signal:answer', (data) => _onSignalAnswer?.call(data));
    _socket!.on('signal:ice', (data) => _onSignalIce?.call(data));

    // Voice message
    _socket!.on('message:new', (data) {
      _onNewMessage?.call(data);
      notifyListeners();
    });
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _onlineStatus.clear();
    _cachedIceServers = null;
  }

  /// Emit explicit logout event so the server marks this user offline.
  void emitLogout() {
    _socket?.emit('user:logout');
  }

  /// Force a full reconnection (dispose old socket, create new one).
  /// Use after login, registration, or group join to ensure fresh state.
  Future<void> reconnect() async {
    disconnect();
    await connect();
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
  /// Returns cached value if available; otherwise queries via socket ack.
  Future<List<Map<String, dynamic>>> getIceServers() async {
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

  // Callbacks
  Function(dynamic)? _onCallRequest;
  Function(dynamic)? _onCallAccepted;
  Function(dynamic)? _onCallRejected;
  Function(dynamic)? _onCallEnded;
  Function(dynamic)? _onCallError;
  Function(dynamic)? _onSignalOffer;
  Function(dynamic)? _onSignalAnswer;
  Function(dynamic)? _onSignalIce;
  Function(dynamic)? _onNewMessage;

  set onCallRequest(Function(dynamic)? fn) => _onCallRequest = fn;
  set onCallAccepted(Function(dynamic)? fn) => _onCallAccepted = fn;
  set onCallRejected(Function(dynamic)? fn) => _onCallRejected = fn;
  set onCallEnded(Function(dynamic)? fn) => _onCallEnded = fn;
  set onCallError(Function(dynamic)? fn) => _onCallError = fn;
  set onSignalOffer(Function(dynamic)? fn) => _onSignalOffer = fn;
  set onSignalAnswer(Function(dynamic)? fn) => _onSignalAnswer = fn;
  set onSignalIce(Function(dynamic)? fn) => _onSignalIce = fn;
  set onNewMessage(Function(dynamic)? fn) => _onNewMessage = fn;

  Function(dynamic)? get onCallRequestHandler => _onCallRequest;
  Function(dynamic)? get onCallAcceptedHandler => _onCallAccepted;
  Function(dynamic)? get onCallRejectedHandler => _onCallRejected;
  Function(dynamic)? get onCallEndedHandler => _onCallEnded;
  Function(dynamic)? get onCallErrorHandler => _onCallError;
  Function(dynamic)? get onSignalOfferHandler => _onSignalOffer;
  Function(dynamic)? get onSignalAnswerHandler => _onSignalAnswer;
  Function(dynamic)? get onSignalIceHandler => _onSignalIce;

  void updateBulkOnlineStatus(List<dynamic> members) {
    for (final m in members) {
      if (m is! Map) continue;
      final userId = (m['userId'] ?? m['id'])?.toString();
      if (userId == null || userId.isEmpty) continue;
      _onlineStatus[userId] = m['isOnline'] ?? false;
    }
    notifyListeners();
  }
}
