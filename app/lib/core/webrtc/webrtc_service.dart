import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../api/socket_service.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _targetUserId;

  final SocketService socketService;

  WebRTCService(this.socketService);

  void setTargetUser(String userId) {
    _targetUserId = userId;
  }

  Future<void> initConnection() async {
    final configuration = <String, dynamic>{
      'iceServers': [
        {
          'urls': ['stun:chat.bluelaser.cn:3478']
        }
      ]
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_targetUserId == null || socketService.socket == null) {
        return;
      }

      socketService.socket!.emit('signal:ice', {
        'targetUserId': _targetUserId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _peerConnection!.onAddStream = (MediaStream stream) {
      _remoteStream = stream;
      // Triggers UI update
    };
  }
}
