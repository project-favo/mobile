import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Centralized error handling utility
/// Converts technical errors to user-friendly messages
class ErrorHandler {
  /// Converts any exception to a user-friendly error message
  static String getUserFriendlyMessage(dynamic error) {
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
          // 401 is usually an authentication error
          if (serverMessage != null) {
            final messageLower = serverMessage.toLowerCase();
            if (messageLower.contains('no_such_account') ||
                messageLower.contains('no such account')) {
              return 'Unable to create account. Please try again or contact support.';
            }
            if (messageLower.contains('credential') ||
                messageLower.contains('password') ||
                messageLower.contains('email')) {
              return 'Incorrect email or password.';
            }
          }
          return 'Your session has expired. Please login again.';
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
        case 503:
          return 'Server error. Please try again later.';
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

    // Catch technical messages and convert to simple messages
    if (errorString.contains('malformed') || 
        errorString.contains('expired') ||
        errorString.contains('credential') ||
        errorString.contains('invalid credential') ||
        errorString.contains('auth credential')) {
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
        // General error message for technical messages
        if (message.contains('login') || 
            message.contains('auth') ||
            message.contains('password') ||
            message.contains('email')) {
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
      
      // Simple message for login/auth related messages
      if (message.contains('login') || 
          message.contains('auth') ||
          message.contains('password') ||
          message.contains('credential')) {
        return 'Incorrect email or password.';
      }
      
      // Return the message if it seems user-friendly
      return message;
    }

    // General error message
    if (errorString.contains('login') || 
        errorString.contains('auth') ||
        errorString.contains('password')) {
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

