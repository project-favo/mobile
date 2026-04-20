import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/session_helper.dart';
import 'friends_feed_dto.dart';

class FriendsFeedRepository {
  final ApiClient _apiClient = ApiClient();
  final SessionHelper _sessionHelper = SessionHelper();

  Future<String> _requireFreshToken() async {
    final t = await _sessionHelper.ensureSession();
    if (t == null) {
      throw Exception('Please sign in to continue.');
    }
    _apiClient.setAuthToken(t);
    return t;
  }

  Future<FriendsFeedPageDto> getFriendsFeed({
    int page = 0,
    int size = 20,
  }) async {
    final safePage = page < 0 ? 0 : page;
    final safeSize = size.clamp(1, 50);
    try {
      final token = await _requireFreshToken();
      final response = await _apiClient.dio.get(
        '/api/products/feed/friends',
        queryParameters: {
          'page': safePage,
          'size': safeSize,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      return FriendsFeedPageDto.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ??
                errorData['error'] ??
                'Failed to load friend activity')
            : errorData?.toString() ?? 'Failed to load friend activity';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }
}
