import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../features/auth/data/repositories/notification_repository.dart';
import 'app_badge_sync.dart';
import 'push_token_logger.dart';

/// Açılış + oturum: FCM token backend’e kayıt, dinleyiciler, data.badge uygulama.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  bool _installed = false;
  bool _fcmHooksBound = false;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<User?>? _authSub;

  /// Backend `POST /api/auth/login` tamamlandıktan hemen sonra: JWT hazır, FCM’yi aynı endpoint’e ilet.
  Future<void> syncTokenAfterBackendSessionReady() async {
    if (kIsWeb) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    await _getTokenAndRegisterIfPossible(source: 'JWT_ready');
  }

  /// [main] sonrası bir kez; giriş/çıkış [authStateChanges] ile yönetilir.
  Future<void> install() async {
    if (kIsWeb) return;
    if (_installed) return;
    _installed = true;

    _authSub = FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        if (user == null) {
          unawaited(clearAppLauncherBadge());
        } else {
          unawaited(_onSignedIn());
        }
      },
    );
    // İlk değer stream üzerinden gelir; burada tekrar _onSignedIn çağırma.
  }

  Future<void> _onSignedIn() async {
    if (kIsWeb) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    // 1) getToken, bildirim izninden bağımsız; null değilse JWT (ensureSession) ile POST
    try {
      await _getTokenAndRegisterIfPossible(source: 'app_open');
    } catch (e, st) {
      // Repository log + rethrow; burada tam stack (push-token / ağ hataları uygulamayı çökertmez)
      pushTokenLog('app_open push-token path failed (see above logs)', error: '$e | $st');
    }
    // 2) İzin, foreground sunumu, onMessage, onTokenRefresh (yenilemede aynı POST)
    try {
      await _ensureAuthorizationAndListeners();
    } catch (e) {
      pushTokenLog('ensureAuthorizationAndListeners failed', error: e);
    }
  }

  /// İzin/notification channel akışı olmadan önce FCM token alınır.
  Future<void> _getTokenAndRegisterIfPossible({required String source}) async {
    if (kIsWeb) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    String? token;
    try {
      pushTokenLog('getToken() start', error: 'source=$source');
      token = await FirebaseMessaging.instance.getToken();
    } catch (e, st) {
      pushTokenLog('getToken() failed', error: '$e | $st');
      rethrow;
    }
    if (token == null || token.isEmpty) {
      pushTokenLog('getToken() null/empty, skip push-token', error: 'source=$source');
      return;
    }
    pushTokenLog('getToken() ok, posting push-token', fcmTokenPrefix: _tokenTailForLog(token));
    await _registerIfAuthenticated(token, source: source);
  }

  String _tokenTailForLog(String t) {
    if (t.length <= 12) return t;
    return '${t.substring(0, 8)}…${t.substring(t.length - 6)}';
  }

  Future<void> _ensureAuthorizationAndListeners() async {
    final fm = FirebaseMessaging.instance;
    // getToken yukarıda açılışta zaten; burada sadece izin + sunum
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final perm = await fm.requestPermission(alert: true, badge: true, sound: true);
      pushTokenLog('iOS requestPermission', error: 'auth=${perm.authorizationStatus.name}');
    } else {
      final s = await fm.getNotificationSettings();
      if (s.authorizationStatus == AuthorizationStatus.notDetermined) {
        final perm = await fm.requestPermission();
        pushTokenLog('Android requestPermission', error: 'auth=${perm.authorizationStatus.name}');
      }
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    if (_fcmHooksBound) return;
    _fcmHooksBound = true;

    _tokenRefreshSub = fm.onTokenRefresh.listen((t) {
      if (FirebaseAuth.instance.currentUser == null) return;
      pushTokenLog('onTokenRefresh, posting push-token', fcmTokenPrefix: t.length > 20 ? '…${t.substring(t.length - 12)}' : t);
      unawaited(
        _registerIfAuthenticated(t, source: 'onTokenRefresh').catchError((
          Object e,
          StackTrace s,
        ) {
          pushTokenLog('async register failed (onTokenRefresh)', error: '$e | $s');
        }),
      );
    });

    FirebaseMessaging.onMessage.listen(
      (m) {
        if (FirebaseAuth.instance.currentUser == null) return;
        unawaited(applyPushBadgeFromMessageData(m.data));
      },
    );
    FirebaseMessaging.onMessageOpenedApp.listen(
      (m) {
        if (FirebaseAuth.instance.currentUser == null) return;
        unawaited(applyPushBadgeFromMessageData(m.data));
      },
    );

    final initial = await fm.getInitialMessage();
    if (initial != null && FirebaseAuth.instance.currentUser != null) {
      unawaited(applyPushBadgeFromMessageData(initial.data));
    }
  }

  static Future<void> _registerIfAuthenticated(
    String fcmToken, {
    required String source,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      pushTokenLog('register skip (no user)', error: 'source=$source');
      return;
    }
    final platform = _iosOrAndroidPlatform();
    if (platform == null) {
      pushTokenLog('register skip (not ios/android)', error: 'source=$source');
      return;
    }
    await NotificationRepository().registerPushToken(
      fcmToken: fcmToken,
      platform: platform,
      logSource: source,
    );
  }

  /// Sadece mobil; backend `ios` / `android` kabul ediyor.
  static String? _iosOrAndroidPlatform() {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => null,
    };
  }

  void dispose() {
    _authSub?.cancel();
    _authSub = null;
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }
}
