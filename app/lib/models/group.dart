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
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      creatorId: json['creatorId']?.toString() ??
        json['creator_id']?.toString() ??
        json['creator']?['id']?.toString() ??
        '',
      inviteCode: json['inviteCode']?.toString() ?? json['invite_code']?.toString(),
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
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['id']?.toString() ?? '',
      groupId: json['groupId']?.toString() ?? json['group_id']?.toString() ?? '',
      nameInGroup: json['nameInGroup']?.toString() ?? json['nickname']?.toString() ?? '',
        avatarUrl: json['avatarUrl'] ?? json['user']?['avatarUrl'],
        isOnline: json['isOnline'] ?? json['user']?['isOnline'] ?? false,
      );
}
