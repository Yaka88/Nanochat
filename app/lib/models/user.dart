class User {
  final String id;
  final String? email;
  final String nickname;
  final String? avatarUrl;
  final bool isRegistered;
  final bool emailVerified;
  final String? deviceId;
  final bool isOnline;
  final String? lastGroupId;

  User({
    required this.id,
    this.email,
    required this.nickname,
    this.avatarUrl,
    this.isRegistered = false,
    this.emailVerified = false,
    this.deviceId,
    this.isOnline = false,
    this.lastGroupId,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'],
        email: json['email'],
        nickname: json['nickname'],
        avatarUrl: json['avatarUrl'],
        isRegistered: json['isRegistered'] ?? false,
        emailVerified: json['emailVerified'] ?? false,
        deviceId: json['deviceId'],
        isOnline: json['isOnline'] ?? false,
        lastGroupId: json['lastGroupId'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'nickname': nickname,
        'avatarUrl': avatarUrl,
        'isRegistered': isRegistered,
        'emailVerified': emailVerified,
        'deviceId': deviceId,
        'isOnline': isOnline,
        'lastGroupId': lastGroupId,
      };
}
