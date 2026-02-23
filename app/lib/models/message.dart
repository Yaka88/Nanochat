class VoiceMessage {
  final String id;
  final String? groupId;
  final String? senderId;
  final String? receiverId;
  final String audioUrl;
  final int durationSeconds;
  final bool isRead;
  final DateTime createdAt;
  final String? senderName;

  VoiceMessage({
    required this.id,
    this.groupId,
    this.senderId,
    this.receiverId,
    required this.audioUrl,
    required this.durationSeconds,
    this.isRead = false,
    required this.createdAt,
    this.senderName,
  });

  factory VoiceMessage.fromJson(Map<String, dynamic> json) => VoiceMessage(
      id: (json['id'] ?? '').toString(),
      groupId: json['groupId']?.toString() ?? json['group']?['id']?.toString(),
      senderId:
        json['senderId']?.toString() ?? json['sender']?['id']?.toString(),
      receiverId: json['receiverId']?.toString(),
      audioUrl: (json['audioUrl'] ?? '').toString(),
        durationSeconds: json['durationSeconds'] ?? 0,
        isRead: json['isRead'] ?? false,
        createdAt: DateTime.parse(json['createdAt']),
      senderName: json['senderName']?.toString() ??
        json['sender']?['nickname']?.toString(),
      );
}
