import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_response_dto.dart';
import '../models/user_update_request_dto.dart';
import '../models/register_request_dto.dart';
import '../repositories/auth_repository.dart';
import '../../../../core/utils/exceptions.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final AuthRepository _authRepository = AuthRepository();

  /// Firebase'de email/password ile giriş yapar ve backend'e login isteği gönderir
  Future<UserResponseDto> loginWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      // 1. Firebase Authentication ile giriş yap
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // 2. Firebase idToken al
      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // 3. Backend'e login isteği gönder (idToken Authorization header'ında)
      try {
        final userDto = await _authRepository.login(idToken);
        // Backend emailVerified: false döndürürse doğrulama sayfasına yönlendir
        if (!userDto.isEmailVerified) {
          throw EmailNotVerifiedException(idToken);
        }
        return userDto;
      } on EmailNotVerifiedException {
        rethrow;
      } on DioException catch (e) {
        // Backend 500 + EMAIL_NOT_VERIFIED (gövde Map/String/HTML olabilir)
        if (dioExceptionBodyContains(e, 'EMAIL_NOT_VERIFIED')) {
          throw EmailNotVerifiedException(idToken);
        }
        rethrow;
      }
    } on EmailNotVerifiedException {
      rethrow;
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

  /// Firebase'de email/password ile kayıt olur ve backend'e register isteği gönderir
  Future<UserResponseDto> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String userName,
    required String name,
    required String surname,
    required String birthdate,
    String? profilePhotoBase64,
    String? profilePhotoMimeType,
  }) async {
    try {
      // 1. Firebase Authentication ile kayıt ol
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // 2. Firebase idToken al (force refresh ile yeni token al)
      // Firebase'de kullanıcı oluşturulduktan sonra backend'in token'ı doğrulayabilmesi için delay ekle
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Token'ı birkaç kez refresh etmeyi dene (bazı durumlarda ilk token henüz tam hazır olmayabilir)
      String? idToken;
      for (int i = 0; i < 3; i++) {
        idToken = await userCredential.user?.getIdToken(true);
        if (idToken != null) {
          // Token başarıyla alındı, kısa bir delay daha ekle
          await Future.delayed(const Duration(milliseconds: 300));
          break;
        }
        // Token alınamadıysa kısa bir delay ile tekrar dene
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      if (idToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // 3. RegisterRequestDto oluştur
      final registerRequest = RegisterRequestDto(
        userName: userName,
        name: name,
        surname: surname,
        birthdate: birthdate,
        profilePhotoBase64: profilePhotoBase64,
        profilePhotoMimeType: profilePhotoMimeType,
      );

      // 4. Backend'e register isteği gönder (idToken Authorization header'ında, RegisterRequestDto request body'de)
      final userDto = await _authRepository.register(idToken, registerRequest);
      return userDto;
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseError(e);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Me endpoint - Authenticated user bilgilerini getirir
  Future<UserResponseDto> getMe() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final idToken = await user.getIdToken();
      if (idToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }
      return await _authRepository.getMe(idToken);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Me update endpoint - User bilgilerini günceller
  Future<UserResponseDto> updateMe(UserUpdateRequestDto request) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final idToken = await user.getIdToken();
      if (idToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }
      return await _authRepository.updateMe(idToken, request);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// E-posta doğrulama kodunu backend'e gönderir.
  Future<UserResponseDto> verifyEmail(String code) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    final token = await user.getIdToken();
    if (token == null) throw Exception('Failed to get Firebase ID token');
    return _authRepository.verifyEmail(token, code);
  }

  /// Doğrulama e-postasını yeniden gönderir.
  Future<void> resendVerification() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    final token = await user.getIdToken();
    if (token == null) throw Exception('Failed to get Firebase ID token');
    return _authRepository.resendVerification(token);
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

      final idToken = await user.getIdToken();
      if (idToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // Backend'de hesabı sil
      await _authRepository.deleteMe(idToken);

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

