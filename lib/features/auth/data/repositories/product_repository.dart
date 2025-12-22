import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../models/product_dto.dart';

class ProductRepository {
  final ApiClient _apiClient = ApiClient();

  /// Fetches all products from GET /api/products
  Future<List<ProductDto>> getAllProducts() async {
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
}

