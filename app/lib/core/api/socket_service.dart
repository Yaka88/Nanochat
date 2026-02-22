import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../auth/session_store.dart';

typedef SocketDataHandler = void Function(Map<String, dynamic> data);

class SocketService {
  static const String serverUrl = 'https://chat.bluelaser.cn';
  IO.Socket? socket;

  SocketDataHandler? onUserOnline;
  SocketDataHandler? onUserOffline;
  SocketDataHandler? onCallIncoming;
  SocketDataHandler? onCallAccepted;
  SocketDataHandler? onCallRejected;
  SocketDataHandler? onCallEnded;
  SocketDataHandler? onCallError;
  SocketDataHandler? onSignalOffer;
  SocketDataHandler? onSignalAnswer;
  SocketDataHandler? onSignalIce;
  SocketDataHandler? onNewMessage;

  void setHandlers({
    SocketDataHandler? onUserOnline,
    SocketDataHandler? onUserOffline,
    SocketDataHandler? onCallIncoming,
    SocketDataHandler? onCallAccepted,
    SocketDataHandler? onCallRejected,
    SocketDataHandler? onCallEnded,
    SocketDataHandler? onCallError,
    SocketDataHandler? onSignalOffer,
    SocketDataHandler? onSignalAnswer,
    SocketDataHandler? onSignalIce,
    SocketDataHandler? onNewMessage,
  }) {
    this.onUserOnline = onUserOnline;
    this.onUserOffline = onUserOffline;
    this.onCallIncoming = onCallIncoming;
    this.onCallAccepted = onCallAccepted;
    this.onCallRejected = onCallRejected;
    this.onCallEnded = onCallEnded;
    this.onCallError = onCallError;
    this.onSignalOffer = onSignalOffer;
    this.onSignalAnswer = onSignalAnswer;
    this.onSignalIce = onSignalIce;
    this.onNewMessage = onNewMessage;
  }

  void connect() async {
    final token = await SessionStore.getAuthToken();

    if (token == null || token.isEmpty) {
      print('Socket connect skipped: missing auth token');
      return;
    }

    socket?.disconnect();
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {
        'token': token,
      }
    });
    
    socket!.connect();

    socket!.onConnect((_) {
      print('Socket Connected');
    });
    
    // Online / Offline Status
    socket!.on('user:online', (data) {
      final payload = _toMap(data);
      print('User Online: $payload');
      onUserOnline?.call(payload);
    });
    socket!.on('user:offline', (data) {
      final payload = _toMap(data);
      print('User Offline: $payload');
      onUserOffline?.call(payload);
    });
    
    // Call Status
    socket!.on('call:incoming', (data) {
      final payload = _toMap(data);
      print('Call Incoming: $payload');
      onCallIncoming?.call(payload);
    });
    socket!.on('call:accepted', (data) {
      final payload = _toMap(data);
      print('Call Accepted: $payload');
      onCallAccepted?.call(payload);
    });
    socket!.on('call:rejected', (data) {
      final payload = _toMap(data);
      print('Call Rejected: $payload');
      onCallRejected?.call(payload);
    });
    socket!.on('call:ended', (data) {
      final payload = _toMap(data);
      print('Call Ended: $payload');
      onCallEnded?.call(payload);
    });
    socket!.on('call:error', (data) {
      final payload = _toMap(data);
      print('Call Error: $payload');
      onCallError?.call(payload);
    });
    
    // Signaling
    socket!.on('signal:offer', (data) {
      final payload = _toMap(data);
      print('WebRTC Offer: $payload');
      onSignalOffer?.call(payload);
    });
    socket!.on('signal:answer', (data) {
      final payload = _toMap(data);
      print('WebRTC Answer: $payload');
      onSignalAnswer?.call(payload);
    });
    socket!.on('signal:ice', (data) {
      final payload = _toMap(data);
      print('WebRTC ICE Candidate: $payload');
      onSignalIce?.call(payload);
    });
    
    // New voice messages
    socket!.on('message:new', (data) {
      final payload = _toMap(data);
      print('New message: $payload');
      onNewMessage?.call(payload);
    });
  }

  void requestCall({
    required String targetUserId,
    required String groupId,
    required String callType,
  }) {
    socket?.emit('call:request', {
      'targetUserId': targetUserId,
      'groupId': groupId,
      'callType': callType,
    });
  }

  void acceptCall({required String callerId}) {
    socket?.emit('call:accept', {
      'callerId': callerId,
    });
  }

  void rejectCall({required String callerId, String? reason}) {
    socket?.emit('call:reject', {
      'callerId': callerId,
      'reason': reason,
    });
  }

  void endCall({required String targetUserId}) {
    socket?.emit('call:end', {
      'targetUserId': targetUserId,
    });
  }

  void disconnect() {
    socket?.disconnect();
    socket = null;
  }

  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    return {'value': data};
  }
}
