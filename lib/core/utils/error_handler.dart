import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'exceptions.dart';

/// Centralized error handling utility
/// Converts technical errors to user-friendly messages
class ErrorHandler {
  /// Backend 503 “mail gönderilemedi” JSON: [code], isteğe bağlı [smtpDetail].
  /// Tanınmazsa null (genel 503 metni kullanılır).
  static String? messageForMailDelivery503Body(dynamic errorData) {
    if (errorData is! Map) return null;
    final m = Map<String, dynamic>.from(errorData);
    final code = m['code']?.toString().trim();
    if (code == null || code.isEmpty) return null;

    String? detailRaw = m['smtpDetail']?.toString().trim();
    if (detailRaw == null || detailRaw.isEmpty) {
      detailRaw = m['smtp_detail']?.toString().trim();
    }
    final detail = (detailRaw != null && detailRaw.isNotEmpty)
        ? (detailRaw.length > 320
            ? '${detailRaw.substring(0, 317)}...'
            : detailRaw)
        : null;
    final detailBlock =
        detail != null ? '\n\nTechnical detail: $detail' : '';

    switch (code) {
      case 'MISSING_MAIL_USERNAME':
        return 'Email was not sent: MAIL_USERNAME (or SPRING_MAIL_USERNAME) is not set '
            'on the server. In Railway, add the variable, fix typos, and redeploy.$detailBlock';
      case 'MISSING_MAIL_FROM':
        return 'Email was not sent: MAIL_FROM is missing or invalid. Set MAIL_FROM to a '
            'full email address (usually the same as MAIL_USERNAME).$detailBlock';
      case 'NO_MAIL_SENDER_BEAN':
        return 'Email was not sent: mail service failed to initialize. Check Spring Mail '
            'starter and mail auto-configuration on the server.$detailBlock';
      case 'EMPTY_USER_EMAIL':
        return 'Email was not sent: this account has no email address on the server / '
            'Firebase. Sign out and register again with a valid email.$detailBlock';
      case 'SMTP_REJECTED':
        return 'The mail server rejected the message (wrong password, app password, '
            '2FA, or blocked account). Regenerate Gmail app password, set MAIL_PASSWORD '
            'in Railway (no spaces needed), and set MAIL_FROM = MAIL_USERNAME.$detailBlock';
      default:
        final hint = m['message']?.toString().trim();
        if (hint != null && hint.isNotEmpty && hint != code) {
          return 'Email was not sent ($code). $hint$detailBlock';
        }
        return 'Email was not sent ($code).$detailBlock';
    }
  }

  /// Converts any exception to a user-friendly error message
  static String getUserFriendlyMessage(dynamic error) {
    if (error is IncompleteBackendRegistrationException) {
      return 'No app profile is linked to this account yet. Register with the '
          'same email, enter the 5-digit code from Favo, then sign in.';
    }

    final raw = error.toString().toUpperCase();
    if (raw.contains('EMAIL_NOT_VERIFIED')) {
      return 'Your email is not verified on the server yet. Enter the 5-digit code '
          'sent to your inbox, or tap Resend code.';
    }

    if (raw.contains('NO_ACTIVE_CODE')) {
      return 'No active verification code. Tap Resend to get a new code.';
    }
    if (raw.contains('WRONG_CODE')) {
      return 'That code is incorrect. Please try again.';
    }
    if (raw.contains('RESEND_COOLDOWN')) {
      return 'Please wait 60 seconds before requesting another code.';
    }
    if (raw.contains('ALREADY_VERIFIED')) {
      return 'This email is already verified.';
    }
    if (raw.contains('INVALID_CODE_FORMAT')) {
      return 'Enter the 5-digit code from your email.';
    }

    if (raw.contains('NO_SUCH_ACCOUNT') ||
        raw.contains('NO_SUCH') ||
        raw.contains('NOT_REGISTERED')) {
      return 'Your Firebase sign-in is active, but no app profile exists yet. '
          'Open the Profile tab and use “Complete profile” if shown, or sign out and '
          'finish registration with the same email.';
    }

    // Firebase Auth errors
    if (error is FirebaseAuthException) {
      return _handleFirebaseError(error);
    }

    // Dio/Network errors
    if (error is DioException) {
      return _handleDioError(error);
    }

    // Generic Exception
    if (error is Exception) {
      return _handleGenericException(error);
    }

    // String errors
    if (error is String) {
      return _handleStringError(error);
    }

    // Unknown error type
    return 'Something went wrong. Please try again.';
  }

  /// Handles Firebase authentication errors
  static String _handleFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Incorrect email or password.';
      case 'wrong-password':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'weak-password':
        return 'Password is too weak. Please choose a stronger password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Please check your internet connection.';
      case 'invalid-credential':
      case 'invalid-verification-code':
      case 'invalid-verification-id':
        return 'Incorrect email or password.';
      default:
        // Firebase'in teknik mesajını kontrol et
        final message = e.message?.toLowerCase() ?? '';
        if (message.contains('malformed') || 
            message.contains('expired') ||
            message.contains('credential') ||
            message.contains('invalid')) {
          return 'Incorrect email or password.';
        }
        return 'Incorrect email or password.';
    }
  }

  /// Handles Dio/Network errors
  static String _handleDioError(DioException e) {
    // Network connectivity issues
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timeout. Please check your internet connection and try again.';
    }

    if (e.type == DioExceptionType.connectionError) {
      return 'Unable to connect to the server. Please check your internet connection.';
    }

    // Server errors (4xx, 5xx)
    if (e.response != null) {
      final statusCode = e.response?.statusCode;
      final errorData = e.response?.data;

      // Extract error message from response
      String? serverMessage;
      if (errorData is Map) {
        serverMessage = errorData['message'] ?? 
                       errorData['error'] ?? 
                       errorData['detail'];
      } else if (errorData is String) {
        serverMessage = errorData;
      }

      // Handle specific status codes
      switch (statusCode) {
        case 400:
          return serverMessage ?? 'Invalid request. Please check your input.';
        case 401:
          if (serverMessage != null) {
            final ml = serverMessage.toLowerCase();
            if (ml.contains('no_such_account') ||
                ml.contains('no such account')) {
              return 'Unable to create account. Please try again or contact support.';
            }
            // Register / API: Firebase JWT — not the email+password login form
            if (ml.contains('token') ||
                ml.contains('jwt') ||
                ml.contains('firebase') ||
                ml.contains('bearer') ||
                ml.contains('email_not_verified') ||
                (ml.contains('expired') &&
                    (ml.contains('token') || ml.contains('session')))) {
              return 'Your email is verified, but the server needs a moment to accept '
                  'your session. Wait a few seconds and tap Continue again.';
            }
            if ((ml.contains('wrong') && ml.contains('password')) ||
                (ml.contains('invalid') && ml.contains('password'))) {
              return 'Incorrect email or password.';
            }
            if (ml.contains('credential') &&
                !ml.contains('token') &&
                !ml.contains('firebase')) {
              return 'Incorrect email or password.';
            }
          }
          return 'Your session is still updating. Please try Continue again in a few seconds.';
        case 403:
          return 'You do not have permission to perform this action.';
        case 404:
          return 'The requested resource was not found.';
        case 409:
          // Conflict - usually for duplicate username/email
          if (serverMessage != null && 
              (serverMessage.toLowerCase().contains('username') ||
               serverMessage.toLowerCase().contains('email') ||
               serverMessage.toLowerCase().contains('already exists'))) {
            return 'This username or email is already taken. Please choose another one.';
          }
          return serverMessage ?? 'This information is already in use. Please try something different.';
        case 422:
          return serverMessage ?? 'Invalid data provided. Please check all fields.';
        case 429:
          return 'Too many requests. Please try again later.';
        case 500:
        case 502:
          return 'Server error. Please try again later.';
        case 503:
          final mail503 = messageForMailDelivery503Body(errorData);
          if (mail503 != null) return mail503;
          return serverMessage ??
              'Service unavailable. Please try again later.';
        default:
          // Try to use server message if available, otherwise generic message
          if (serverMessage != null && serverMessage.isNotEmpty) {
            // Only show server message if it's user-friendly
            // Filter out technical error messages
            if (!serverMessage.contains('Exception') &&
                !serverMessage.contains('Error:') &&
                !serverMessage.contains('at ') &&
                serverMessage.length < 200) {
              return serverMessage;
            }
          }
          return 'An error occurred. Please try again.';
      }
    }

    // Unknown network error
    return 'Network error. Please check your connection and try again.';
  }

  /// Handles generic exceptions
  static String _handleGenericException(Exception e) {
    final errorString = e.toString().toLowerCase();

    final looksLikeFirebaseOrJwt =
        errorString.contains('token') ||
        errorString.contains('jwt') ||
        errorString.contains('firebase') ||
        errorString.contains('bearer') ||
        errorString.contains('id_token');
    if (looksLikeFirebaseOrJwt &&
        (errorString.contains('invalid') ||
            errorString.contains('expired') ||
            errorString.contains('malformed'))) {
      return 'Your email is verified, but the server could not accept your sign-in '
          'yet. Wait a few seconds and tap Continue again.';
    }

    // Catch login-form mistakes (not JWT / post-verify token lag)
    if (errorString.contains('malformed') && !looksLikeFirebaseOrJwt) {
      return 'Incorrect email or password.';
    }
    if ((errorString.contains('credential') ||
            errorString.contains('auth credential')) &&
        !looksLikeFirebaseOrJwt) {
      return 'Incorrect email or password.';
    }
    
    if (errorString.contains('wrong password') ||
        errorString.contains('incorrect password') ||
        errorString.contains('invalid password')) {
      return 'Incorrect email or password.';
    }
    
    if (errorString.contains('user not found') ||
        errorString.contains('no user found')) {
      return 'Incorrect email or password.';
    }

    // Filter out technical details
    if (errorString.contains('exception: ')) {
      final message = errorString.replaceFirst('exception: ', '');
      
      // Don't show technical error messages
      if (message.contains('at ') || 
          message.contains('error:') ||
          message.length > 200) {
        if (message.contains('token') ||
            message.contains('jwt') ||
            message.contains('firebase')) {
          return 'Your email is verified, but the server could not accept your session '
              'yet. Wait a few seconds and tap Continue again.';
        }
        if ((message.contains('wrong') && message.contains('password')) ||
            (message.contains('invalid') && message.contains('password'))) {
          return 'Incorrect email or password.';
        }
        return 'Something went wrong. Please try again.';
      }
      
      // Check for specific patterns
      if (message.contains('username') && message.contains('already')) {
        return 'This username is already taken.';
      }
      
      if (message.contains('email') && message.contains('already')) {
        return 'This email is already registered.';
      }
      
      if ((message.contains('wrong') && message.contains('password')) ||
          (message.contains('invalid') && message.contains('password'))) {
        return 'Incorrect email or password.';
      }
      if (message.contains('credential') &&
          !message.contains('token') &&
          !message.contains('firebase')) {
        return 'Incorrect email or password.';
      }
      
      // Return the message if it seems user-friendly
      return message;
    }

    if (errorString.contains('password') &&
        (errorString.contains('wrong') || errorString.contains('incorrect'))) {
      return 'Incorrect email or password.';
    }

    return 'Something went wrong. Please try again.';
  }

  /// Handles string errors
  static String _handleStringError(String error) {
    final errorLower = error.toLowerCase();
    
    // Catch technical messages and convert to simple messages
    if (errorLower.contains('malformed') || 
        errorLower.contains('expired') ||
        errorLower.contains('credential') ||
        errorLower.contains('invalid credential') ||
        errorLower.contains('auth credential')) {
      return 'Incorrect email or password.';
    }
    
    if (errorLower.contains('wrong password') ||
        errorLower.contains('incorrect password') ||
        errorLower.contains('invalid password')) {
      return 'Incorrect email or password.';
    }
    
    if (errorLower.contains('user not found') ||
        errorLower.contains('no user found')) {
      return 'Incorrect email or password.';
    }
    
    // Filter out technical error strings
    if (error.contains('Exception') ||
        error.contains('Error:') ||
        error.contains('at ') ||
        error.length > 200) {
      // Simple message for login/auth related technical messages
      if (errorLower.contains('login') || 
          errorLower.contains('auth') ||
          errorLower.contains('password') ||
          errorLower.contains('credential')) {
        return 'Incorrect email or password.';
      }
      return 'Something went wrong. Please try again.';
    }

    // Check for specific patterns
    if (errorLower.contains('network') ||
        errorLower.contains('connection')) {
      return 'Please check your internet connection.';
    }

    if (errorLower.contains('timeout')) {
      return 'Connection timed out. Please try again.';
    }
    
    // Simple message for login/auth related messages
    if (errorLower.contains('login') || 
        errorLower.contains('auth') ||
        errorLower.contains('password')) {
      return 'Incorrect email or password.';
    }

    return error;
  }

  /// Checks if error is a network-related error
  static bool isNetworkError(dynamic error) {
    if (error is DioException) {
      return error.type == DioExceptionType.connectionTimeout ||
             error.type == DioExceptionType.sendTimeout ||
             error.type == DioExceptionType.receiveTimeout ||
             error.type == DioExceptionType.connectionError;
    }
    
    final errorString = error.toString().toLowerCase();
    return errorString.contains('network') ||
           errorString.contains('connection') ||
           errorString.contains('timeout') ||
           errorString.contains('socket');
  }

  /// Checks if error is an authentication error
  static bool isAuthError(dynamic error) {
    if (error is FirebaseAuthException) {
      return true;
    }
    
    if (error is DioException && error.response?.statusCode == 401) {
      return true;
    }
    
    final errorString = error.toString().toLowerCase();
    return errorString.contains('unauthorized') ||
           errorString.contains('authentication') ||
           errorString.contains('login');
  }
}

