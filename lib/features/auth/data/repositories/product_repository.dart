import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/cache/product_memory_cache.dart';
import '../../../../core/utils/exceptions.dart';
import '../../../../core/utils/product_listing_flags.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/firebase_auth_api_interceptor.dart';
import '../models/product_dto.dart';
import '../models/product_search_result_dto.dart';
import 'interaction_repository.dart';

class ProductRepository {
  final ApiClient _apiClient = ApiClient();
  final InteractionRepository _interactionRepository = InteractionRepository();

  /// Ortak sayfalı feed: `ProductSearchResultDto` + rating/like zenginleştirme.
  /// [size] sunucuda en fazla 50 ile sınırlanır.
  Future<ProductSearchResultDto> _getEnrichedPagedFeed({
    required String path,
    required int page,
    int size = 20,
    String? firebaseIdToken,
    bool skipFirebaseAuthOnFeedRequest = false,
  }) async {
    final safeSize = size.clamp(1, 50);
    try {
      final response = await _apiClient.dio.get(
        path,
        queryParameters: {'page': page, 'size': safeSize},
        options:
            skipFirebaseAuthOnFeedRequest
                ? Options(extra: const {kDioExtraSkipFirebaseAuth: true})
                : null,
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
        final errorMessage =
            errorData is Map
                ? (errorData['message'] ??
                    errorData['error'] ??
                    'Failed to load feed')
                : errorData?.toString() ?? 'Failed to load feed';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Paginated home feed from GET /api/products/home?page={page}&size={size}
  Future<ProductSearchResultDto> getHomeFeed({
    required int page,
    int size = 20,
    String? firebaseIdToken,
  }) async {
    return _getEnrichedPagedFeed(
      path: '/api/products/home',
      page: page,
      size: size,
      firebaseIdToken: firebaseIdToken,
    );
  }

  /// Ortak sayfalı feed — enrichment YOK (top picks gibi sadece görsel için hızlı yükleme).
  Future<ProductSearchResultDto> _getRawPagedFeed({
    required String path,
    required int page,
    int size = 20,
    bool skipAuth = false,
  }) async {
    final safeSize = size.clamp(1, 50);
    try {
      final response = await _apiClient.dio.get(
        path,
        queryParameters: {'page': page, 'size': safeSize},
        options: skipAuth
            ? Options(extra: const {kDioExtraSkipFirebaseAuth: true})
            : null,
      );
      return ProductSearchResultDto.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to load feed')
            : errorData?.toString() ?? 'Failed to load feed';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// GET /api/products/feed/trending-reviews — public; son 7 gün yorum trendi.
  Future<ProductSearchResultDto> getTrendingReviewsFeed({
    required int page,
    int size = 20,
    String? firebaseIdToken,
  }) async {
    return _getRawPagedFeed(
      path: '/api/products/feed/trending-reviews',
      page: page,
      size: size,
      skipAuth: true,
    );
  }

  /// GET /api/products/feed/trending-likes-week — public; bu hafta LIKE trendi.
  Future<ProductSearchResultDto> getTrendingLikesWeekFeed({
    required int page,
    int size = 20,
    String? firebaseIdToken,
  }) async {
    return _getRawPagedFeed(
      path: '/api/products/feed/trending-likes-week',
      page: page,
      size: size,
      skipAuth: true,
    );
  }

  /// GET /api/products/feed/personalized — Bearer zorunlu.
  Future<ProductSearchResultDto> getPersonalizedFeed({
    required int page,
    int size = 20,
    required String firebaseIdToken,
  }) async {
    return _getRawPagedFeed(
      path: '/api/products/feed/personalized',
      page: page,
      size: size,
    );
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
        final errorMessage =
            errorData is Map
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
        final errorMessage =
            errorData is Map
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
                      'Failed to get rating for product ${product.id}: $e',
                    );
                  }
                  return 0.0;
                }),
            firebaseIdToken != null
                ? _interactionRepository
                    .isProductLiked(firebaseIdToken, product.id)
                    .catchError((e) {
                      if (kDebugMode) {
                        debugPrint(
                          'Failed to get like status for product ${product.id}: $e',
                        );
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
          return product.copyWith(averageRating: 0.0, isLiked: false);
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
        final errorMessage =
            errorData is Map
                ? (errorData['message'] ??
                    errorData['error'] ??
                    'Failed to fetch products')
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
        final baseProducts =
            (response.data as List)
                .map(
                  (json) => ProductDto.fromJson(json as Map<String, dynamic>),
                )
                .toList();

        // 2. Her ürün için ek bilgileri (like, rating) paralel olarak çek
        final productsWithRatings = await Future.wait(
          baseProducts.map((product) async {
            try {
              // Paralel olarak iki isteği birden başlatıyoruz
              final results = await Future.wait([
                _interactionRepository
                    .getProductAverageRating(product.id)
                    .catchError((e) {
                      if (kDebugMode) {
                        debugPrint(
                          'Failed to get rating for product ${product.id}: $e',
                        );
                      }
                      return 0.0;
                    }),
                // Sadece token varsa like durumunu sor, yoksa direkt false dön
                firebaseIdToken != null
                    ? _interactionRepository
                        .isProductLiked(firebaseIdToken, product.id)
                        .catchError((e) {
                          if (kDebugMode) {
                            debugPrint(
                              'Failed to get like status for product ${product.id}: $e',
                            );
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
              return product.copyWith(averageRating: 0.0, isLiked: false);
            }
          }),
        );

        return productsWithRatings;
      }

      return [];
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage =
            errorData is Map
                ? (errorData['message'] ??
                    errorData['error'] ??
                    'Failed to fetch products')
                : errorData?.toString() ?? 'Failed to fetch products';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Fetches a single product by ID from GET /api/products/{id}
  Future<ProductDto> getProductById(
    String productId, {
    String? firebaseIdToken,
    bool bypassCache = false,
  }) async {
    // Taze GET öncesi eski (aktif sanılan) satırı sil — askı/GET ile çelişen cache dönmesin.
    if (bypassCache) {
      ProductMemoryCache.instance.remove(productId);
    }
    if (!bypassCache) {
      final cached = ProductMemoryCache.instance.peek(productId);
      if (cached != null) {
        return cached;
      }
    }
    try {
      final response = await _apiClient.dio.get('/api/products/$productId');
      final data = response.data as Map<String, dynamic>;
      var product = ProductDto.fromJson(data);
      if (isProductNotListedInResponseJson(data)) {
        product = product.copyWith(isProductNotListed: true);
      }
      // API `suspended` taşımıyorsa boş görsel = vitrin dışı; cache’e “aktif” yazma.
      if (!product.isProductNotListed &&
          isNotListedImpliedByEmptyProductImage(product.imageURL)) {
        product = product.copyWith(isProductNotListed: true);
      }

      // Rating ve like bilgilerini paralel olarak çek
      try {
        final results = await Future.wait([
          _interactionRepository.getProductAverageRating(productId).catchError((
            e,
          ) {
            if (kDebugMode) {
              debugPrint('Failed to get rating for product $productId: $e');
            }
            return 0.0;
          }),
          firebaseIdToken != null
              ? _interactionRepository
                  .isProductLiked(firebaseIdToken, productId)
                  .catchError((e) {
                    if (kDebugMode) {
                      debugPrint(
                        'Failed to get like status for product $productId: $e',
                      );
                    }
                    return false;
                  })
              : Future.value(false),
        ]);

        final double avgRating = results[0] as double? ?? 0.0;
        final bool isLikedStatus = results[1] as bool? ?? false;

        final enriched = product.copyWith(
          averageRating: avgRating,
          isLiked: isLikedStatus,
        );
        ProductMemoryCache.instance.remember(enriched);
        return enriched;
      } catch (e) {
        // Hata durumunda orijinal product'ı döndür ama rating ve like değerlerini set et
        if (kDebugMode) {
          debugPrint('Error getting product details for $productId: $e');
        }
        final fallback = product.copyWith(averageRating: 0.0, isLiked: false);
        ProductMemoryCache.instance.remember(fallback);
        return fallback;
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final code = e.response?.statusCode;
        // Sadece 404 / 401: ürün yok veya bu kaynağa erişim yok (API sözleşmesi).
        if (code == 404 || code == 401) {
          throw ProductNotAvailableException(productId, statusCode: code);
        }
        final errorData = e.response?.data;
        final errorMessage =
            errorData is Map
                ? (errorData['message'] ??
                    errorData['error'] ??
                    'Failed to fetch product')
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
        final errorMessage =
            errorData is Map
                ? (errorData['message'] ??
                    errorData['error'] ??
                    'Failed to fetch products')
                : errorData?.toString() ?? 'Failed to fetch products';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Fetches products by tag ID from GET /api/products/tag/{tagId}
  Future<List<ProductDto>> getProductsByTagId(
    String tagId, {
    String? firebaseIdToken,
  }) async {
    try {
      final response = await _apiClient.dio.get('/api/products/tag/$tagId');

      if (response.data is List) {
        final products =
            (response.data as List)
                .map(
                  (json) => ProductDto.fromJson(json as Map<String, dynamic>),
                )
                .toList();

        // Her product için rating ve like bilgilerini paralel olarak çek
        final productsWithRatings = await Future.wait(
          products.map((product) async {
            try {
              final results = await Future.wait([
                _interactionRepository
                    .getProductAverageRating(product.id)
                    .catchError((e) {
                      if (kDebugMode) {
                        debugPrint(
                          'Failed to get rating for product ${product.id}: $e',
                        );
                      }
                      return 0.0;
                    }),
                firebaseIdToken != null
                    ? _interactionRepository
                        .isProductLiked(firebaseIdToken, product.id)
                        .catchError((e) {
                          if (kDebugMode) {
                            debugPrint(
                              'Failed to get like status for product ${product.id}: $e',
                            );
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
              return product.copyWith(averageRating: 0.0, isLiked: false);
            }
          }),
        );

        return productsWithRatings;
      }

      return [];
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage =
            errorData is Map
                ? (errorData['message'] ??
                    errorData['error'] ??
                    'Failed to fetch products')
                : errorData?.toString() ?? 'Failed to fetch products';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }
}
