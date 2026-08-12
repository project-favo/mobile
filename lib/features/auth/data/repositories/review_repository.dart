import 'package:dio/dio.dart';
import '../../../../core/cache/current_user_cache.dart';
import '../../../../core/cache/product_review_notification_horizon_prefs.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/entity_active.dart';
import '../../../../core/utils/exceptions.dart';
import '../models/my_reviews_page_result_dto.dart';
import '../models/review_dto.dart';

bool _dioMeansReviewAlreadyReported(DioException e) {
  final code = e.response?.statusCode;
  if (code == 409) return true;
  final data = e.response?.data;
  if (data is Map) {
    final m = Map<String, dynamic>.from(data);
    final errorCode = m['errorCode']?.toString().trim().toUpperCase();
    if (errorCode == 'REVIEW_REPORT_ALREADY_SUBMITTED') return true;
    final internalCode = m['internalCode']?.toString().trim();
    if (internalCode == '12007') return true;
  }
  final s = dioResponseDataAsSearchString(data).toLowerCase();
  if (s.contains('already') && s.contains('reported')) return true;
  if (s.contains('zaten') && s.contains('şikayet')) return true;
  if (s.contains('already') &&
      (s.contains('flag') ||
          s.contains('report') ||
          s.contains('şikayet') ||
          s.contains('sikayet'))) {
    return true;
  }
  return false;
}

class ReviewRepository {
  final ApiClient _apiClient = ApiClient();
  static final RegExp _numericIdPattern = RegExp(r'^\d+(?:\.0+)?$');

  static const String reviewSortNewest = 'newest';
  static const String reviewSortMostLiked = 'most_liked';
  static const String reviewSortHighestRating = 'highest_rating';
  static const String reviewSortLowestRating = 'lowest_rating';
  static const String reviewSortTopFollowerAuthor = 'top_follower_author';

  /// Giriş yapan kullanıcının kendi yorumları — GET /api/reviews/me?page=&size=&sort=
  /// Token zorunlu. Sunucu Spring [Page] JSON döner.
  Future<MyReviewsPageResultDto> getMyReviewsPage(
    String firebaseIdToken, {
    int page = 0,
    int size = 20,
    /// Örn. [reviewSortNewest] → `createdAt,desc`, en eski için `createdAt,asc`
    String? sortParam,
  }) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.get(
        '/api/reviews/me',
        queryParameters: <String, dynamic>{
          'page': page,
          'size': size,
          if (sortParam != null && sortParam.isNotEmpty) 'sort': sortParam,
        },
      );

      if (response.data is Map<String, dynamic>) {
        final raw = MyReviewsPageResultDto.fromJson(
          response.data as Map<String, dynamic>,
        );
        final filtered = filterVisibleReviews(raw.content);
        return MyReviewsPageResultDto(
          content: filtered,
          totalElements: raw.totalElements,
          totalPages: raw.totalPages,
          size: raw.size,
          number: raw.number,
        );
      }

      return MyReviewsPageResultDto(
        content: const [],
        totalElements: 0,
        totalPages: 0,
        size: 0,
        number: 0,
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch my reviews')
            : errorData?.toString() ?? 'Failed to fetch my reviews';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// GET /api/reviews/me/average-rating — giriş yapan kullanıcının tüm yorumlarının
  /// ortalama rating'i (sayfalama ile aynı DB filtresi; tek satır, hafif).
  Future<double?> getMyReviewsAverageRating(String firebaseIdToken) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.get(
        '/api/reviews/me/average-rating',
      );
      if (response.data is Map<String, dynamic>) {
        final m = response.data as Map<String, dynamic>;
        final v = m['averageRating'];
        if (v == null) return null;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString());
      }
      return null;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ??
                errorData['error'] ??
                'Failed to fetch review average')
            : errorData?.toString() ?? 'Failed to fetch review average';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  List<ReviewDto> _parseProductReviewsPayload(dynamic data) {
    if (data is List) {
      return (data)
          .map((json) => ReviewDto.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final c = m['content'];
      if (c is List) {
        return c
            .map((json) => ReviewDto.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  /// Product'a göre review'ları getirir
  /// GET /api/reviews/product/{productId}
  /// [page]/[size] Spring sayfalaması; gövde [List] veya [Page] (`content`) olabilir.
  Future<List<ReviewDto>> getReviewsByProductId(
    String productId, {
    String? firebaseIdToken,
    bool? hasMedia,
    bool? isCollaborative,
    String sort = reviewSortNewest,
    int? page,
    int? size,
  }) async {
    try {
      if (firebaseIdToken != null) {
        _apiClient.setAuthToken(firebaseIdToken);
      }
      final response = await _apiClient.dio.get(
        '/api/reviews/product/$productId',
        queryParameters: <String, dynamic>{
          if (hasMedia != null) 'hasMedia': hasMedia,
          if (isCollaborative != null) 'isCollaborative': isCollaborative,
          'sort': sort,
          if (page != null) 'page': page,
          if (size != null) 'size': size,
        },
      );

      final raw = _parseProductReviewsPayload(response.data);
      return filterVisibleReviews(raw);
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch reviews')
            : errorData?.toString() ?? 'Failed to fetch reviews';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Ana sayfa arkadaş baloncuğu: takip edilen farklı yazarları bulmak için yeni + takipçi sıralı
  /// sayfaları birleştirir (tek sıralamada kaçan yazarlar için).
  Future<List<ReviewDto>> getReviewsByProductIdForFriendCardOverlay(
    String productId, {
    required String firebaseIdToken,
    int pageSize = 45,
    int maxPages = 4,
  }) async {
    final byKey = <String, ReviewDto>{};
    void absorb(Iterable<ReviewDto> list) {
      for (final r in list) {
        final id = r.id.trim();
        final k = id.isNotEmpty ? id : '${r.ownerId.trim()}|${r.createdAt.trim()}';
        byKey[k] = r;
      }
    }

    String? firstRowKeyPage0;
    for (var p = 0; p < maxPages; p++) {
      final list = await getReviewsByProductId(
        productId,
        firebaseIdToken: firebaseIdToken,
        sort: reviewSortNewest,
        page: p,
        size: pageSize,
      );
      if (list.isEmpty) break;
      final rowKey = list.first.id.trim().isNotEmpty
          ? list.first.id.trim()
          : '${list.first.ownerId.trim()}|${list.first.createdAt.trim()}';
      if (p == 0) {
        firstRowKeyPage0 = rowKey;
      } else if (rowKey == firstRowKeyPage0) {
        break;
      }
      absorb(list);
      if (list.length < pageSize) break;
    }

    final topSorted = await getReviewsByProductId(
      productId,
      firebaseIdToken: firebaseIdToken,
      sort: reviewSortTopFollowerAuthor,
      page: 0,
      size: pageSize,
    );
    absorb(topSorted);

    final out = byKey.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filterVisibleReviews(out);
  }

  /// Kullanıcıya göre review'ları getirir
  /// GET /api/reviews/user/{userId}
  Future<List<ReviewDto>> getReviewsByUserId(
    String userId, {
    String? firebaseIdToken,
  }) async {
    try {
      if (firebaseIdToken != null) {
        _apiClient.setAuthToken(firebaseIdToken);
      }
      final response = await _apiClient.dio.get('/api/reviews/user/$userId');
      
      if (response.data is List) {
        final list = (response.data as List)
            .map((json) => ReviewDto.fromJson(json as Map<String, dynamic>))
            .toList();
        return filterVisibleReviews(list);
      }
      
      return [];
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch reviews')
            : errorData?.toString() ?? 'Failed to fetch reviews';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// ID'ye göre review getirir
  /// GET /api/reviews/{id}
  Future<ReviewDto> getReviewById(
    String reviewId, {
    String? firebaseIdToken,
  }) async {
    try {
      if (firebaseIdToken != null) {
        _apiClient.setAuthToken(firebaseIdToken);
      }
      final response = await _apiClient.dio.get('/api/reviews/$reviewId');
      final r = ReviewDto.fromJson(response.data as Map<String, dynamic>);
      if (!isReviewEntityVisible(r)) {
        throw ReviewNotAvailableException(reviewId, statusCode: 404);
      }
      return r;
    } on DioException catch (e) {
      if (e.response != null) {
        final code = e.response?.statusCode;
        if (code == 404 ||
            code == 401 ||
            code == 403 ||
            code == 410 ||
            code == 423) {
          throw ReviewNotAvailableException(reviewId, statusCode: code);
        }
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch review')
            : errorData?.toString() ?? 'Failed to fetch review';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// En çok review yazan aktif kullanıcılar (token zorunlu)
  /// GET /api/reviews/top-reviewers?limit=… (varsayılan 5, en fazla 50)
  Future<List<TopReviewerDto>> getTopReviewers(
    String firebaseIdToken, {
    int limit = 5,
  }) async {
    final safe = limit.clamp(1, 50);
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.get(
        '/api/reviews/top-reviewers',
        queryParameters: <String, dynamic>{'limit': safe},
      );
      if (response.data is List) {
        return (response.data as List)
            .map(
              (e) => TopReviewerDto.fromJson(e as Map<String, dynamic>),
            )
            .toList();
      }
      return [];
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to load top reviewers')
            : errorData?.toString() ?? 'Failed to load top reviewers';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Yeni review oluşturur
  /// POST /api/reviews
  Future<ReviewDto> createReview(
    String firebaseIdToken,
    CreateReviewRequestDto request,
  ) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.post(
        '/api/reviews',
        data: request.toJson(),
      );
      final dto = ReviewDto.fromJson(response.data as Map<String, dynamic>);
      final uid = CurrentUserCache.instance.userId?.trim();
      if (uid != null && uid.isNotEmpty) {
        final pid = dto.productId.trim();
        if (pid.isNotEmpty) {
          await ProductReviewNotificationHorizonPrefs.instance
              .applyReviewPosted(viewerId: uid, productId: pid);
        }
      }
      return dto;
    } on DioException catch (e) {
      if (e.response != null) {
        final code = e.response?.statusCode;
        if (code == 409) {
          throw Exception(
            'You have already reviewed this product. Edit your existing review instead.',
          );
        }
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to create review')
            : errorData?.toString() ?? 'Failed to create review';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Review'ı günceller
  /// PUT /api/reviews/{id}
  Future<ReviewDto> updateReview(
    String firebaseIdToken,
    String reviewId,
    UpdateReviewRequestDto request,
  ) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.put(
        '/api/reviews/$reviewId',
        data: request.toJson(),
      );
      final dto = ReviewDto.fromJson(response.data as Map<String, dynamic>);
      final uid = CurrentUserCache.instance.userId?.trim();
      if (uid != null && uid.isNotEmpty) {
        final pid = dto.productId.trim();
        if (pid.isNotEmpty) {
          await ProductReviewNotificationHorizonPrefs.instance
              .applyReviewPosted(viewerId: uid, productId: pid);
        }
      }
      return dto;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to update review')
            : errorData?.toString() ?? 'Failed to update review';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Review'ı siler
  /// DELETE /api/reviews/{id}
  Future<void> deleteReview(
    String firebaseIdToken,
    String reviewId,
  ) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      await _apiClient.dio.delete('/api/reviews/$reviewId');
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to delete review')
            : errorData?.toString() ?? 'Failed to delete review';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Review şikayeti — önce `POST .../report` (mevcut backend), yoksa `POST .../flag`.
  Future<void> reportReview(
    String firebaseIdToken,
    String reviewId,
    ReportReviewRequestDto request,
  ) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final id = _normalizeReviewId(reviewId);
      await _apiClient.dio.post(
        '/api/reviews/$id/flag',
        data: request.toJson(),
      );
    } on DioException catch (e) {
      if (_dioMeansReviewAlreadyReported(e)) {
        throw const ReviewAlreadyReportedException();
      }
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ??
                errorData['error'] ??
                'Failed to submit report')
            : errorData?.toString() ?? 'Failed to submit report';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  String _normalizeReviewId(String raw) {
    final t = raw.trim();
    if (t.isEmpty) {
      throw Exception('Invalid review id');
    }
    if (_numericIdPattern.hasMatch(t)) {
      final dot = t.indexOf('.');
      return dot >= 0 ? t.substring(0, dot) : t;
    }
    return t;
  }
}

