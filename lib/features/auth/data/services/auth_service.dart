import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/cache/app_session_cache.dart';
import '../../../../core/cache/current_user_cache.dart';
import '../../../../core/utils/session_helper.dart';
import '../../../../core/utils/user_display_name_prefs.dart';
import '../../../../core/utils/exceptions.dart';
import '../models/user_response_dto.dart';
import '../models/user_update_request_dto.dart';
import '../models/register_request_dto.dart';
import '../repositories/auth_repository.dart';

bool _dioLooksLikeNoBackendUser(DioException e) {
  final code = e.response?.statusCode;
  final s = dioResponseDataAsSearchString(e.response?.data).toLowerCase();
  if (code == 404) return true;
  if (s.contains('no_such_account') || s.contains('no such account')) {
    return true;
  }
  if (s.contains('not registered') ||
      s.contains('register first') ||
      s.contains('unknown user')) {
    return true;
  }
  if (s.contains('user') &&
      (s.contains('not found') || s.contains('does not exist'))) {
    return true;
  }
  if (s.contains('complete') && s.contains('registration')) return true;
  if (code == 403 && (s.contains('register') || s.contains('registration'))) {
    return true;
  }
  return false;
}

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final AuthRepository _authRepository = AuthRepository();
  final SessionHelper _sessionHelper = SessionHelper();

  /// Kayıt formundan doğrulama ekranına taşınan veri (tüm AuthService örnekleri için ortak).
  static RegisterRequestDto? _registerFormDraft;

  static void saveRegisterFormDraft(RegisterRequestDto dto) {
    _registerFormDraft = dto;
  }

  static RegisterRequestDto? get peekRegisterFormDraft => _registerFormDraft;

  static void clearRegisterFormDraft() {
    _registerFormDraft = null;
  }

  Future<String> _getFreshIdToken(User user) async {
    final idToken = await user.getIdToken(true);
    if (idToken == null) {
      throw Exception('Failed to get Firebase ID token');
    }
    return idToken;
  }

  Future<UserResponseDto> _backendLoginWithIdToken(String idToken) async {
    return _authRepository.login(idToken);
  }

  Future<UserResponseDto> _finalizeUserResponse(UserResponseDto u) async {
    final merged = await UserDisplayNamePrefs.instance.mergeInto(u);
    if (merged.id.trim().isNotEmpty) {
      CurrentUserCache.instance.rememberFromDto(merged);
    }
    return merged;
  }

  /// Mevcut Firebase oturumu ile `POST /api/auth/login` (kayıt / e-posta doğrulama sonrası).
  Future<UserResponseDto> establishBackendSession() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final token = await _getFreshIdToken(user);
    return _finalizeUserResponse(await _backendLoginWithIdToken(token));
  }

  /// Firebase + backend login. E-posta doğrulanmamış olsa da oturum açılır (profilde uyarı).
  Future<UserResponseDto> loginWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      var user = userCredential.user;
      if (user == null) {
        throw Exception('Sign in failed');
      }
      await user.reload();
      user = _firebaseAuth.currentUser;
      if (user == null) {
        throw Exception('Sign in failed');
      }

      final idToken = await _getFreshIdToken(user);
      try {
        final login = await _backendLoginWithIdToken(idToken);
        _sessionHelper.markBackendLoginSucceeded();
        return _finalizeUserResponse(login);
      } on DioException catch (e) {
        if (looksLikeDeactivatedAccountMessage(
          dioResponseDataAsSearchString(e.response?.data),
        )) {
          await _firebaseAuth.signOut();
          _sessionHelper.clearSession();
          throw const DeactivatedAccountException();
        }
        if (dioExceptionBodyContains(e, 'EMAIL_NOT_VERIFIED')) {
          throw EmailNotVerifiedException(user.email ?? email.trim());
        }
        if (_dioLooksLikeNoBackendUser(e)) {
          throw const IncompleteBackendRegistrationException();
        }
        rethrow;
      }
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseError(e);
    } on DioException {
      rethrow;
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Profil / oturum öncesi token claim’lerini güncellemek için (backend gecikmesi).
  Future<void> syncFirebaseUserAndRefreshIdToken() async {
    final u = _firebaseAuth.currentUser;
    if (u == null) return;
    try {
      await u.reload();
    } catch (_) {}
    await _firebaseAuth.currentUser?.getIdToken(true);
  }

  /// Kayıt adımı 1: Firebase hesabı oluşturur; **e-posta göndermez** (Firebase link maili yok).
  /// E-postadaki 5 haneli kod yalnızca backend (`register` / `resend-verification`) üzerinden gelir.
  Future<void> createFirebaseUserForRegistration({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final u = userCredential.user;
      if (u == null) {
        throw Exception('Failed to create account');
      }
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseError(e);
    }
  }

  /// Kayıt adımı 2: `POST /api/auth/register`. Backend e-posta kodu için [requireFirebaseEmailVerified] false olmalı.
  Future<void> registerOnBackend(
    RegisterRequestDto request, {
    bool requireFirebaseEmailVerified = false,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('Session expired. Please sign in again.');
    }
    if (requireFirebaseEmailVerified && !user.emailVerified) {
      throw Exception(
        'Open the verification link in your email, then tap Continue.',
      );
    }
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      throw Exception('No email on this account. Sign out and register again.');
    }
    final t1 = await _getFreshIdToken(user);
    final payload = RegisterRequestDto(
      userName: request.userName,
      name: request.name,
      surname: request.surname,
      birthdate: request.birthdate,
      email: email,
      profilePhotoBase64: request.profilePhotoBase64,
      profilePhotoMimeType: request.profilePhotoMimeType,
    );
    await _authRepository.register(t1, payload);
  }

  /// İsteğe bağlı: Firebase’in **link** içeren doğrulama e-postasını gönderir (kayıt akışında kullanılmaz).
  Future<void> resendFirebaseEmailVerification() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('No active session. Please register again.');
    }
    await user.sendEmailVerification();
  }

  /// Başka kullanıcı (mesaj / liste avatarı için). Uç yoksa null.
  Future<UserResponseDto?> getUserById(String userId) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    try {
      final idToken = await _getFreshIdToken(user);
      return _authRepository.getUserById(idToken, userId);
    } catch (_) {
      return null;
    }
  }

  /// Me endpoint - Authenticated user bilgilerini getirir
  ///
  /// `EMAIL_NOT_VERIFIED` dönerse verify tamamlanana kadar [login] çağrılmaz; minimal profil döner.
  Future<UserResponseDto> getMe() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      await user.reload();
    } catch (_) {}

    Future<String?> freshToken() async => user.getIdToken(true);

    var idToken = await freshToken();
    if (idToken == null) {
      throw Exception('Failed to get Firebase ID token');
    }

    try {
      return await _finalizeUserResponse(await _authRepository.getMe(idToken));
    } catch (e) {
      final buf = StringBuffer(e.toString());
      if (e is DioException) {
        buf.write(dioResponseDataAsSearchString(e.response?.data));
      }
      final msg = buf.toString().toUpperCase();
      if (msg.contains('EMAIL_NOT_VERIFIED')) {
        return await _finalizeUserResponse(_fallbackUserWhenMeBlocked(user));
      }
      if (msg.contains('NO_SUCH')) {
        try {
          await user.reload();
          idToken = await freshToken();
          if (idToken == null) {
            return await _finalizeUserResponse(_fallbackUserWhenMeBlocked(user));
          }
          return await _finalizeUserResponse(await _authRepository.login(idToken));
        } catch (e2) {
          final buf2 = StringBuffer(e2.toString());
          if (e2 is DioException) {
            buf2.write(dioResponseDataAsSearchString(e2.response?.data));
          }
          final m2 = buf2.toString().toUpperCase();
          if (m2.contains('NO_SUCH')) {
            return await _finalizeUserResponse(_fallbackUserWhenMeBlocked(user));
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  UserResponseDto _fallbackUserWhenMeBlocked(User firebaseUser) {
    final email = firebaseUser.email ?? '';
    final local =
        email.contains('@') ? email.split('@').first.trim() : email.trim();
    final nameFromEmail = local.isNotEmpty ? local : 'User';
    final dn = firebaseUser.displayName?.trim();
    return UserResponseDto(
      id: '',
      email: email,
      userName: (dn != null && dn.isNotEmpty) ? dn : nameFromEmail,
      emailVerified: firebaseUser.emailVerified,
    );
  }

  /// Me update endpoint - User bilgilerini günceller
  Future<UserResponseDto> updateMe(UserUpdateRequestDto request) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    final idToken = await _getFreshIdToken(user);
    return _finalizeUserResponse(await _authRepository.updateMe(idToken, request));
  }

  /// E-posta doğrulama kodunu backend'e gönderir.
  Future<UserResponseDto> verifyEmail(String code) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    final token = await _getFreshIdToken(user);
    return _finalizeUserResponse(
      await _authRepository.verifyEmail(token, code),
    );
  }

  /// Şifre sıfırlama: backend `POST /api/auth/forgot-password` (public, Bearer yok).
  /// Firebase reset linki e-postaya gider; hesap yoksa da aynı başarı yanıtı.
  Future<String> requestPasswordReset(String email) async {
    return _authRepository.forgotPassword(email);
  }

  /// `POST /api/auth/resend-verification` — gövdede [email] (Spring’de yaygın).
  Future<void> resendVerification() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    final token = await _getFreshIdToken(user);
    return _authRepository.resendVerification(
      token,
      email: user.email?.trim(),
    );
  }

  /// Şifre değiştirir (Firebase Auth)
  /// Önce mevcut şifre ile re-authentication yapılır, sonra yeni şifre ayarlanır
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      if (user.email == null) {
        throw Exception('User email not found');
      }

      // 1. Mevcut şifre ile re-authentication yap
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);

      // 2. Yeni şifreyi ayarla
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseError(e);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Hesabı siler: önce backend'de /api/auth/me DELETE, sonra Firebase signOut
  Future<void> deleteAccount() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final idToken = await _getFreshIdToken(user);

      // Backend'de hesabı sil
      await _authRepository.deleteMe(idToken);

      _sessionHelper.clearSession();
      clearAllAppCachesOnLogout();
      // Firebase oturumunu kapat
      await _firebaseAuth.signOut();
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseError(e);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Çıkış yapar
  Future<void> signOut() async {
    _sessionHelper.clearSession();
    clearAllAppCachesOnLogout();
    await _firebaseAuth.signOut();
  }

  /// Mevcut kullanıcıyı kontrol eder
  User? get currentUser => _firebaseAuth.currentUser;

  /// Firebase error handling
  Exception _handleFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return Exception('No user found with this email');
      case 'wrong-password':
        return Exception('Wrong password provided');
      case 'email-already-in-use':
        return Exception('Email is already registered');
      case 'weak-password':
        return Exception('Password is too weak');
      case 'invalid-email':
        return Exception('Invalid email address');
      case 'user-disabled':
        return Exception('This user account has been disabled');
      case 'too-many-requests':
        return Exception('Too many requests. Please try again later');
      default:
        return Exception(e.message ?? 'Authentication failed');
    }
  }
}

