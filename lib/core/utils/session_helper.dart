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
  /// Only calls login if session is not established or expired
  /// Returns the Firebase ID token
  Future<String?> ensureSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    // Get token (don't force refresh unless needed)
    final token = await user.getIdToken();
    if (token == null) {
      return null;
    }

    // Check if session is still valid
    if (_sessionEstablished && 
        _lastLoginTime != null && 
        DateTime.now().difference(_lastLoginTime!) < _sessionValidDuration) {
      // Session is still valid, just set the token in header
      ApiClient().setAuthToken(token);
      return token;
    }

    // Session expired or not established, login to backend
    try {
      final apiClient = ApiClient();
      apiClient.setAuthToken(token);
      
      // Call login endpoint to establish session
      await apiClient.dio.post(
        ApiConfig.loginPath,
      );
      
      _sessionEstablished = true;
      _lastLoginTime = DateTime.now();
      
      return token;
    } on DioException catch (e) {
      if (dioExceptionBodyContains(e, 'EMAIL_NOT_VERIFIED')) {
        _sessionEstablished = false;
        _lastLoginTime = null;
        ApiClient().setAuthToken(token);
        return token;
      }
      // If login fails with 401/403, session might be invalid
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        _sessionEstablished = false;
        _lastLoginTime = null;
        // Try to refresh token and login again
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
      // For other errors, assume session might still work with cookies
      // Just set the token and continue
      _sessionEstablished = true;
      _lastLoginTime = DateTime.now();
      return token;
    } catch (_) {
      // On any other error, just set token and hope cookies work
      ApiClient().setAuthToken(token);
      return token;
    }
  }

  /// Gets Firebase ID token and sets it in API client
  /// Does NOT call login endpoint - assumes session exists via cookies
  Future<String?> getTokenAndSetHeader() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    final token = await user.getIdToken();
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

