import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage.dart';

class Api {
  static const _defaultBaseUrl = 'https://chat.bluelaser.cn/api';
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  static String resolveFileUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final uri = Uri.parse(baseUrl);
    final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    return '$origin$url';
  }

  static Future<Map<String, String>> _headers() async {
    final token = await LocalStorage.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers();
    late http.Response res;

    switch (method) {
      case 'GET':
        res = await http.get(uri, headers: headers);
        break;
      case 'POST':
        res = await http.post(uri, headers: headers, body: jsonEncode(body));
        break;
      case 'PUT':
        res = await http.put(uri, headers: headers, body: jsonEncode(body));
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: headers);
        break;
    }

    final data = jsonDecode(res.body);
    if (res.statusCode >= 400) {
      throw ApiException(data['error'] ?? 'Request failed', res.statusCode);
    }
    return data;
  }

  // Auth
  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String nickname,
  }) =>
      _request('POST', '/auth/register', body: {
        'email': email,
        'password': password,
        'nickname': nickname,
      });

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) =>
      _request('POST', '/auth/login', body: {
        'email': email,
        'password': password,
      });

  static Future<Map<String, dynamic>> loginById({
    required String userId,
    required String deviceId,
  }) =>
      _request('POST', '/auth/login-by-id', body: {
        'userId': userId,
        'deviceId': deviceId,
      });

  static Future<Map<String, dynamic>> upgradeToRegistered({
    required String email,
    required String password,
  }) =>
      _request('POST', '/auth/upgrade', body: {
        'email': email,
        'password': password,
      });

  static Future<Map<String, dynamic>> getMe() =>
      _request('GET', '/auth/me');

  // Groups
  static Future<Map<String, dynamic>> getGroups() =>
      _request('GET', '/groups');

  static Future<Map<String, dynamic>> createGroup({required String name}) =>
      _request('POST', '/groups', body: {'name': name});

  static Future<Map<String, dynamic>> getGroupMembers(String groupId) =>
      _request('GET', '/groups/$groupId/members');

  static Future<Map<String, dynamic>> getInviteQR(String groupId) =>
      _request('GET', '/groups/$groupId/invite');

  static Future<Map<String, dynamic>> joinGroupByCode({
    required String groupId,
    required String groupName,
    required String inviterName,
    required int timestamp,
    required String signature,
    required String inviteCode,
    required String deviceId,
    String? nameInGroup,
    String? nickname,
  }) =>
      _request('POST', '/groups/join-by-code', body: {
        'groupId': groupId,
        'groupName': groupName,
        'inviterName': inviterName,
        'timestamp': timestamp,
        'signature': signature,
        'inviteCode': inviteCode,
        'deviceId': deviceId,
        if (nameInGroup != null) 'nameInGroup': nameInGroup,
        if (nickname != null) 'nickname': nickname,
      });

  static Future<Map<String, dynamic>> sendVoiceMessage({
    required String groupId,
    required String receiverId,
    required int durationSeconds,
    required String audioFilePath,
  }) async {
    final token = await LocalStorage.getToken();
    final uri = Uri.parse('$baseUrl/messages');
    final request = http.MultipartRequest('POST', uri)
      ..fields['groupId'] = groupId
      ..fields['receiverId'] = receiverId
      ..fields['durationSeconds'] = '$durationSeconds'
      ..files.add(await http.MultipartFile.fromPath('file', audioFilePath));

    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final streamed = await request.send();
    final responseBody = await streamed.stream.bytesToString();
    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    if (streamed.statusCode >= 400) {
      throw ApiException(data['error'] ?? 'Request failed', streamed.statusCode);
    }
    return data;
  }

  static Future<String> uploadAvatar(String filePath) async {
    final token = await LocalStorage.getToken();
    final uri = Uri.parse('$baseUrl/auth/upload-avatar');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final streamed = await request.send();
    final responseBody = await streamed.stream.bytesToString();
    final data = jsonDecode(responseBody) as Map<String, dynamic>;

    if (streamed.statusCode >= 400) {
      throw ApiException(data['error'] ?? 'Upload failed', streamed.statusCode);
    }

    final avatarUrl = (data['avatarUrl'] ?? '').toString();
    if (avatarUrl.isEmpty) {
      throw ApiException('Invalid upload response', streamed.statusCode);
    }
    return avatarUrl;
  }

  static Future<Map<String, dynamic>> updateMyAvatar(String filePath) async {
    final token = await LocalStorage.getToken();
    final uri = Uri.parse('$baseUrl/auth/me/avatar');
    final request = http.MultipartRequest('PUT', uri)
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final streamed = await request.send();
    final responseBody = await streamed.stream.bytesToString();
    final data = jsonDecode(responseBody) as Map<String, dynamic>;

    if (streamed.statusCode >= 400) {
      throw ApiException(
        data['error'] ?? 'Update avatar failed',
        streamed.statusCode,
      );
    }
    return data;
  }

  // Messages
  static Future<Map<String, dynamic>> getMessages({
    String? groupId,
    String? userId,
  }) {
    final params = <String, String>{};
    if (groupId != null) params['groupId'] = groupId;
    if (userId != null) params['userId'] = userId;
    final query = Uri(queryParameters: params).query;
    return _request('GET', '/messages${query.isNotEmpty ? '?$query' : ''}');
  }

  static Future<Map<String, dynamic>> markRead(String messageId) =>
      _request('PUT', '/messages/$messageId/read');
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);
  @override
  String toString() => message;
}
