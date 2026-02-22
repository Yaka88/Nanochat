import 'package:flutter/material.dart';
import 'dart:io';
import '../../core/api/api_client.dart';
import '../../core/utils/error_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceMessageScreen extends StatefulWidget {
  final String name;
  final String receiverUserId;
  final String groupId;

  const VoiceMessageScreen({
    Key? key,
    required this.name,
    required this.receiverUserId,
    required this.groupId,
  }) : super(key: key);

  @override
  State<VoiceMessageScreen> createState() => _VoiceMessageScreenState();
}

class _VoiceMessageScreenState extends State<VoiceMessageScreen> {
  static const int _maxDurationSeconds = 60;

  final ApiClient _apiClient = ApiClient();
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool isRecording = false;
  bool isSending = false;
  DateTime? _recordingStartedAt;
  String? _recordingPath;

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有麦克风权限，请先授权')),
      );
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
      ),
      path: filePath,
    );

    setState(() {
      isRecording = true;
      _recordingStartedAt = DateTime.now();
      _recordingPath = filePath;
    });
  }

  Future<void> _stopAndSendRecording() async {
    final startedAt = _recordingStartedAt;
    final filePath = await _audioRecorder.stop() ?? _recordingPath;

    setState(() {
      isRecording = false;
      isSending = true;
    });

    try {
      if (filePath == null || filePath.isEmpty) {
        throw Exception('录音文件不存在');
      }

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('录音文件不存在');
      }

      final now = DateTime.now();
      final durationRaw = startedAt == null
          ? 1
          : now.difference(startedAt).inSeconds;
      final duration = durationRaw <= 0
          ? 1
          : (durationRaw > _maxDurationSeconds ? _maxDurationSeconds : durationRaw);

      final audioBytes = await file.readAsBytes();

      await _apiClient.uploadVoiceMessage(
        groupId: widget.groupId,
        receiverId: widget.receiverUserId,
        durationSeconds: duration,
        audioBytes: audioBytes,
        fileName: file.uri.pathSegments.isEmpty
            ? 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a'
            : file.uri.pathSegments.last,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('留言已发送', style: TextStyle(fontSize: 24))),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = extractErrorMessage(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $message')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSending = false;
          _recordingStartedAt = null;
          _recordingPath = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('给 ${widget.name} 留语音')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('按住下方按钮说话', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 48),
            GestureDetector(
              onLongPressStart: isSending ? null : (_) => _startRecording(),
              onLongPressEnd: isSending ? null : (_) => _stopAndSendRecording(),
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: isSending
                      ? Colors.grey
                      : (isRecording ? Colors.red : Colors.orange),
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (isRecording)
                      BoxShadow(
                        color: Colors.red.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 10,
                      )
                  ],
                ),
                child: Icon(
                  isSending
                      ? Icons.hourglass_top
                      : (isRecording ? Icons.mic : Icons.mic_none),
                  size: 100,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isSending
                  ? '发送中...'
                  : (isRecording ? '录音中... 松开发送' : '长按录音（最长60秒）'),
              style: const TextStyle(fontSize: 24, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
