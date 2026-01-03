import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../models/product_dto.dart';
import 'interaction_repository.dart';

class ProductRepository {
  final ApiClient _apiClient = ApiClient();
  final InteractionRepository _interactionRepository = InteractionRepository();

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
                  print('Failed to get rating for product ${product.id}: $e');
                  return 0.0;
                }),
                // Sadece token varsa like durumunu sor, yoksa direkt false dön
                firebaseIdToken != null 
                  ? _interactionRepository.isProductLiked(firebaseIdToken, product.id).catchError((e) {
                      print('Failed to get like status for product ${product.id}: $e');
                      return false; // Hata durumunda false dön
                    })
                  : Future.value(false), // Token yoksa false dön
              ]);

              // InteractionRepository'den gelen değerleri güvenli bir şekilde al
              final double avgRating = results[0] as double? ?? 0.0;
              final bool isLikedStatus = results[1] as bool? ?? false;

              print('📦 ProductRepository - Product ${product.id} (${product.name}):');
              print('   avgRating from backend: $avgRating');
              print('   isLikedStatus: $isLikedStatus');

              // copyWith kullanarak yeni DTO oluştur
              final updatedProduct = product.copyWith(
                averageRating: avgRating,
                isLiked: isLikedStatus,
              );
              
              print('   Updated product averageRating: ${updatedProduct.averageRating}');
              
              return updatedProduct;
            } catch (e) {
              print('Error processing product ${product.id}: $e');
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
            print('Failed to get rating for product $productId: $e');
            return 0.0;
          }),
          firebaseIdToken != null 
            ? _interactionRepository.isProductLiked(firebaseIdToken, productId).catchError((e) {
                print('Failed to get like status for product $productId: $e');
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
        print('Error getting product details for $productId: $e');
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
                  print('Failed to get rating for product ${product.id}: $e');
                  return 0.0;
                }),
                firebaseIdToken != null 
                  ? _interactionRepository.isProductLiked(firebaseIdToken, product.id).catchError((e) {
                      print('Failed to get like status for product ${product.id}: $e');
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
              print('Error processing product ${product.id}: $e');
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

