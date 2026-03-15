import 'dart:async';
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
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.targetUserId,
    required this.targetName,
    required this.isVideo,
    this.isIncoming = false,
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
  bool _offerCreated = false;
  bool _accepted = false;
  Timer? _outgoingTimeoutTimer;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;
  late final SocketProvider _socketProvider;

  StreamSubscription<dynamic>? _callAcceptedSub;
  StreamSubscription<dynamic>? _callRejectedSub;
  StreamSubscription<dynamic>? _callEndedSub;
  StreamSubscription<dynamic>? _callErrorSub;
  StreamSubscription<dynamic>? _signalOfferSub;
  StreamSubscription<dynamic>? _signalAnswerSub;
  StreamSubscription<dynamic>? _signalIceSub;

  @override
  void initState() {
    super.initState();
    _socketProvider = context.read<SocketProvider>();
    _init();
  }

  Future<void> _init() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

    // Get local media
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              'frameRate': {'ideal': 30},
            }
          : false,
    });
    _localRenderer.srcObject = _localStream;

    // Fetch TURN/STUN ICE servers from server
    final iceServers = await _socketProvider.getIceServers();

    // Create peer connection with TURN support
    _pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    // Set higher bitrate for video
    if (widget.isVideo) {
      final senders = await _pc!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          final params = sender.parameters;
          if (params.encodings == null || params.encodings!.isEmpty) {
            params.encodings = [RTCRtpEncoding()];
          }
          for (final encoding in params.encodings!) {
            encoding.maxBitrate = 2000000; // 2 Mbps
            encoding.minBitrate = 500000;  // 500 kbps
          }
          await sender.setParameters(params);
        }
      }
    }

    await Helper.setSpeakerphoneOn(true);

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
      _socketProvider.emit('signal:ice', {
        'targetUserId': widget.targetUserId,
        'candidate': candidate.toMap(),
      });
    };

    // Listen for signaling
    _signalAnswerSub = _socketProvider.onSignalAnswerStream.listen((data) async {
      if (data['fromUserId']?.toString() != widget.targetUserId) return;
      if (_cleaned || _pc == null) return;
      await _setRemoteDescriptionAndFlush(
        RTCSessionDescription(data['sdp'], data['type']),
      );
    });

    _signalIceSub = _socketProvider.onSignalIceStream.listen((data) async {
      if (data['fromUserId']?.toString() != widget.targetUserId) return;
      if (_cleaned || _pc == null) return;
      final candidateData = data['candidate'];
      if (candidateData == null || candidateData is! Map) return;
      final candidate = RTCIceCandidate(
        candidateData['candidate']?.toString(),
        candidateData['sdpMid']?.toString(),
        candidateData['sdpMLineIndex'] as int?,
      );

      if (!_remoteDescriptionSet) {
        _pendingRemoteCandidates.add(candidate);
        return;
      }

      if (_pc == null) return;
      await _pc!.addCandidate(candidate);
    });

    _callAcceptedSub = _socketProvider.onCallAcceptedStream.listen((data) {
      if (data['fromUserId']?.toString() != widget.targetUserId) return;
      _accepted = true;
      _outgoingTimeoutTimer?.cancel();
      _createOffer();
    });
    _callRejectedSub = _socketProvider.onCallRejectedStream.listen((data) {
      if (data['fromUserId']?.toString() != widget.targetUserId) return;
      _finishCall(localHangup: false);
    });

    _callEndedSub = _socketProvider.onCallEndedStream.listen((data) {
      if (data['fromUserId']?.toString() != widget.targetUserId) return;
      _finishCall(localHangup: false);
    });

    _callErrorSub = _socketProvider.onCallErrorStream.listen((data) {
      if (!mounted) return;
      final message = (data is Map ? data['message'] : null)?.toString() ?? 'Call failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      _finishCall(localHangup: false);
    });

    _signalOfferSub = _socketProvider.onSignalOfferStream.listen((data) async {
      if (data['fromUserId']?.toString() != widget.targetUserId) return;
      if (_cleaned || _pc == null) return;
      await _setRemoteDescriptionAndFlush(
        RTCSessionDescription(data['sdp'], data['type']),
      );
      final answer = await _pc!.createAnswer();
      if (widget.isVideo) {
        answer.sdp = _setVideoBandwidth(answer.sdp!, 2000);
      }
      await _pc!.setLocalDescription(answer);
      _socketProvider.emit('signal:answer', {
        'targetUserId': data['fromUserId'] ?? widget.targetUserId,
        'sdp': answer.sdp,
        'type': answer.type,
      });
    });

    if (!widget.isIncoming) {
      _socketProvider.emit('call:request', {
        'targetUserId': widget.targetUserId,
        'isVideo': widget.isVideo,
      });

      _outgoingTimeoutTimer?.cancel();
      _outgoingTimeoutTimer = Timer(const Duration(seconds: 30), () {
        if (!mounted || _connected || _accepted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('呼叫超时，对方未接听')),
        );
        _finishCall(localHangup: true);
      });
    } else {
      // Incoming: now that media & peer connection are ready, tell the
      // caller we are ready so they can create the offer.
      _socketProvider.emit('call:accept', {
        'targetUserId': widget.targetUserId,
      });
    }

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通话初始化失败: $e')),
      );
      // Tell the other side we can't proceed
      if (widget.isIncoming) {
        _socketProvider.emit('call:reject', {'targetUserId': widget.targetUserId});
      }
      _finishCall(localHangup: !widget.isIncoming);
    }
  }

  Future<void> _setRemoteDescriptionAndFlush(RTCSessionDescription desc) async {
    await _pc!.setRemoteDescription(desc);
    _remoteDescriptionSet = true;
    // Apply bitrate constraints to video sender after remote description is set
    if (widget.isVideo) await _applyVideoBitrate();
    if (_pendingRemoteCandidates.isNotEmpty) {
      for (final candidate in _pendingRemoteCandidates) {
        await _pc!.addCandidate(candidate);
      }
      _pendingRemoteCandidates.clear();
    }
  }

  /// Apply max bitrate to the video sender via RTCRtpSender parameters.
  Future<void> _applyVideoBitrate() async {
    if (_pc == null) return;
    final senders = await _pc!.getSenders();
    for (final sender in senders) {
      if (sender.track?.kind == 'video') {
        final params = sender.parameters;
        if (params.encodings == null || params.encodings!.isEmpty) {
          params.encodings = [RTCRtpEncoding()];
        }
        for (final encoding in params.encodings!) {
          encoding.maxBitrate = 2000000; // 2 Mbps
          encoding.minBitrate = 500000;  // 500 kbps
        }
        await sender.setParameters(params);
      }
    }
  }

  /// Set bandwidth in SDP for video media section (b=AS:xxx).
  String _setVideoBandwidth(String sdp, int bandwidthKbps) {
    final lines = sdp.split('\n');
    final result = <String>[];
    bool inVideo = false;
    for (final line in lines) {
      if (line.startsWith('m=video')) {
        inVideo = true;
      } else if (line.startsWith('m=')) {
        inVideo = false;
      }
      // Remove existing bandwidth line in video section
      if (inVideo && line.startsWith('b=AS:')) continue;
      result.add(line);
      // Insert bandwidth after c= line in video section
      if (inVideo && line.startsWith('c=')) {
        result.add('b=AS:$bandwidthKbps');
      }
    }
    return result.join('\n');
  }

  Future<void> _createOffer() async {
    if (_offerCreated || _pc == null) return;
    _offerCreated = true;
    final offer = await _pc!.createOffer();
    if (widget.isVideo) {
      offer.sdp = _setVideoBandwidth(offer.sdp!, 2000);
    }
    await _pc!.setLocalDescription(offer);
    _socketProvider.emit('signal:offer', {
      'targetUserId': widget.targetUserId,
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  void _finishCall({required bool localHangup}) {
    _outgoingTimeoutTimer?.cancel();
    if (localHangup) {
      _socketProvider.emit('call:end', {
        'targetUserId': widget.targetUserId,
      });
    }
    _cleanup();
    if (mounted) Navigator.pop(context);
  }

  void _endCall() {
    _finishCall(localHangup: true);
  }

  void _toggleMute() {
    final nextMuted = !_muted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !nextMuted);
    setState(() => _muted = nextMuted);
  }

  void _toggleSpeaker() {
    final nextSpeakerOn = !_speakerOn;
    Helper.setSpeakerphoneOn(nextSpeakerOn);
    setState(() => _speakerOn = nextSpeakerOn);
  }

  void _cleanup() {
    if (_cleaned) return;
    _cleaned = true;
    _outgoingTimeoutTimer?.cancel();
    _callAcceptedSub?.cancel();
    _callRejectedSub?.cancel();
    _callEndedSub?.cancel();
    _callErrorSub?.cancel();
    _signalOfferSub?.cancel();
    _signalAnswerSub?.cancel();
    _signalIceSub?.cancel();
    try { _localStream?.dispose(); } catch (_) {}
    try { _pc?.close(); } catch (_) {}
    try { _localRenderer.dispose(); } catch (_) {}
    try { _remoteRenderer.dispose(); } catch (_) {}
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
