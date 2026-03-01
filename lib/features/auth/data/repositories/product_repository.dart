import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../models/product_dto.dart';
import '../models/product_search_result_dto.dart';
import 'interaction_repository.dart';

class ProductRepository {
  final ApiClient _apiClient = ApiClient();
  final InteractionRepository _interactionRepository = InteractionRepository();

  /// Paginated home feed from GET /api/products/home?page={page}&size={size}
  Future<ProductSearchResultDto> getHomeFeed({
    required int page,
    int size = 20,
    String? firebaseIdToken,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/products/home',
        queryParameters: {
          'page': page,
          'size': size,
        },
      );

      final result = ProductSearchResultDto.fromJson(
        response.data as Map<String, dynamic>,
      );

      // Optionally enrich with rating/like info (parallel)
      if (result.content.isEmpty) return result;

      final enrichedContent = await _enrichProductsWithInteractionInfo(
        result.content,
        firebaseIdToken: firebaseIdToken,
      );

      return ProductSearchResultDto(
        content: enrichedContent,
        totalElements: result.totalElements,
        totalPages: result.totalPages,
        size: result.size,
        number: result.number,
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ??
                errorData['error'] ??
                'Failed to fetch home feed')
            : errorData?.toString() ?? 'Failed to fetch home feed';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Same as search but no rating/like (fast). For compare list.
  Future<ProductSearchResultDto> searchProductsRaw({
    required String categoryPathPrefix,
    required int page,
    int size = 50,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/products/search',
        queryParameters: {
          'categoryPathPrefix': categoryPathPrefix,
          'page': page,
          'size': size,
        },
      );
      return ProductSearchResultDto.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ??
                errorData['error'] ??
                'Failed to search products')
            : errorData?.toString() ?? 'Failed to search products';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Paginated category/search from
  /// GET /api/products/search?categoryPathPrefix=...&page={page}&size={size}
  Future<ProductSearchResultDto> searchProducts({
    required String categoryPathPrefix,
    required int page,
    int size = 20,
    String? firebaseIdToken,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/products/search',
        queryParameters: {
          'categoryPathPrefix': categoryPathPrefix,
          'page': page,
          'size': size,
        },
      );

      final result = ProductSearchResultDto.fromJson(
        response.data as Map<String, dynamic>,
      );

      if (result.content.isEmpty) return result;

      final enrichedContent = await _enrichProductsWithInteractionInfo(
        result.content,
        firebaseIdToken: firebaseIdToken,
      );

      return ProductSearchResultDto(
        content: enrichedContent,
        totalElements: result.totalElements,
        totalPages: result.totalPages,
        size: result.size,
        number: result.number,
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ??
                errorData['error'] ??
                'Failed to search products')
            : errorData?.toString() ?? 'Failed to search products';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Common helper to attach rating & like info to a list of products
  Future<List<ProductDto>> _enrichProductsWithInteractionInfo(
    List<ProductDto> products, {
    String? firebaseIdToken,
  }) async {
    return Future.wait(
      products.map((product) async {
        try {
          final results = await Future.wait([
            _interactionRepository
                .getProductAverageRating(product.id)
                .catchError((e) {
              if (kDebugMode) {
                debugPrint(
                    'Failed to get rating for product ${product.id}: $e');
              }
              return 0.0;
            }),
            firebaseIdToken != null
                ? _interactionRepository
                    .isProductLiked(firebaseIdToken, product.id)
                    .catchError((e) {
                    if (kDebugMode) {
                      debugPrint(
                          'Failed to get like status for product ${product.id}: $e');
                    }
                    return false;
                  })
                : Future.value(false),
          ]);

          final double avgRating = results[0] as double? ?? 0.0;
          final bool isLikedStatus = results[1] as bool? ?? false;

          return product.copyWith(
            averageRating: avgRating,
            isLiked: isLikedStatus,
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error processing product ${product.id}: $e');
          }
          return product.copyWith(
            averageRating: 0.0,
            isLiked: false,
          );
        }
      }),
    );
  }

  /// Fetches all products from GET /api/products (no rating/like enrichment).
  /// Use for compare list so the page loads fast.
  Future<List<ProductDto>> getAllProductsRaw() async {
    try {
      final response = await _apiClient.dio.get('/api/products');
      if (response.data is List) {
        return (response.data as List)
            .map((json) => ProductDto.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch products')
            : errorData?.toString() ?? 'Failed to fetch products';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Fetches all products from GET /api/products
  /// Optionally includes average rating and like status for each product
  Future<List<ProductDto>> getAllProducts({String? firebaseIdToken}) async {
    try {
      // 1. Ana ürün listesini çek
      final response = await _apiClient.dio.get('/api/products');
      
      if (response.data is List) {
        final baseProducts = (response.data as List)
            .map((json) => ProductDto.fromJson(json as Map<String, dynamic>))
            .toList();
        
        // 2. Her ürün için ek bilgileri (like, rating) paralel olarak çek
        final productsWithRatings = await Future.wait(
          baseProducts.map((product) async {
            try {
              // Paralel olarak iki isteği birden başlatıyoruz
              final results = await Future.wait([
                _interactionRepository.getProductAverageRating(product.id).catchError((e) {
                  if (kDebugMode) {
                    debugPrint('Failed to get rating for product ${product.id}: $e');
                  }
                  return 0.0;
                }),
                // Sadece token varsa like durumunu sor, yoksa direkt false dön
                firebaseIdToken != null 
                  ? _interactionRepository.isProductLiked(firebaseIdToken, product.id).catchError((e) {
                      if (kDebugMode) {
                        debugPrint('Failed to get like status for product ${product.id}: $e');
                      }
                      return false; // Hata durumunda false dön
                    })
                  : Future.value(false), // Token yoksa false dön
              ]);

              // InteractionRepository'den gelen değerleri güvenli bir şekilde al
              final double avgRating = results[0] as double? ?? 0.0;
              final bool isLikedStatus = results[1] as bool? ?? false;

              return product.copyWith(
                averageRating: avgRating,
                isLiked: isLikedStatus,
              );
            } catch (e) {
              if (kDebugMode) {
                debugPrint('Error processing product ${product.id}: $e');
              }
              // Hata olsa bile listeyi bozma, ham veriyi dön (rating ve like null/false olacak)
              return product.copyWith(
                averageRating: 0.0,
                isLiked: false,
              );
            }
          }),
        );
        
        return productsWithRatings;
      }
      
      return [];
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch products')
            : errorData?.toString() ?? 'Failed to fetch products';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Fetches a single product by ID from GET /api/products/{id}
  Future<ProductDto> getProductById(String productId, {String? firebaseIdToken}) async {
    try {
      final response = await _apiClient.dio.get('/api/products/$productId');
      
      final product = ProductDto.fromJson(response.data as Map<String, dynamic>);
      
      // Rating ve like bilgilerini paralel olarak çek
      try {
        final results = await Future.wait([
          _interactionRepository.getProductAverageRating(productId).catchError((e) {
            if (kDebugMode) {
              debugPrint('Failed to get rating for product $productId: $e');
            }
            return 0.0;
          }),
          firebaseIdToken != null 
            ? _interactionRepository.isProductLiked(firebaseIdToken, productId).catchError((e) {
                if (kDebugMode) {
                  debugPrint('Failed to get like status for product $productId: $e');
                }
                return false;
              })
            : Future.value(false),
        ]);

        final double avgRating = results[0] as double? ?? 0.0;
        final bool isLikedStatus = results[1] as bool? ?? false;

        return product.copyWith(
          averageRating: avgRating,
          isLiked: isLikedStatus,
        );
      } catch (e) {
        // Hata durumunda orijinal product'ı döndür ama rating ve like değerlerini set et
        if (kDebugMode) {
          debugPrint('Error getting product details for $productId: $e');
        }
        return product.copyWith(
          averageRating: 0.0,
          isLiked: false,
        );
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch product')
            : errorData?.toString() ?? 'Failed to fetch product';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Same tag products without rating/like (fast). For compare 2nd product list.
  Future<List<ProductDto>> getProductsByTagIdRaw(String tagId) async {
    try {
      final response = await _apiClient.dio.get('/api/products/tag/$tagId');
      if (response.data is List) {
        return (response.data as List)
            .map((json) => ProductDto.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch products')
            : errorData?.toString() ?? 'Failed to fetch products';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Fetches products by tag ID from GET /api/products/tag/{tagId}
  Future<List<ProductDto>> getProductsByTagId(String tagId, {String? firebaseIdToken}) async {
    try {
      final response = await _apiClient.dio.get('/api/products/tag/$tagId');
      
      if (response.data is List) {
        final products = (response.data as List)
            .map((json) => ProductDto.fromJson(json as Map<String, dynamic>))
            .toList();
        
        // Her product için rating ve like bilgilerini paralel olarak çek
        final productsWithRatings = await Future.wait(
          products.map((product) async {
            try {
              final results = await Future.wait([
                _interactionRepository.getProductAverageRating(product.id).catchError((e) {
                  if (kDebugMode) {
                    debugPrint('Failed to get rating for product ${product.id}: $e');
                  }
                  return 0.0;
                }),
                firebaseIdToken != null 
                  ? _interactionRepository.isProductLiked(firebaseIdToken, product.id).catchError((e) {
                      if (kDebugMode) {
                        debugPrint('Failed to get like status for product ${product.id}: $e');
                      }
                      return false;
                    })
                  : Future.value(false),
              ]);

              final double avgRating = results[0] as double? ?? 0.0;
              final bool isLikedStatus = results[1] as bool? ?? false;

              return product.copyWith(
                averageRating: avgRating,
                isLiked: isLikedStatus,
              );
            } catch (e) {
              if (kDebugMode) {
                debugPrint('Error processing product ${product.id}: $e');
              }
              return product.copyWith(
                averageRating: 0.0,
                isLiked: false,
              );
            }
          }),
        );
        
        return productsWithRatings;
      }
      
      return [];
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch products')
            : errorData?.toString() ?? 'Failed to fetch products';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }
}

