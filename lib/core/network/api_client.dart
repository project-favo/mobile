import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  Dio? _dio;
  CookieJar? _cookieJar;
  bool _initialized = false;

  void initialize({String? baseUrl, String? authToken}) {
    // CookieManager is not supported on web (dio_cookie_manager throws in web env)
    if (!kIsWeb) {
      _cookieJar = CookieJar();
    }

    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
      ),
    );

    // Add cookie manager only on non-web platforms (mobile, desktop)
    if (!kIsWeb && _cookieJar != null) {
      _dio!.interceptors.add(CookieManager(_cookieJar!));
    }

    // Log interceptor only in debug mode (not in production)
    if (kDebugMode) {
      _dio!.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          error: true,
        ),
      );
    }
    
    _initialized = true;
  }

  void setAuthToken(String token) {
    if (!_initialized || _dio == null) {
      throw Exception('ApiClient must be initialized before setting auth token');
    }
    _dio!.options.headers['Authorization'] = 'Bearer $token';
  }

  void clearAuthToken() {
    if (!_initialized || _dio == null) {
      return;
    }
    _dio!.options.headers.remove('Authorization');
  }

  Dio get dio {
    if (!_initialized || _dio == null) {
      throw Exception('ApiClient must be initialized before use. Call initialize() first.');
    }
    return _dio!;
  }
}

