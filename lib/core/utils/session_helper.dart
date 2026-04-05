import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../config/api_config.dart';
import 'exceptions.dart';

/// Session management helper
/// Handles backend session establishment and token management
class SessionHelper {
  static final SessionHelper _instance = SessionHelper._internal();
  factory SessionHelper() => _instance;
  SessionHelper._internal();

  bool _sessionEstablished = false;
  DateTime? _lastLoginTime;
  static const Duration _sessionValidDuration = Duration(minutes: 30);

  /// Ensures backend session is established
  /// Firebase token is always refreshed with [getIdToken(true)]; backend login
  /// is only repeated when the local session window expired.
  Future<String?> ensureSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    final freshToken = await user.getIdToken(true);
    if (freshToken == null) {
      return null;
    }

    ApiClient().setAuthToken(freshToken);

    if (_sessionEstablished &&
        _lastLoginTime != null &&
        DateTime.now().difference(_lastLoginTime!) < _sessionValidDuration) {
      return freshToken;
    }

    try {
      final apiClient = ApiClient();
      await apiClient.dio.post(
        ApiConfig.loginPath,
      );

      _sessionEstablished = true;
      _lastLoginTime = DateTime.now();

      return freshToken;
    } on DioException catch (e) {
      if (dioExceptionBodyContains(e, 'EMAIL_NOT_VERIFIED')) {
        _sessionEstablished = false;
        _lastLoginTime = null;
        final t = await user.getIdToken(true);
        if (t != null) {
          ApiClient().setAuthToken(t);
        }
        return t;
      }
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        _sessionEstablished = false;
        _lastLoginTime = null;
        try {
          final refreshedToken = await user.getIdToken(true);
          if (refreshedToken != null) {
            final apiClient = ApiClient();
            apiClient.setAuthToken(refreshedToken);
            await apiClient.dio.post(ApiConfig.loginPath);
            _sessionEstablished = true;
            _lastLoginTime = DateTime.now();
            return refreshedToken;
          }
        } catch (_) {
          // Ignore refresh errors
        }
      }
      _sessionEstablished = true;
      _lastLoginTime = DateTime.now();
      return freshToken;
    } catch (_) {
      ApiClient().setAuthToken(freshToken);
      return freshToken;
    }
  }

  /// Gets Firebase ID token and sets it in API client
  Future<String?> getTokenAndSetHeader() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    final token = await user.getIdToken(true);
    if (token != null) {
      ApiClient().setAuthToken(token);
    }
    return token;
  }

  /// Clears session state (on logout)
  void clearSession() {
    _sessionEstablished = false;
    _lastLoginTime = null;
    ApiClient().clearAuthToken();
  }

  /// Forces session refresh (call login endpoint)
  Future<String?> refreshSession() async {
    _sessionEstablished = false;
    _lastLoginTime = null;
    return await ensureSession();
  }
}
