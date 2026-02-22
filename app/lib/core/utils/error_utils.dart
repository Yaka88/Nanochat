import 'package:dio/dio.dart';

/// Extract a user-friendly error message from any error object.
/// Handles DioException by reading the server response body.
String extractErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final msg = data['error'] ?? data['message'];
      if (msg != null && msg.toString().isNotEmpty) {
        return msg.toString();
      }
    }
    return error.message ?? '网络请求失败';
  }
  return error.toString().replaceFirst('Exception: ', '');
}
