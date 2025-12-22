import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../models/tag_dto.dart';

class TagRepository {
  final ApiClient _apiClient = ApiClient();

  /// Fetches root tags from GET /api/tags/roots
  /// Requires authentication - Firebase ID token must be provided
  Future<List<TagDto>> getRootTags(String firebaseIdToken) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.get('/api/tags/roots');
      
      if (response.data is List) {
        return (response.data as List)
            .map((json) => TagDto.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      
      return [];
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch tags')
            : errorData?.toString() ?? 'Failed to fetch tags';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }
}

