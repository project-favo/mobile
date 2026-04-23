import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/exceptions.dart';
import '../models/review_dto.dart';

bool _dioMeansReviewAlreadyReported(DioException e) {
  final code = e.response?.statusCode;
  if (code == 409) return true;
  final s = dioResponseDataAsSearchString(e.response?.data).toLowerCase();
  if (s.contains('duplicate')) return true;
  if (s.contains('zaten')) return true;
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

  /// Giriş yapan kullanıcının kendi yorumları - GET /api/reviews/me
  /// Token zorunlu.
  Future<List<ReviewDto>> getMyReviews(String firebaseIdToken) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.get('/api/reviews/me');

      if (response.data is List) {
        return (response.data as List)
            .map((json) => ReviewDto.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      return [];
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

  /// Product'a göre review'ları getirir
  /// GET /api/reviews/product/{productId}
  Future<List<ReviewDto>> getReviewsByProductId(
    String productId, {
    String? firebaseIdToken,
  }) async {
    try {
      if (firebaseIdToken != null) {
        _apiClient.setAuthToken(firebaseIdToken);
      }
      final response = await _apiClient.dio.get('/api/reviews/product/$productId');
      
      if (response.data is List) {
        return (response.data as List)
            .map((json) => ReviewDto.fromJson(json as Map<String, dynamic>))
            .toList();
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
        return (response.data as List)
            .map((json) => ReviewDto.fromJson(json as Map<String, dynamic>))
            .toList();
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
      return ReviewDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response != null) {
        final code = e.response?.statusCode;
        if (code == 404 || code == 401) {
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
      return ReviewDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response != null) {
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
      return ReviewDto.fromJson(response.data as Map<String, dynamic>);
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
      final id = reviewId.trim();
      final notes = request.notes?.trim() ?? '';
      final reportBody = <String, dynamic>{'reason': request.reason};
      if (notes.isNotEmpty) {
        reportBody['description'] = notes;
        reportBody['notes'] = notes;
      }

      try {
        await _apiClient.dio.post(
          '/api/reviews/$id/flag',
          data: request.toJson(),
        );
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        // Eski uç: yalnızca `/report`. Bazı kurulumlarda `/flag` yokken 404/405/401 görülebiliyor.
        if (code == 404 || code == 405 || code == 401) {
          await _apiClient.dio.post(
            '/api/reviews/$id/report',
            data: reportBody,
          );
          return;
        }
        rethrow;
      }
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
}

