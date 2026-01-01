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
      final response = await _apiClient.dio.get('/api/products');
      
      if (response.data is List) {
        final products = (response.data as List)
            .map((json) => ProductDto.fromJson(json as Map<String, dynamic>))
            .toList();
        
        // Her product için rating ve like bilgilerini çek
        final productsWithRatings = await Future.wait(
          products.map((product) async {
            try {
              // Average rating'i çek
              double averageRating = 0.0;
              try {
                averageRating = await _interactionRepository.getProductAverageRating(product.id);
              } catch (e) {
                // Rating çekilemezse 0.0 kullan
                print('Failed to get rating for product ${product.id}: $e');
                averageRating = 0.0;
              }
              
              // Like durumunu çek (eğer kullanıcı authenticated ise)
              bool? isLiked;
              if (firebaseIdToken != null) {
                try {
                  isLiked = await _interactionRepository.isProductLiked(firebaseIdToken, product.id);
                } catch (e) {
                  // Like durumu çekilemezse null bırak
                  print('Failed to get like status for product ${product.id}: $e');
                  isLiked = null;
                }
              }
              
              return ProductDto(
                id: product.id,
                name: product.name,
                imageURL: product.imageURL,
                description: product.description,
                tag: product.tag,
                // averageRating'i her zaman set et (0.0 olsa bile, null değil)
                averageRating: averageRating,
                isLiked: isLiked,
              );
            } catch (e) {
              // Hata durumunda orijinal product'ı döndür ama rating ve like null olabilir
              print('Error processing product ${product.id}: $e');
              return product;
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
      
      // Rating ve like bilgilerini çek
      try {
        final averageRating = await _interactionRepository.getProductAverageRating(productId);
        bool? isLiked;
        if (firebaseIdToken != null) {
          isLiked = await _interactionRepository.isProductLiked(firebaseIdToken, productId);
        }
        
        return ProductDto(
          id: product.id,
          name: product.name,
          imageURL: product.imageURL,
          description: product.description,
          tag: product.tag,
          // averageRating'i her zaman set et (0.0 olsa bile, null değil)
          averageRating: averageRating,
          isLiked: isLiked,
        );
      } catch (e) {
        // Hata durumunda orijinal product'ı döndür
        return product;
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
        
        // Her product için rating ve like bilgilerini çek
        final productsWithRatings = await Future.wait(
          products.map((product) async {
            try {
              final averageRating = await _interactionRepository.getProductAverageRating(product.id);
              bool? isLiked;
              if (firebaseIdToken != null) {
                isLiked = await _interactionRepository.isProductLiked(firebaseIdToken, product.id);
              }
              
              return ProductDto(
                id: product.id,
                name: product.name,
                imageURL: product.imageURL,
                description: product.description,
                tag: product.tag,
                // averageRating'i her zaman set et (0.0 olsa bile, null değil)
                averageRating: averageRating,
                isLiked: isLiked,
              );
            } catch (e) {
              return product;
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

