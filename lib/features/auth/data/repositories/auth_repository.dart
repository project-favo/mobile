import 'package:dio/dio.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/firebase_auth_api_interceptor.dart';
import '../../../../core/utils/exceptions.dart';
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
      final raw = response.data;
      try {
        if (raw is Map) {
          return UserResponseDto.fromJson(Map<String, dynamic>.from(raw));
        }
      } catch (_) {}
      return UserResponseDto(
        id: '',
        email: '',
        userName: request.userName,
        emailVerified: false,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 503) {
        rethrow;
      }
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
        if (statusCode == 401) {
          errorMessage =
              'Unauthorized (401). Confirm the request URL is POST ${ApiConfig.registerPath} '
              'and you are signed in to Firebase so a fresh ID token is sent.';
        }

        throw Exception(errorMessage);
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Başka kullanıcının profili (avatar için). Backend path’i yoksa null döner.
  Future<UserResponseDto?> getUserById(
    String firebaseIdToken,
    String userId,
  ) async {
    final paths = <String>[
      '/api/users/$userId',
      '/api/auth/user/$userId',
      '/api/auth/users/$userId',
    ];
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      for (final path in paths) {
        try {
          final response = await _apiClient.dio.get(path);
          final data = response.data;
          if (data is Map) {
            return UserResponseDto.fromJson(
              Map<String, dynamic>.from(data),
            );
          }
        } on DioException {
          // Bir uç 403/404 dönerse diğer path'leri dene (policy farkı sık görülür).
          continue;
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Me endpoint - Authenticated user bilgilerini getirir
  Future<UserResponseDto> getMe(String firebaseIdToken) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.get(ApiConfig.mePath);
      return UserResponseDto.fromJson(response.data);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        if (m['id'] != null || m['userName'] != null || m['email'] != null) {
          try {
            return UserResponseDto.fromJson(m);
          } catch (_) {}
        }
      }
      if (e.response != null) {
        final errorData = e.response?.data;
        final errorMessage = errorData is Map
            ? (errorData['message'] ?? errorData['error'] ?? 'Failed to get user info')
            : errorData?.toString() ?? 'Failed to get user info';
        if (dioResponseDataAsSearchString(errorData)
            .toUpperCase()
            .contains('EMAIL_NOT_VERIFIED')) {
          throw Exception('EMAIL_NOT_VERIFIED');
        }
        throw Exception(errorMessage.toString());
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

  /// Backend e-posta kodu: `POST /api/auth/verify-email`, body `{ "code": "12345" }` (tam 5 rakam).
  Future<UserResponseDto> verifyEmail(String firebaseIdToken, String code) async {
    final normalized = code.trim();
    if (!RegExp(r'^\d{5}$').hasMatch(normalized)) {
      throw Exception('INVALID_CODE_FORMAT');
    }
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.post(
        ApiConfig.verifyEmailPath,
        data: {'code': normalized},
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

  /// `POST /api/auth/forgot-password` — public; Authorization gönderilmez.
  /// Başarı: 202 + `{ "message": "..." }`; hesap yoksa da aynı (enumeration yok).
  Future<String> forgotPassword(String email) async {
    final addr = email.trim();
    if (addr.isEmpty) {
      throw Exception('Email is required');
    }
    final dio = _apiClient.dio;
    try {
      // Oturum açıkken bile Bearer gönderilmemeli: [attachFirebaseIdTokenToAllRequests] bunu atlar.
      final response = await dio.post(
        ApiConfig.forgotPasswordPath,
        data: {'email': addr},
        options: Options(
          extra: {kDioExtraSkipFirebaseAuth: true},
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 202 || (status >= 200 && status < 300)) {
        final raw = response.data;
        if (raw is Map) {
          final m = raw['message']?.toString().trim();
          if (m != null && m.isNotEmpty) return m;
        }
        return 'If an account exists for this email, password reset instructions were sent.';
      }
      throw Exception('Request could not be completed');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      if (code == 400) {
        final msg = data is Map
            ? (data['message'] ?? data['error'] ?? 'Invalid email')
            : 'Invalid email';
        throw Exception(msg.toString());
      }
      if (e.response != null) {
        final msg = data is Map
            ? (data['message'] ?? data['error'] ?? 'Request failed')
            : data?.toString() ?? 'Request failed';
        throw Exception(msg.toString());
      }
      throw Exception(e.message ?? 'Network error');
    }
  }

  /// `POST /api/auth/resend-verification` (Bearer + isteğe bağlı `{ "email": "..." }`).
  Future<void> resendVerification(
    String firebaseIdToken, {
    String? email,
  }) async {
    _apiClient.setAuthToken(firebaseIdToken);
    final body = <String, dynamic>{};
    final addr = email?.trim();
    if (addr != null && addr.isNotEmpty) {
      body['email'] = addr;
    }
    await _apiClient.dio.post(
      ApiConfig.resendVerificationPath,
      data: body,
    );
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

