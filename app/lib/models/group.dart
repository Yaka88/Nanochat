class Group {
  final String id;
  final String name;
  final String creatorId;
  final String? inviteCode;
  final DateTime? inviteExpiresAt;

  Group({
    required this.id,
    required this.name,
    required this.creatorId,
    this.inviteCode,
    this.inviteExpiresAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'],
        name: json['name'],
        creatorId: json['creatorId'],
        inviteCode: json['inviteCode'],
        inviteExpiresAt: json['inviteExpiresAt'] != null
            ? DateTime.parse(json['inviteExpiresAt'])
            : null,
      );
}

class GroupMember {
  final String id;
  final String userId;
  final String groupId;
  final String nameInGroup;
  final String? avatarUrl;
  bool isOnline;

  GroupMember({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.nameInGroup,
    this.avatarUrl,
    this.isOnline = false,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
        id: json['id'],
        userId: json['userId'],
        groupId: json['groupId'],
        nameInGroup: json['nameInGroup'],
        avatarUrl: json['avatarUrl'] ?? json['user']?['avatarUrl'],
        isOnline: json['isOnline'] ?? json['user']?['isOnline'] ?? false,
      );
}
