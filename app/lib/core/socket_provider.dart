import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'storage.dart';

class SocketProvider extends ChangeNotifier {
  io.Socket? _socket;
  final Map<String, bool> _onlineStatus = {};

  bool isUserOnline(String userId) => _onlineStatus[userId] ?? false;

  Future<void> connect() async {
    if (_socket?.connected == true) return;

    final token = await LocalStorage.getToken();
    if (token == null) return;

    _socket = io.io(
      'https://chat.bluelaser.cn',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) => debugPrint('[WS] Connected'));
    _socket!.onDisconnect((_) => debugPrint('[WS] Disconnected'));

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
  Function(dynamic)? _onSignalOffer;
  Function(dynamic)? _onSignalAnswer;
  Function(dynamic)? _onSignalIce;
  Function(dynamic)? _onNewMessage;

  set onCallRequest(Function(dynamic)? fn) => _onCallRequest = fn;
  set onCallAccepted(Function(dynamic)? fn) => _onCallAccepted = fn;
  set onCallRejected(Function(dynamic)? fn) => _onCallRejected = fn;
  set onCallEnded(Function(dynamic)? fn) => _onCallEnded = fn;
  set onSignalOffer(Function(dynamic)? fn) => _onSignalOffer = fn;
  set onSignalAnswer(Function(dynamic)? fn) => _onSignalAnswer = fn;
  set onSignalIce(Function(dynamic)? fn) => _onSignalIce = fn;
  set onNewMessage(Function(dynamic)? fn) => _onNewMessage = fn;

  void updateBulkOnlineStatus(List<dynamic> members) {
    for (final m in members) {
      _onlineStatus[m['userId']] = m['isOnline'] ?? false;
    }
    notifyListeners();
  }
}
