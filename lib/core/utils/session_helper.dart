import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../routes/app_routes.dart';
import '../network/api_client.dart';
import '../config/api_config.dart';
import 'exceptions.dart';
import 'user_account_flags.dart';
import 'review_report_storage.dart';
import '../cache/app_session_cache.dart';
import '../config/app_background_timers.dart';
import 'app_logger.dart';

/// Session management helper
/// Handles backend session establishment and token management
class SessionHelper {
  static final SessionHelper _instance = SessionHelper._internal();
  factory SessionHelper() => _instance;
  SessionHelper._internal();

  bool _sessionEstablished = false;
  DateTime? _lastLoginTime;
  static const Duration _sessionValidDuration = Duration(minutes: 30);
  static const String _deactivatedTitle = 'Account Deactivated';
  static const String _deactivatedNotice =
      'Your account has been deactivated by admin.\n\n'
      'For help, please contact: ctis411.09@gmail.com';
  static const String _suspendedTitle = 'Account Suspended';
  static const String _suspendedNotice =
      'Your account has been suspended.\n\n'
      'For help, please contact: ctis411.09@gmail.com';
  Timer? _accountStatusTimer;
  bool _isHandlingDeactivatedState = false;

  /// Gerekirse backend oturumu kurar.
  ///
  /// Firebase: [getIdToken] varsayılan olarak geçerli ID token döner, süresi dolmuşsa
  /// SDK yeniler. [getIdToken(true)] yalnızca [forceIdTokenRefresh] veya 401/özel
  /// kurtarma yollarında kullanılır; her çağrıda zorunlu tazelik pil ve ağ israfıdır.
  Future<String?> ensureSession({bool forceIdTokenRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    final freshToken = await user.getIdToken(forceIdTokenRefresh);
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
      if (_looksLikeSuspendedAccountFromDio(e)) {
        await handleSuspendedAccount();
        throw const SuspendedAccountException();
      }
      if (_looksLikeDeactivatedAccountFromDio(e)) {
        await handleDeactivatedAccount();
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
        } catch (e, st) {
          AppLogger.warnSilencedError(
            'ensureSession 401 retry',
            e,
            st,
          );
        }
      }
      _sessionEstablished = true;
      _lastLoginTime = DateTime.now();
      return freshToken;
    } catch (e, st) {
      AppLogger.warnSilencedError('ensureSession outer catch', e, st);
      ApiClient().setAuthToken(freshToken);
      return freshToken;
    }
  }

  /// API istemcisi için ID token. Varsayılan [forceRefresh] yok; [ensureSession] ile aynı ilke.
  Future<String?> getTokenAndSetHeader({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }

    final token = await user.getIdToken(forceRefresh);
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
    return ensureSession(forceIdTokenRefresh: true);
  }

  void startAccountStatusMonitoring() {
    _accountStatusTimer?.cancel();
    _accountStatusTimer = Timer.periodic(
      AppBackgroundTimers.accountStatusCheck,
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
      final token = await user.getIdToken(false);
      if (token == null) return;
      ApiClient().setAuthToken(token);
      final response = await ApiClient().dio.get(ApiConfig.mePath);
      if (_looksLikeSuspendedAccountFromMe(response.data)) {
        await handleSuspendedAccount();
        return;
      }
      if (_looksLikeDeactivatedAccountFromMe(response.data)) {
        await handleDeactivatedAccount();
      }
    } on DioException catch (e) {
      if (_looksLikeSuspendedAccountFromDio(e)) {
        await handleSuspendedAccount();
        return;
      }
      if (_looksLikeDeactivatedAccountFromDio(e)) {
        await handleDeactivatedAccount();
      }
    } catch (e, st) {
      AppLogger.warnSilencedError('SessionHelper._checkAccountStatus', e, st);
    }
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
    if (status == 'deactivated' || status == 'inactive') {
      return true;
    }
    if (active is bool && !active) return true;
    if (enabled is bool && !enabled) return true;
    if (isActive is bool && !isActive) return true;
    return false;
  }

  bool _looksLikeSuspendedAccountFromMe(dynamic data) {
    if (data is! Map) return false;
    final m = Map<String, dynamic>.from(data);
    if (isUserSuspendedSignalInMap(m)) return true;
    final status = m['status']?.toString().toLowerCase() ?? '';
    return status == 'suspended';
  }

  bool _looksLikeSuspendedAccountFromDio(DioException e) {
    final body = dioResponseDataAsSearchString(e.response?.data);
    if (looksLikeSuspendedAccountMessage(body)) return true;
    final code = e.response?.statusCode ?? 0;
    return (code == 403 || code == 423) &&
        looksLikeSuspendedAccountMessage(e.message ?? '');
  }

  bool _looksLikeDeactivatedAccountFromDio(DioException e) {
    final code = e.response?.statusCode ?? 0;
    final body = dioResponseDataAsSearchString(e.response?.data);
    if (looksLikeDeactivatedAccountMessage(body)) return true;
    return (code == 403 || code == 423) &&
        looksLikeDeactivatedAccountMessage(e.message ?? '');
  }

  Future<void> _handleAccountLocked({
    required String title,
    required String notice,
  }) async {
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
              title: Text(title),
              content: Text(notice),
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
    await _handleAccountLocked(
      title: _deactivatedTitle,
      notice: _deactivatedNotice,
    );
  }

  Future<void> handleSuspendedAccount() async {
    await _handleAccountLocked(
      title: _suspendedTitle,
      notice: _suspendedNotice,
    );
  }
}
