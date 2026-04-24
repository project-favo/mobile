import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/firebase_auth_api_interceptor.dart';
import '../../../../core/utils/exceptions.dart';
import '../models/user_response_dto.dart';
import '../models/user_update_request_dto.dart';
import '../models/register_request_dto.dart';

/// [GET /api/users/{userId}/profile-image] — pasif kullanıcı **404**; `/api/users` JSON’undaki
/// URL sızıntısını baskılar (görüntü yalnız bu uçtan kabul edilir).
class UserProfileImageFetch {
  const UserProfileImageFetch._({
    this.memoryBytes,
    this.imageUrl,
    this.isNotFound = false,
  });

  const UserProfileImageFetch.notFound() : this._(isNotFound: true);

  /// Ham görüntü baytları (image/* 200 cevabı).
  factory UserProfileImageFetch.fromBytes(Uint8List b) {
    if (b.isEmpty) return const UserProfileImageFetch.notFound();
    return UserProfileImageFetch._(memoryBytes: b);
  }

  final Uint8List? memoryBytes;
  final String? imageUrl;
  final bool isNotFound;

  bool get hasImage =>
      (memoryBytes != null && memoryBytes!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.trim().isNotEmpty);
}

class AuthRepository {
  final ApiClient _apiClient = ApiClient();

  List<UserResponseDto> _parseUsersListResponse(dynamic data) {
    List<dynamic> rows = const [];
    if (data is List) {
      rows = data;
    } else if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final content = m['content'];
      final users = m['users'];
      final items = m['items'];
      if (content is List) {
        rows = content;
      } else if (users is List) {
        rows = users;
      } else if (items is List) {
        rows = items;
      }
    }
    final out = <UserResponseDto>[];
    for (final row in rows) {
      if (row is! Map) continue;
      try {
        final dto = UserResponseDto.fromJson(Map<String, dynamic>.from(row));
        if (dto.id.trim().isEmpty || dto.userName.trim().isEmpty) continue;
        out.add(dto);
      } catch (_) {}
    }
    return out;
  }

  bool _looksLikeLastPage(dynamic data) {
    if (data is! Map) return false;
    final m = Map<String, dynamic>.from(data);
    final last = m['last'];
    if (last is bool) return last;
    final totalPages = m['totalPages'];
    final number = m['number'];
    if (totalPages is num && number is num) {
      return number >= totalPages - 1;
    }
    return false;
  }

  /// “Ben” endpoint’leri: backend bazen sadece `isActive: false` ile hesap kapatma gönderir.
  /// [getUserById] için **kullanma** (yanıltıcı `isActive` diğer kullanıcılarda da gelebiliyor).
  static UserResponseDto _withAccountDeactivated(UserResponseDto u) {
    if (u.isAccountDeactivated) return u;
    return UserResponseDto(
      id: u.id,
      email: u.email,
      userName: u.userName,
      name: u.name,
      surname: u.surname,
      birthdate: u.birthdate,
      profileImageUrl: u.profileImageUrl,
      profilePhotoData: u.profilePhotoData,
      profilePhotoMimeType: u.profilePhotoMimeType,
      emailVerified: u.emailVerified,
      isAccountInactive: u.isAccountInactive,
      isAccountDeactivated: true,
      isSuspended: u.isSuspended,
    );
  }

  static UserResponseDto _userFromJsonForSelfEndpoint(Object? raw) {
    if (raw is! Map) {
      return UserResponseDto(
        id: '',
        email: '',
        userName: '',
      );
    }
    final m = Map<String, dynamic>.from(raw);
    final u = UserResponseDto.fromJson(m);
    if (u.isAccountDeactivated) return u;
    if (m['isAccountDeactivated'] == true) {
      return _withAccountDeactivated(u);
    }
    if (m['isActive'] is bool && (m['isActive'] as bool) == false) {
      return _withAccountDeactivated(u);
    }
    if (m['active'] is bool && (m['active'] as bool) == false) {
      return _withAccountDeactivated(u);
    }
    return u;
  }

  /// Backend'e login isteği gönderir
  /// Firebase idToken Authorization header'ında Bearer token olarak gönderilir
  Future<UserResponseDto> login(String firebaseIdToken) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.post(
        ApiConfig.loginPath,
      );
      return _userFromJsonForSelfEndpoint(response.data);
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
          return _userFromJsonForSelfEndpoint(Map<String, dynamic>.from(raw));
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

  /// Başka kullanıcının profili. Tüm uçlar **404** (yok) ise [TargetUserNotAvailableException].
  /// 401 burada sayılmaz: çoğu backend’de yetki/yol farkı “kullanıcı yok” değildir; tüm profiller 401
  /// alınca yanlışlıkla herkes [TargetUserNotAvailableException] oluyordu.
  Future<UserResponseDto?> getUserById(
    String firebaseIdToken,
    String userId,
  ) async {
    final paths = <String>[
      '/api/users/$userId',
      '/api/auth/user/$userId',
      '/api/auth/users/$userId',
    ];
    var notFoundHits = 0;
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      for (final path in paths) {
        try {
          final response = await _apiClient.dio.get(path);
          final data = response.data;
          if (data is Map) {
            // Başka kullanıcı: [isActive] yorumlama yok; sadece [UserResponseDto.fromJson].
            return UserResponseDto.fromJson(
              Map<String, dynamic>.from(data),
            );
          }
        } on DioException catch (e) {
          final c = e.response?.statusCode;
          if (c == 404 || c == 410) {
            notFoundHits++;
          }
          continue;
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}
    if (notFoundHits >= paths.length) {
      throw TargetUserNotAvailableException(userId);
    }
    return null;
  }

  Future<List<UserResponseDto>> searchUsers(
    String firebaseIdToken,
    String query, {
    int size = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    _apiClient.setAuthToken(firebaseIdToken);
    final tries = <({String path, Map<String, dynamic>? params})>[
      (path: '/api/users/search', params: {'q': q, 'page': 0, 'size': size}),
      (path: '/api/users/search', params: {'query': q, 'page': 0, 'size': size}),
      (path: '/api/users/search', params: {'keyword': q, 'page': 0, 'size': size}),
      (path: '/api/users/search', params: {'username': q, 'page': 0, 'size': size}),
      (path: '/api/users', params: {'q': q, 'page': 0, 'size': size}),
      (path: '/api/users', params: {'query': q, 'page': 0, 'size': size}),
      (path: '/api/users', params: {'username': q, 'page': 0, 'size': size}),
      (path: '/api/auth/users/search', params: {'q': q, 'page': 0, 'size': size}),
      (path: '/api/auth/users/search', params: {'query': q, 'page': 0, 'size': size}),
      (path: '/api/auth/users/search', params: {'username': q, 'page': 0, 'size': size}),
      (path: '/api/users/search/$q', params: null),
      (path: '/api/auth/users/search/$q', params: null),
    ];

    for (final t in tries) {
      try {
        final response = await _apiClient.dio.get(
          t.path,
          queryParameters: t.params,
        );
        final parsed = _parseUsersListResponse(response.data)
          ..sort((a, b) {
            final aq = a.userName.toLowerCase();
            final bq = b.userName.toLowerCase();
            final ql = q.toLowerCase();
            final aStarts = aq.startsWith(ql) ? 0 : 1;
            final bStarts = bq.startsWith(ql) ? 0 : 1;
            if (aStarts != bStarts) return aStarts - bStarts;
            return aq.compareTo(bq);
          });
        if (parsed.isNotEmpty) return parsed;
      } on DioException {
        continue;
      } catch (_) {
        continue;
      }
    }
    return const [];
  }

  Future<List<UserResponseDto>> fetchUserDirectory(
    String firebaseIdToken, {
    int maxPages = 10,
    int pageSize = 100,
  }) async {
    _apiClient.setAuthToken(firebaseIdToken);
    final seen = <String>{};
    final out = <UserResponseDto>[];
    final routes = <String>[
      '/api/users',
      '/api/users/all',
      '/api/auth/users',
    ];
    for (final route in routes) {
      var hadAnySuccess = false;
      for (var page = 0; page < maxPages; page++) {
        try {
          final response = await _apiClient.dio.get(
            route,
            queryParameters: {'page': page, 'size': pageSize},
          );
          hadAnySuccess = true;
          final parsed = _parseUsersListResponse(response.data);
          for (final u in parsed) {
            if (seen.add(u.id)) {
              out.add(u);
            }
          }
          if (parsed.isEmpty || _looksLikeLastPage(response.data)) break;
        } on DioException {
          break;
        } catch (_) {
          break;
        }
      }
      if (hadAnySuccess && out.isNotEmpty) break;
    }
    return out;
  }

  /// [GET /api/users/{userId}/profile-image] — inactive kullanıcı **404/410**; yalnızca public görünür.
  Future<UserProfileImageFetch?> fetchUserProfileImage(
    String firebaseIdToken,
    String userId,
  ) async {
    final id = userId.trim();
    if (id.isEmpty) return null;
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final r = await _apiClient.dio.get<dynamic>(
        '/api/users/${Uri.encodeComponent(id)}/profile-image',
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (c) => c == 200 || c == 404 || c == 410,
        ),
      );
      final code = r.statusCode;
      if (code == 404 || code == 410) {
        return const UserProfileImageFetch.notFound();
      }
      if (code != 200) return null;
      final data = r.data;
      if (data == null) return null;
      final raw = data is List<int> ? (data is Uint8List ? data : Uint8List.fromList(data)) : null;
      if (raw == null || raw.isEmpty) return const UserProfileImageFetch.notFound();
      final ct = r.headers.value('content-type')?.toLowerCase() ?? '';
      if (ct.contains('json')) {
        try {
          final s = utf8.decode(raw);
          final decoded = jsonDecode(s);
          if (decoded is Map<String, dynamic>) {
            final u = (decoded['url'] ?? decoded['imageUrl'] ?? decoded['profileImageUrl'])
                ?.toString()
                .trim();
            if (u != null && u.isNotEmpty) {
              return UserProfileImageFetch._(imageUrl: u);
            }
          }
        } catch (_) {}
        return const UserProfileImageFetch.notFound();
      }
      if (ct.contains('image/')) {
        return UserProfileImageFetch.fromBytes(raw);
      }
      if (raw.length >= 2 && raw[0] == 0xFF && raw[1] == 0xD8) {
        return UserProfileImageFetch.fromBytes(raw);
      }
      if (raw.length >= 3 &&
          raw[0] == 0x89 &&
          raw[1] == 0x50 &&
          raw[2] == 0x4E) {
        return UserProfileImageFetch.fromBytes(raw);
      }
      return const UserProfileImageFetch.notFound();
    } on DioException catch (e) {
      final c = e.response?.statusCode;
      if (c == 404 || c == 410) {
        return const UserProfileImageFetch.notFound();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Me endpoint - Authenticated user bilgilerini getirir
  Future<UserResponseDto> getMe(String firebaseIdToken) async {
    try {
      _apiClient.setAuthToken(firebaseIdToken);
      final response = await _apiClient.dio.get(ApiConfig.mePath);
      return _userFromJsonForSelfEndpoint(response.data);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        if (m['id'] != null || m['userName'] != null || m['email'] != null) {
          try {
            return _userFromJsonForSelfEndpoint(m);
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
      return _userFromJsonForSelfEndpoint(response.data);
    } on DioException {
      rethrow;
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
      return _userFromJsonForSelfEndpoint(response.data);
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

