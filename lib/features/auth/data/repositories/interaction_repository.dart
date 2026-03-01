import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../models/product_dto.dart';

class InteractionRepository {
  final ApiClient _apiClient = ApiClient();

  /// Product'a like/unlike yapar
  /// Returns: { "liked": true/false }
  Future<bool> toggleProductLike(String firebaseIdToken, String productId) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.post('/api/interactions/product/$productId/like');
      
      if (response.data is Map) {
        return response.data['liked'] as bool? ?? false;
      }
      
      return false;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to toggle like')
            : errorData?.toString() ?? 'Failed to toggle like';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Review'a like/unlike yapar
  /// Returns: { "liked": true/false }
  Future<bool> toggleReviewLike(String firebaseIdToken, String reviewId) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.post('/api/interactions/review/$reviewId/like');
      
      if (response.data is Map) {
        return response.data['liked'] as bool? ?? false;
      }
      
      return false;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to toggle like')
            : errorData?.toString() ?? 'Failed to toggle like';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Product'ın like sayısını getirir
  /// Returns: { "count": 42 }
  Future<int> getProductLikeCount(String productId) async {
    try {
      final response = await _apiClient.dio.get('/api/interactions/product/$productId/like-count');
      
      if (response.data is Map) {
        return (response.data['count'] as num?)?.toInt() ?? 0;
      }
      
      return 0;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to get like count')
            : errorData?.toString() ?? 'Failed to get like count';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Review'ın like sayısını getirir
  /// Returns: { "count": 15 }
  Future<int> getReviewLikeCount(String reviewId) async {
    try {
      final response = await _apiClient.dio.get('/api/interactions/review/$reviewId/like-count');
      
      if (response.data is Map) {
        return (response.data['count'] as num?)?.toInt() ?? 0;
      }
      
      return 0;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to get like count')
            : errorData?.toString() ?? 'Failed to get like count';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Kullanıcının product'ı beğenip beğenmediğini kontrol eder
  /// Returns: { "isLiked": true/false }
  Future<bool> isProductLiked(String? firebaseIdToken, String productId) async {
    try {
      if (firebaseIdToken != null) {
        _apiClient.setAuthToken(firebaseIdToken);
      }
      final response = await _apiClient.dio.get('/api/interactions/product/$productId/is-liked');
      
      if (response.data is Map) {
        return response.data['isLiked'] as bool? ?? false;
      }
      
      return false;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to check like status')
            : errorData?.toString() ?? 'Failed to check like status';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Kullanıcının review'ı beğenip beğenmediğini kontrol eder
  /// Returns: { "isLiked": true/false }
  Future<bool> isReviewLiked(String? firebaseIdToken, String reviewId) async {
    try {
      if (firebaseIdToken != null) {
        _apiClient.setAuthToken(firebaseIdToken);
      }
      final response = await _apiClient.dio.get('/api/interactions/review/$reviewId/is-liked');
      
      if (response.data is Map) {
        return response.data['isLiked'] as bool? ?? false;
      }
      
      return false;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to check like status')
            : errorData?.toString() ?? 'Failed to check like status';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Product'a rating verir (1-5 arası)
  /// Request Body: { "rating": 4 }
  /// Returns: { "rating": 4 }
  Future<int> rateProduct(String firebaseIdToken, String productId, int rating) async {
    try {
      if (rating < 1 || rating > 5) {
        throw Exception('Rating must be between 1 and 5');
      }
      
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.post(
        '/api/interactions/product/$productId/rating',
        data: {'rating': rating},
      );
      
      if (response.data is Map) {
        return (response.data['rating'] as num?)?.toInt() ?? 0;
      }
      
      return 0;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to rate product')
            : errorData?.toString() ?? 'Failed to rate product';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Product'ın ortalama rating'ini getirir
  /// Returns: { "averageRating": 4.5, "productId": 123 }
  Future<double> getProductAverageRating(String productId) async {
    try {
      final response = await _apiClient.dio.get('/api/interactions/product/$productId/average-rating');

      if (response.data is Map) {
        final ratingValue = response.data['averageRating'];
        if (ratingValue == null) return 0.0;

        double rating;
        if (ratingValue is num) {
          rating = ratingValue.toDouble();
        } else if (ratingValue is String) {
          rating = double.tryParse(ratingValue) ?? 0.0;
        } else {
          rating = 0.0;
        }
        return rating.clamp(0.0, 5.0);
      }
      return 0.0;
    } on DioException catch (e) {
      // 404 veya diğer hatalar için 0.0 döndür (rating yoksa)
      if (e.response?.statusCode == 404) {
        return 0.0;
      }
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to get average rating')
            : errorData?.toString() ?? 'Failed to get average rating';
        // Hata durumunda 0.0 döndür (rating gösterilmez)
        if (kDebugMode) {
          debugPrint('Failed to get rating for product $productId: $errorMessage');
        }
        return 0.0;
      }
      if (kDebugMode) {
        debugPrint('Network error getting rating for product $productId: ${e.message}');
      }
      return 0.0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Unexpected error getting rating for product $productId: $e');
      }
      return 0.0;
    }
  }

  /// Kullanıcının product'a verdiği rating'i getirir
  /// Returns: { "rating": 4 } veya { "rating": null }
  Future<int?> getUserProductRating(String? firebaseIdToken, String productId) async {
    try {
      if (firebaseIdToken != null) {
        _apiClient.setAuthToken(firebaseIdToken);
      }
      final response = await _apiClient.dio.get('/api/interactions/product/$productId/user-rating');
      
      if (response.data is Map) {
        final rating = response.data['rating'];
        if (rating == null) return null;
        return (rating as num?)?.toInt();
      }
      
      return null;
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to get user rating')
            : errorData?.toString() ?? 'Failed to get user rating';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Kullanıcının wishlist'ini (beğendiği ürünler) getirir
  /// GET /api/interactions/me/wishlist?page=0&size=20
  Future<List<ProductDto>> getMyWishlist(
    String firebaseIdToken, {
    int page = 0,
    int size = 20,
  }) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.get(
        '/api/interactions/me/wishlist',
        queryParameters: {
          'page': page,
          'size': size,
        },
      );

      if (response.data is Map && response.data['content'] is List) {
        final content = response.data['content'] as List;
        final products = <ProductDto>[];
        for (final raw in content) {
          final item = raw as Map<String, dynamic>;
          ProductDto product;
          DateTime? date;

          // API'den likedAt (beğenme tarihi) gelir; yoksa diğer tarih alanlarına bakılır
          if (item['product'] != null && item['product'] is Map) {
            product = ProductDto.fromJson(item['product'] as Map<String, dynamic>);
            final dateStr = item['likedAt']?.toString() ?? item['addedAt']?.toString() ?? item['createdAt']?.toString() ?? item['created_at']?.toString();
            if (dateStr != null) date = DateTime.tryParse(dateStr);
          } else {
            product = ProductDto.fromJson(item);
            date = item['likedAt'] != null ? DateTime.tryParse(item['likedAt'].toString()) : product.createdAt;
          }

          if (date != null) {
            product = product.copyWith(createdAt: date);
          }
          products.add(product);
        }

        return products;
      }

      return [];
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch wishlist')
            : errorData?.toString() ?? 'Failed to fetch wishlist';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }
}

