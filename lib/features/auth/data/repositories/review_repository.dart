import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../models/review_dto.dart';

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
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch review')
            : errorData?.toString() ?? 'Failed to fetch review';
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
}

