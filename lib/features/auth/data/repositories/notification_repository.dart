import 'package:dio/dio.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/notifications/push_token_logger.dart';
import '../../../../core/utils/session_helper.dart';
import '../models/notification_dto.dart';

class NotificationRepository {
  final ApiClient _apiClient = ApiClient();

  Future<String> _requireFreshToken() async {
    final t = await SessionHelper().ensureSession();
    if (t == null) {
      throw Exception('Please sign in to continue.');
    }
    _apiClient.setAuthToken(t);
    return t;
  }

  /// GET /api/notifications?page=&size=
  Future<NotificationPageDto> getNotifications({
    int page = 0,
    int size = 20,
  }) async {
    try {
      final token = await _requireFreshToken();
      final response = await _apiClient.dio.get(
        '/api/notifications',
        queryParameters: {
          'page': page,
          'size': size,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      return NotificationPageDto.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ??
                errorData['error'] ??
                'Failed to load notifications')
            : errorData?.toString() ?? 'Failed to load notifications';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// GET /api/notifications/unread-count
  Future<int> getUnreadCount() async {
    try {
      final token = await _requireFreshToken();
      final response = await _apiClient.dio.get(
        '/api/notifications/unread-count',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return (data['unreadCount'] as num?)?.toInt() ?? 0;
      }
      return 0;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ??
                errorData['error'] ??
                'Failed to load unread count')
            : errorData?.toString() ?? 'Failed to load unread count';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// PATCH /api/notifications/{id}/read → 204
  Future<void> markRead(String id) async {
    final encoded = Uri.encodeComponent(id);
    try {
      final token = await _requireFreshToken();
      await _apiClient.dio.patch(
        '/api/notifications/$encoded/read',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ??
                errorData['error'] ??
                'Failed to mark as read')
            : errorData?.toString() ?? 'Failed to mark as read';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// DELETE /api/notifications/{id} → 204
  Future<void> deleteNotification(String id) async {
    final encoded = Uri.encodeComponent(id);
    try {
      final token = await _requireFreshToken();
      await _apiClient.dio.delete(
        '/api/notifications/$encoded',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ??
                errorData['error'] ??
                'Failed to delete notification')
            : errorData?.toString() ?? 'Failed to delete notification';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// POST /api/notifications/push-token — Cihaz FCM token (iOS’ta APNs üzerinden eşleşen FCM token).
  /// Beklenen: 204 No Content, Authorization: Bearer (Firebase idToken)
  Future<void> registerPushToken({
    required String fcmToken,
    required String platform,
    String logSource = 'registerPushToken',
  }) async {
    if (platform != 'ios' && platform != 'android') {
      pushTokenLog('push-token skip bad platform', error: 'source=$logSource platform=$platform');
      return;
    }
    const path = '/api/notifications/push-token';
    final fullUrl = '${ApiConfig.baseUrl}$path';
    try {
      pushTokenLog(
        'push-token request (JWT = ensureSession sonrası Bearer)',
        error: 'source=$logSource | POST $fullUrl | platform=$platform | token_len=${fcmToken.length}',
        fcmTokenPrefix: fcmToken.length > 20
            ? '${fcmToken.substring(0, 10)}…${fcmToken.substring(fcmToken.length - 8)}'
            : fcmToken,
      );
      final session = await SessionHelper().ensureSession();
      if (session == null) {
        pushTokenLog('push-token skip (no session / JWT yok)', error: 'source=$logSource');
        return;
      }
      _apiClient.setAuthToken(session);
      final response = await _apiClient.dio.post(
        path,
        data: <String, String>{
          'token': fcmToken,
          'platform': platform,
        },
        options: Options(
          headers: <String, String>{'Authorization': 'Bearer $session'},
          validateStatus: (code) => code != null && code >= 200 && code < 300,
        ),
      );
      pushTokenLog(
        'push-token response OK',
        statusCode: response.statusCode,
        responseBody: response.data,
        error: 'source=$logSource',
        fcmTokenPrefix: 'ok',
      );
    } on DioException catch (e, st) {
      pushTokenLog(
        'push-token DioException',
        error:
            'source=$logSource | st=$st | type=${e.type} | msg=${e.message} | request=${e.requestOptions.uri} | req_data=${e.requestOptions.data}',
        statusCode: e.response?.statusCode,
        responseBody: e.response?.data,
      );
      rethrow;
    } catch (e, st) {
      pushTokenLog('push-token other error', error: 'source=$logSource | $e | $st');
      rethrow;
    }
  }

  /// POST /api/notifications/read-all → 204
  Future<void> markAllRead() async {
    try {
      final token = await _requireFreshToken();
      await _apiClient.dio.post(
        '/api/notifications/read-all',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ??
                errorData['error'] ??
                'Failed to mark all as read')
            : errorData?.toString() ?? 'Failed to mark all as read';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }
}
