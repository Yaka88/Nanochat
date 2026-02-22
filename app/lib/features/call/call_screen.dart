import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/api/socket_service.dart';

class CallScreen extends StatefulWidget {
  final bool isVideo;
  final String name;
  final String targetUserId;
  final String groupId;
  final SocketService socketService;

  const CallScreen({
    Key? key,
    required this.isVideo,
    required this.name,
    required this.targetUserId,
    required this.groupId,
    required this.socketService,
  }) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _micEnabled = true;
  bool _speakerEnabled = true;
  int _elapsedSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds += 1;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _durationText {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _hangup() {
    _timer?.cancel();
    widget.socketService.endCall(targetUserId: widget.targetUserId);
    Navigator.pop(context);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 通话界面背景深色
      appBar: AppBar(
        title: Text('正在与 ${widget.name} 通话...'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Center(
            child: widget.isVideo 
              ? const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person, size: 150, color: Colors.grey),
                    SizedBox(height: 24),
                    Text('视频加载中...', style: TextStyle(fontSize: 28, color: Colors.white)),
                  ],
                )
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person, size: 150, color: Colors.grey),
                    SizedBox(height: 24),
                    Text('正在语音通话', style: TextStyle(fontSize: 28, color: Colors.white)),
                  ],
                ),
          ),

          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                _durationText,
                style: const TextStyle(fontSize: 24, color: Colors.white70),
              ),
            ),
          ),
          
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 麦克风开关
                FloatingActionButton(
                  heroTag: 'mic',
                  backgroundColor: _micEnabled ? Colors.white24 : Colors.redAccent,
                  onPressed: () {
                    setState(() {
                      _micEnabled = !_micEnabled;
                    });
                  },
                  child: Icon(
                    _micEnabled ? Icons.mic : Icons.mic_off,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
                
                // 挂断
                FloatingActionButton(
                  heroTag: 'hangup',
                  backgroundColor: Colors.red,
                  onPressed: _hangup,
                  child: const Icon(Icons.call_end, size: 36, color: Colors.white),
                ),
                
                // 扬声器外放
                FloatingActionButton(
                  heroTag: 'speaker',
                  backgroundColor: _speakerEnabled ? Colors.white24 : Colors.blueGrey,
                  onPressed: () {
                    setState(() {
                      _speakerEnabled = !_speakerEnabled;
                    });
                  },
                  child: Icon(
                    _speakerEnabled ? Icons.volume_up : Icons.hearing_disabled,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
