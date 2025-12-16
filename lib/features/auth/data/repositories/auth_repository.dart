import 'package:dio/dio.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../models/user_response_dto.dart';
import '../models/user_update_request_dto.dart';

class AuthRepository {
  final ApiClient _apiClient = ApiClient();

  /// Backend'e login isteği gönderir
  /// Firebase idToken Authorization header'ında Bearer token olarak gönderilir
  Future<UserResponseDto> login(String firebaseIdToken) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.post(
        ApiConfig.loginPath,
      );
      return UserResponseDto.fromJson(response.data);
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Login failed')
            : errorData?.toString() ?? 'Login failed';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Backend'e register isteği gönderir
  /// Firebase idToken Authorization header'ında, userName query parameter olarak gönderilir
  Future<UserResponseDto> register(String firebaseIdToken, String userName) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.post(
        ApiConfig.registerPath,
        queryParameters: {'userName': userName},
      );
      return UserResponseDto.fromJson(response.data);
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Registration failed')
            : errorData?.toString() ?? 'Registration failed';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Me endpoint - Authenticated user bilgilerini getirir
  Future<UserResponseDto> getMe(String firebaseIdToken) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.get(ApiConfig.mePath);
      return UserResponseDto.fromJson(response.data);
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to get user info')
            : errorData?.toString() ?? 'Failed to get user info';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Me update endpoint - User bilgilerini günceller
  Future<UserResponseDto> updateMe(
    String firebaseIdToken,
    UserUpdateRequestDto request,
  ) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.put(
        ApiConfig.mePath,
        data: request.toJson(),
      );
      return UserResponseDto.fromJson(response.data);
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Update failed')
            : errorData?.toString() ?? 'Update failed';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }
}

