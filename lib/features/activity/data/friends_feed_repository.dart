import 'package:dio/dio.dart';

import '../../../core/cache/current_user_cache.dart';
import '../../../core/cache/follow_notification_horizon_prefs.dart';
import '../../../core/config/list_paging.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/session_helper.dart';
import '../../auth/data/services/auth_service.dart';
import '../../auth/data/utils/notification_remote_user_filter.dart';
import 'friends_feed_dto.dart';

class FriendsFeedRepository {
  final ApiClient _apiClient = ApiClient();
  final SessionHelper _sessionHelper = SessionHelper();
  final AuthService _auth = AuthService();

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
    int size = kStandardListPageSize,
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
      final raw = FriendsFeedPageDto.fromJson(
        response.data as Map<String, dynamic>,
      );
      var content = await filterFriendsFeedHidingUnlistedActors(
        raw.content,
        _auth,
      );
      final me = CurrentUserCache.instance.userId?.trim();
      if (me != null && me.isNotEmpty) {
        final horizons =
            await FollowNotificationHorizonPrefs.instance.loadHorizonsUtc(me);
        if (horizons.isNotEmpty) {
          content = content
              .where((e) {
                final aid = e.actorUserId.trim();
                if (aid.isEmpty) return true;
                final h = horizons[aid];
                if (h == null) return true;
                final at = e.createdAt;
                if (at == null) return true;
                return !at.toUtc().isBefore(h);
              })
              .toList();
        }
        content = await filterFriendsFeedByProductReviewHorizon(content, me);
      }
      return FriendsFeedPageDto(
        content: content,
        totalElements: raw.totalElements,
        totalPages: raw.totalPages,
        size: raw.size,
        number: raw.number,
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
