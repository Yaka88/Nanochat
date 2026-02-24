import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'storage.dart';

class SocketProvider extends ChangeNotifier {
  io.Socket? _socket;
  final Map<String, bool> _onlineStatus = {};

  bool isUserOnline(String userId) => _onlineStatus[userId] ?? false;

  Future<void> connect() async {
    if (_socket?.connected == true) return;

    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }

    _onlineStatus.clear();

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

    _socket!.onConnect((_) => debugPrint('[WS] Connected'));
    _socket!.onDisconnect((_) => debugPrint('[WS] Disconnected'));

    _socket!.on('presence:snapshot', (data) {
      final ids = (data is Map ? data['onlineUserIds'] : null) as List<dynamic>?;
      if (ids == null) return;
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
