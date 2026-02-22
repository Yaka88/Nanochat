import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';
import '../auth/session_store.dart';

class ApiClient {
  static const String baseUrl = 'https://chat.bluelaser.cn/api';
  late final Dio dio;

  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));

    // add authorization token automatically
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await SessionStore.getAuthToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  Future<Map<String, dynamic>> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });

    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> registerWithEmail({
    required String email,
    required String password,
    required String nickname,
    String? avatarUrl,
  }) async {
    final payload = {
      'email': email,
      'password': password,
      'nickname': nickname,
      if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
    };

    final response = await dio.post('/auth/register', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> loginById({
    required String userId,
    required String deviceId,
  }) async {
    final response = await dio.post('/auth/login-by-id', data: {
      'userId': userId,
      'deviceId': deviceId,
    });

    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await dio.get('/auth/me');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async {
    final response = await dio.get('/groups/$groupId/members');
    final payload = Map<String, dynamic>.from(response.data as Map);
    final members = (payload['members'] as List?) ?? <dynamic>[];

    return members
        .map((member) => Map<String, dynamic>.from(member as Map))
        .toList();
  }

  Future<Map<String, dynamic>> getGroupInvite(String groupId) async {
    final response = await dio.get('/groups/$groupId/invite');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> joinGroupByCode({
    required Map<String, dynamic> invite,
    required String nickname,
    required String nameInGroup,
    required String deviceId,
    String? avatarUrl,
  }) async {
    final payload = {
      'inviteCode': invite['invite_code'],
      'groupId': invite['group_id'],
      'groupName': invite['group_name'],
      'inviterName': invite['inviter_name'],
      'timestamp': invite['timestamp'],
      'signature': invite['signature'],
      'nickname': nickname,
      'nameInGroup': nameInGroup,
      'deviceId': deviceId,
      if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
    };

    final response = await dio.post('/groups/join-by-code', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> uploadVoiceMessage({
    required String groupId,
    required String receiverId,
    required int durationSeconds,
    required Uint8List audioBytes,
    String fileName = 'voice.m4a',
  }) async {
    final form = FormData.fromMap({
      'groupId': groupId,
      'receiverId': receiverId,
      'durationSeconds': durationSeconds.toString(),
      'file': MultipartFile.fromBytes(
        audioBytes,
        filename: fileName,
        contentType: MediaType('audio', 'mp4'),
      ),
    });

    final response = await dio.post('/messages', data: form);
    return Map<String, dynamic>.from(response.data as Map);
  }
}
