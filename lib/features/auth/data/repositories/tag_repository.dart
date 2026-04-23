import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../models/tag_dto.dart';

class TagChildrenResponse {
  final String id;
  final String name;
  final String? categoryPath;
  final String? parentId;
  final List<TagDto> children;
  final bool isLeaf;

  TagChildrenResponse({
    required this.id,
    required this.name,
    this.categoryPath,
    this.parentId,
    required this.children,
    required this.isLeaf,
  });

  factory TagChildrenResponse.fromJson(Map<String, dynamic> json) {
    return TagChildrenResponse(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      categoryPath: json['categoryPath']?.toString(),
      parentId: json['parentId']?.toString(),
      children: json['children'] != null
          ? (json['children'] as List)
              .map((child) => TagDto.fromJson(child as Map<String, dynamic>))
              .toList()
          : [],
      isLeaf: json['isLeaf'] as bool? ?? false,
    );
  }
}

class TagRepository {
  final ApiClient _apiClient = ApiClient();

  /// Fetches root tags from GET /api/tags/roots
  /// Token optional: backend may allow public access
  Future<List<TagDto>> getRootTags([String? firebaseIdToken]) async {
    try {
      if (firebaseIdToken != null) {
        _apiClient.setAuthToken(firebaseIdToken);
      }
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

  /// Searches tags from GET /api/tags/search?name={query}
  /// Public endpoint, auth not required
  Future<List<TagDto>> searchTags(String query) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/tags/search',
        queryParameters: {'name': query},
      );

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
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to search tags')
            : errorData?.toString() ?? 'Failed to search tags';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// GET /api/tags/{id} — yalnızca **aktif** etiket; pasif/ yok → hata
  Future<TagDto> getTagById(String id, [String? firebaseIdToken]) async {
    if (id.trim().isEmpty) {
      throw Exception('Tag id is empty');
    }
    try {
      if (firebaseIdToken != null) {
        _apiClient.setAuthToken(firebaseIdToken);
      }
      final response = await _apiClient.dio.get('/api/tags/${Uri.encodeComponent(id)}');
      if (response.data is Map) {
        return TagDto.fromJson(response.data as Map<String, dynamic>);
      }
      throw Exception('Invalid tag response');
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Tag not found')
            : errorData?.toString() ?? 'Tag not found';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// GET /api/tags/path?categoryPath=... — yalnızca **aktif** ağaç; pasif yol → 404 vb.
  Future<TagDto?> getTagByCategoryPath(
    String categoryPath, [
    String? firebaseIdToken,
  ]) async {
    final q = categoryPath.trim();
    if (q.isEmpty) return null;
    try {
      if (firebaseIdToken != null) {
        _apiClient.setAuthToken(firebaseIdToken);
      }
      final response = await _apiClient.dio.get(
        '/api/tags/path',
        queryParameters: {'categoryPath': q},
      );
      if (response.data is Map) {
        return TagDto.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// GET /api/tags/parent/{parentId}/children — parent **aktif** değilse sonuç yok; çocuklar aktif.
  /// Token optional: backend may allow public access
  Future<TagChildrenResponse> getTagChildren(String parentId, [String? firebaseIdToken]) async {
    try {
      if (firebaseIdToken != null) {
        _apiClient.setAuthToken(firebaseIdToken);
      }
      final response = await _apiClient.dio.get(
        '/api/tags/parent/${Uri.encodeComponent(parentId)}/children',
      );
      
      if (response.data is Map) {
        return TagChildrenResponse.fromJson(response.data as Map<String, dynamic>);
      }
      
      throw Exception('Invalid response format');
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to fetch tag children')
            : errorData?.toString() ?? 'Failed to fetch tag children';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Recursively collects all leaf tag IDs from a given tag
  /// Returns list of all leaf tag IDs (tags that have products)
  /// Optimized with parallel processing
  Future<List<String>> getAllLeafTagIds(String tagId, String firebaseIdToken) async {
    final leafTagIds = <String>[];
    
    try {
      final tagChildren = await getTagChildren(tagId, firebaseIdToken);
      
      if (tagChildren.isLeaf) {
        // This tag is a leaf, add it to the list
        leafTagIds.add(tagId);
      } else {
        // This tag has children, recursively get all leaf tags in PARALLEL
        if (tagChildren.children.isNotEmpty) {
          final childLeafTagsResults = await Future.wait(
            tagChildren.children.map((child) => 
              getAllLeafTagIds(child.id, firebaseIdToken).catchError((e) {
                // If one child fails, return empty list and continue with others
                return <String>[];
              })
            ),
          );
          
          // Combine all results
          for (final childLeafTags in childLeafTagsResults) {
            leafTagIds.addAll(childLeafTags);
          }
        }
      }
    } catch (e) {
      // If error occurs, just return what we have so far
      // This prevents one error from breaking the entire process
    }
    
    return leafTagIds;
  }
}

