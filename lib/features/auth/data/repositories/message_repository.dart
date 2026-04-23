import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/entity_active.dart';
import '../models/message_dto.dart';
import '../models/conversation_dto.dart';
import '../models/unread_count_dto.dart';

class MessageRepository {
  final ApiClient _apiClient = ApiClient();

  /// POST /api/messages/send
  Future<MessageDto> sendMessage({
    int? recipientId,
    int? conversationId,
    required String content,
  }) async {
    try {
      final body = <String, dynamic>{
        'content': content,
      };
      if (recipientId != null) {
        body['recipientId'] = recipientId;
      }
      if (conversationId != null) {
        body['conversationId'] = conversationId;
      }

      final response = await _apiClient.dio.post(
        '/api/messages/send',
        data: body,
      );
      return MessageDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to send message')
            : errorData?.toString() ?? 'Failed to send message';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// GET /api/messages/conversations
  Future<ConversationPageDto> getConversations({
    int page = 0,
    int size = 20,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/messages/conversations',
        queryParameters: {
          'page': page,
          'size': size,
        },
      );
      final raw = ConversationPageDto.fromJson(
        response.data as Map<String, dynamic>,
      );
      final filtered = filterVisibleConversations(raw.content);
      return ConversationPageDto(
        content: filtered,
        totalElements: raw.totalElements,
        totalPages: raw.totalPages,
        size: raw.size,
        number: raw.number,
        first: raw.first,
        last: raw.last,
        empty: filtered.isEmpty,
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to load conversations')
            : errorData?.toString() ?? 'Failed to load conversations';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// GET /api/messages/conversations/{conversationId}
  Future<MessagePageDto> getConversationMessages({
    required int conversationId,
    int page = 0,
    int size = 50,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/messages/conversations/$conversationId',
        queryParameters: {
          'page': page,
          'size': size,
        },
      );
      return MessagePageDto.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to load messages')
            : errorData?.toString() ?? 'Failed to load messages';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// GET /api/messages/unread-count
  Future<UnreadCountDto> getUnreadCount() async {
    try {
      final response = await _apiClient.dio.get('/api/messages/unread-count');
      return UnreadCountDto.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to load unread count')
            : errorData?.toString() ?? 'Failed to load unread count';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }
}

