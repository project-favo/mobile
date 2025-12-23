import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_response_dto.dart';
import '../models/user_update_request_dto.dart';
import '../repositories/auth_repository.dart';

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
      final userDto = await _authRepository.login(idToken);
      return userDto;
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseError(e);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Firebase'de email/password ile kayıt olur ve backend'e register isteği gönderir
  Future<UserResponseDto> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String userName,
  }) async {
    try {
      // 1. Firebase Authentication ile kayıt ol
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // 2. Firebase idToken al
      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null) {
        throw Exception('Failed to get Firebase ID token');
      }

      // 3. Backend'e register isteği gönder (idToken Authorization header'ında, userName query param'da)
      final userDto = await _authRepository.register(idToken, userName);
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

