import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../models/notification_dto.dart';

class NotificationRepository {
  final ApiClient _apiClient = ApiClient();

  /// GET /api/notifications?page=&size=
  Future<NotificationPageDto> getNotifications({
    int page = 0,
    int size = 20,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/notifications',
        queryParameters: {
          'page': page,
          'size': size,
        },
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
      final response = await _apiClient.dio.get('/api/notifications/unread-count');
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
      await _apiClient.dio.patch('/api/notifications/$encoded/read');
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

  /// POST /api/notifications/read-all → 204
  Future<void> markAllRead() async {
    try {
      await _apiClient.dio.post('/api/notifications/read-all');
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
