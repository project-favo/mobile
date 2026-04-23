import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../routes/app_routes.dart';
import '../network/api_client.dart';
import '../config/api_config.dart';
import 'exceptions.dart';
import 'review_report_storage.dart';
import '../cache/app_session_cache.dart';

/// Session management helper
/// Handles backend session establishment and token management
class SessionHelper {
  static final SessionHelper _instance = SessionHelper._internal();
  factory SessionHelper() => _instance;
  SessionHelper._internal();

  bool _sessionEstablished = false;
  DateTime? _lastLoginTime;
  static const Duration _sessionValidDuration = Duration(minutes: 30);
  static const Duration _accountStatusCheckInterval = Duration(seconds: 60);
  static const String _deactivatedTitle = 'Account Deactivated';
  static const String _deactivatedNotice =
      'Your account has been deactivated by admin.\n\n'
      'For help, please contact: ctis411.09@gmail.com';
  Timer? _accountStatusTimer;
  bool _isHandlingDeactivatedState = false;

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
    startAccountStatusMonitoring();

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
      if (_looksLikeDeactivatedAccountFromDio(e)) {
        await _handleAccountDeactivated();
        throw const DeactivatedAccountException();
      }
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
            startAccountStatusMonitoring();
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
      startAccountStatusMonitoring();
    }
    return token;
  }

  /// Clears session state (on logout)
  void clearSession() {
    _sessionEstablished = false;
    _lastLoginTime = null;
    _accountStatusTimer?.cancel();
    _accountStatusTimer = null;
    ReviewReportStorage.clearMemory();
    ApiClient().clearAuthToken();
  }

  /// Call after a successful `POST /api/auth/login` elsewhere (e.g. [AuthService.establishBackendSession])
  /// so [ensureSession] does not immediately repeat login.
  void markBackendLoginSucceeded() {
    _sessionEstablished = true;
    _lastLoginTime = DateTime.now();
    startAccountStatusMonitoring();
  }

  /// Forces session refresh (call login endpoint)
  Future<String?> refreshSession() async {
    _sessionEstablished = false;
    _lastLoginTime = null;
    return await ensureSession();
  }

  void startAccountStatusMonitoring() {
    _accountStatusTimer?.cancel();
    _accountStatusTimer = Timer.periodic(
      _accountStatusCheckInterval,
      (_) => unawaited(_checkAccountStatus()),
    );
  }

  Future<void> _checkAccountStatus() async {
    if (_isHandlingDeactivatedState) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      clearSession();
      return;
    }
    try {
      final token = await user.getIdToken(true);
      if (token == null) return;
      ApiClient().setAuthToken(token);
      final response = await ApiClient().dio.get(ApiConfig.mePath);
      if (_looksLikeDeactivatedAccountFromMe(response.data)) {
        await _handleAccountDeactivated();
      }
    } on DioException catch (e) {
      if (_looksLikeDeactivatedAccountFromDio(e)) {
        await _handleAccountDeactivated();
      }
    } catch (_) {}
  }

  bool _looksLikeDeactivatedAccountFromMe(dynamic data) {
    if (data is! Map) return false;
    final map = Map<String, dynamic>.from(data);
    if (map['isAccountDeactivated'] is bool &&
        (map['isAccountDeactivated'] as bool)) {
      return true;
    }
    final status = map['status']?.toString().toLowerCase() ?? '';
    final active = map['active'];
    final enabled = map['enabled'];
    final isActive = map['isActive'];
    if (status == 'deactivated' || status == 'inactive' || status == 'suspended') {
      return true;
    }
    if (active is bool && !active) return true;
    if (enabled is bool && !enabled) return true;
    if (isActive is bool && !isActive) return true;
    return false;
  }

  bool _looksLikeDeactivatedAccountFromDio(DioException e) {
    final code = e.response?.statusCode ?? 0;
    final body = dioResponseDataAsSearchString(e.response?.data);
    if (looksLikeDeactivatedAccountMessage(body)) return true;
    return (code == 403 || code == 423) &&
        looksLikeDeactivatedAccountMessage(e.message ?? '');
  }

  Future<void> _handleAccountDeactivated() async {
    if (_isHandlingDeactivatedState) return;
    _isHandlingDeactivatedState = true;
    try {
      clearSession();
      clearAllAppCachesOnLogout();
      await FirebaseAuth.instance.signOut();
      final navigator = appNavigatorKey.currentState;
      if (navigator != null) {
        navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
      }
      final context = appNavigatorKey.currentContext;
      if (context != null) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text(_deactivatedTitle),
              content: const Text(_deactivatedNotice),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    } finally {
      _isHandlingDeactivatedState = false;
    }
  }

  Future<void> handleDeactivatedAccount() async {
    await _handleAccountDeactivated();
  }
}
