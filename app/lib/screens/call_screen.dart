import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/socket_provider.dart';
import '../core/l10n.dart';

/// Video / Voice call screen using WebRTC
class CallScreen extends StatefulWidget {
  final String targetUserId;
  final String targetName;
  final bool isVideo;

  const CallScreen({
    super.key,
    required this.targetUserId,
    required this.targetName,
    required this.isVideo,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  bool _connected = false;
  bool _muted = false;
  bool _speakerOn = true;
  bool _cleaned = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Get local media
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.isVideo
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    });
    _localRenderer.srcObject = _localStream;

    // Create peer connection
    _pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:chat.bluelaser.cn:3478'},
      ],
    });

    _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
          _connected = true;
        });
      }
    };

    _pc!.onIceCandidate = (candidate) {
      context.read<SocketProvider>().emit('signal:ice', {
        'targetUserId': widget.targetUserId,
        'candidate': candidate.toMap(),
      });
    };

    // Listen for signaling
    final socket = context.read<SocketProvider>();

    socket.onSignalAnswer = (data) async {
      await _setRemoteDescriptionAndFlush(
        RTCSessionDescription(data['sdp'], data['type']),
      );
    };

    socket.onSignalIce = (data) async {
      final candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'],
      );

      if (!_remoteDescriptionSet) {
        _pendingRemoteCandidates.add(candidate);
        return;
      }

      await _pc!.addCandidate(candidate);
    };

    socket.onCallAccepted = (_) => _createOffer();
    socket.onCallRejected = (_) => _endCall();
    socket.onCallEnded = (_) => _endCall();

    socket.onSignalOffer = (data) async {
      await _setRemoteDescriptionAndFlush(
        RTCSessionDescription(data['sdp'], data['type']),
      );
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      socket.emit('signal:answer', {
        'targetUserId': widget.targetUserId,
        'sdp': answer.sdp,
        'type': answer.type,
      });
    };

    // Send call request
    socket.emit('call:request', {
      'targetUserId': widget.targetUserId,
      'isVideo': widget.isVideo,
    });

    setState(() {});
  }

  Future<void> _setRemoteDescriptionAndFlush(RTCSessionDescription desc) async {
    await _pc!.setRemoteDescription(desc);
    _remoteDescriptionSet = true;
    if (_pendingRemoteCandidates.isNotEmpty) {
      for (final candidate in _pendingRemoteCandidates) {
        await _pc!.addCandidate(candidate);
      }
      _pendingRemoteCandidates.clear();
    }
  }

  Future<void> _createOffer() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    context.read<SocketProvider>().emit('signal:offer', {
      'targetUserId': widget.targetUserId,
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  void _endCall() {
    context.read<SocketProvider>().emit('call:end', {
      'targetUserId': widget.targetUserId,
    });
    _cleanup();
    if (mounted) Navigator.pop(context);
  }

  void _toggleMute() {
    final nextMuted = !_muted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !nextMuted);
    setState(() => _muted = nextMuted);
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    // Platform-specific speaker toggle would go here
  }

  void _cleanup() {
    if (_cleaned) return;
    _cleaned = true;
    final socket = context.read<SocketProvider>();
    socket.onCallAccepted = null;
    socket.onCallRejected = null;
    socket.onCallEnded = null;
    socket.onSignalOffer = null;
    socket.onSignalAnswer = null;
    socket.onSignalIce = null;
    _localStream?.dispose();
    _pc?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote video (full screen)
            if (widget.isVideo)
              Positioned.fill(
                child: _connected
                    ? RTCVideoView(_remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
              ),

            // Voice call UI
            if (!widget.isVideo)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.person, size: 64, color: Colors.white70),
                    ),
                    const SizedBox(height: 24),
                    Text(widget.targetName,
                        style: const TextStyle(
                            fontSize: 32, color: Colors.white,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_connected ? '' : t('calling'),
                        style: const TextStyle(fontSize: 20, color: Colors.white70)),
                  ],
                ),
              ),

            // Local video (small, top-right)
            if (widget.isVideo)
              Positioned(
                top: 16,
                right: 16,
                width: 120,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(_localRenderer, mirror: true),
                ),
              ),

            // Name bar
            Positioned(
              top: 16,
              left: 16,
              child: Text(widget.targetName,
                  style: const TextStyle(
                      fontSize: 24, color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),

            // Control buttons
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    label: _muted ? 'Muted' : 'Mic',
                    color: Colors.white24,
                    onTap: _toggleMute,
                  ),
                  _CallButton(
                    icon: Icons.call_end,
                    label: t('end_call'),
                    color: Colors.red,
                    size: 72,
                    onTap: _endCall,
                  ),
                  _CallButton(
                    icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                    label: 'Speaker',
                    color: Colors.white24,
                    onTap: _toggleSpeaker,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    this.size = 56,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: size * 0.5),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    );
  }
}
