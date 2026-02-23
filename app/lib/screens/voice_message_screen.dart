import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../core/api.dart';
import '../core/l10n.dart';
import '../models/message.dart';

/// Voice message screen: record, playback, send
class VoiceMessageScreen extends StatefulWidget {
  final String targetUserId;
  final String targetName;
  final String groupId;

  const VoiceMessageScreen({
    super.key,
    required this.targetUserId,
    required this.targetName,
    required this.groupId,
  });

  @override
  State<VoiceMessageScreen> createState() => _VoiceMessageScreenState();
}

class _VoiceMessageScreenState extends State<VoiceMessageScreen> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  List<VoiceMessage> _messages = [];
  bool _recording = false;
  int _seconds = 0;
  Timer? _timer;
  String? _recordPath;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final res = await Api.getMessages(
        groupId: widget.groupId,
        userId: widget.targetUserId,
      );
      setState(() {
        _messages = (res['messages'] as List)
            .map((m) => VoiceMessage.fromJson(m))
            .toList();
      });
    } catch (e) {
      debugPrint('Load messages error: $e');
    }
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    _recordPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _recordPath!,
    );

    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
      if (_seconds >= 60) _stopRecording();
    });
    setState(() => _recording = true);
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    await _recorder.stop();
    setState(() => _recording = false);
  }

  Future<void> _send() async {
    if (_recordPath == null) return;
    try {
      await Api.sendVoiceMessage(
        groupId: widget.groupId,
        receiverId: widget.targetUserId,
        durationSeconds: _seconds,
        audioFilePath: _recordPath!,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent!', style: TextStyle(fontSize: 18))),
      );
      _recordPath = null;
      setState(() => _seconds = 0);
      _loadMessages();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _playMessage(VoiceMessage msg) async {
    await _player.play(UrlSource(Api.resolveFileUrl(msg.audioUrl)));
    if (!msg.isRead) {
      Api.markRead(msg.id).catchError((_) {});
    }
  }

  String _formatDuration(int secs) =>
      '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = (String k) => AppL10n.t(context, k);
    return Scaffold(
      appBar: AppBar(title: Text(widget.targetName)),
      body: Column(
        children: [
          // Message list
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text('No messages',
                        style: TextStyle(fontSize: 18, color: Colors.grey[500])))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      return _MessageBubble(
                        message: msg,
                        onPlay: () => _playMessage(msg),
                      );
                    },
                  ),
          ),
          // Record area
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (_recording || _recordPath != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _recording
                          ? '${t('recording')} ${_formatDuration(_seconds)}'
                          : '${_formatDuration(_seconds)} ready',
                      style: TextStyle(
                        fontSize: 20,
                        color: _recording ? Colors.red : Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Record button
                    GestureDetector(
                      onLongPressStart: (_) => _startRecording(),
                      onLongPressEnd: (_) => _stopRecording(),
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: _recording ? Colors.red : Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _recording ? Icons.stop : Icons.mic,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (_recordPath != null && !_recording) ...[
                      const SizedBox(width: 24),
                      GestureDetector(
                        onTap: _send,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.send, size: 32, color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(t('hold_to_record'),
                    style: TextStyle(fontSize: 16, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final VoiceMessage message;
  final VoidCallback onPlay;

  const _MessageBubble({required this.message, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: onPlay,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow, size: 32, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    '${message.durationSeconds}s',
                    style: const TextStyle(fontSize: 20, color: Colors.blue),
                  ),
                  if (!message.isRead) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
