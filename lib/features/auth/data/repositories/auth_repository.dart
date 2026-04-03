import 'package:dio/dio.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../models/user_response_dto.dart';
import '../models/user_update_request_dto.dart';
import '../models/register_request_dto.dart';

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
    } on DioException {
      rethrow;
    }
  }

  /// Backend'e register isteği gönderir
  /// Firebase idToken Authorization header'ında Bearer token olarak gönderilir
  /// RegisterRequestDto request body'de gönderilir
  /// NOT: Email ve password Firebase'de tutulur, backend'e gönderilmez
  Future<UserResponseDto> register(String firebaseIdToken, RegisterRequestDto request) async {
    try {
      // Token'ı temizle (başındaki/sonundaki boşlukları kaldır)
      final cleanToken = firebaseIdToken.trim();
      
      // Token'ı header'a ekle (Bearer formatında)
      _apiClient.setAuthToken(cleanToken);
      
      // Request body'yi hazırla
      final requestBody = request.toJson();
      
      final response = await _apiClient.dio.post(
        ApiConfig.registerPath,
        data: requestBody,
      );
      return UserResponseDto.fromJson(response.data);
    } on DioException catch (e) {
      if (e.response != null) {
        final statusCode = e.response?.statusCode;
        final errorData = e.response?.data;
        
        String errorMessage;
        if (errorData is Map) {
          errorMessage = errorData['message'] ?? 
                        errorData['error'] ?? 
                        'Registration failed';
        } else if (errorData != null) {
          errorMessage = errorData.toString();
        } else {
          errorMessage = 'Registration failed';
        }
        
        // 403 hatası için özel mesaj
        if (statusCode == 403) {
          errorMessage = 'Access forbidden. Please check your authentication token or contact support.';
        }
        
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

  /// E-posta doğrulama kodu gönderir
  /// Body: { "code": "12345" } — tam 5 hane
  Future<UserResponseDto> verifyEmail(String firebaseIdToken, String code) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.post(
        '/api/auth/verify-email',
        data: {'code': code},
      );
      return UserResponseDto.fromJson(response.data);
    } on DioException catch (e) {
      final errorData = e.response?.data;
      final errorCode = errorData is Map
          ? (errorData['error'] ?? errorData['message'] ?? 'VERIFICATION_FAILED')
          : 'VERIFICATION_FAILED';
      throw Exception(errorCode.toString());
    }
  }

  /// Doğrulama e-postasını yeniden gönderir (60s cooldown)
  Future<void> resendVerification(String firebaseIdToken) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      await _apiClient.dio.post('/api/auth/resend-verification');
    } on DioException catch (e) {
      final errorData = e.response?.data;
      final errorCode = errorData is Map
          ? (errorData['error'] ?? errorData['message'] ?? 'RESEND_FAILED')
          : 'RESEND_FAILED';
      throw Exception(errorCode.toString());
    }
  }

  /// Hesabı siler (backend'de /api/auth/me DELETE)
  Future<void> deleteMe(String firebaseIdToken) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      await _apiClient.dio.delete(ApiConfig.mePath);
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Delete account failed')
            : errorData?.toString() ?? 'Delete account failed';
        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }
}

