class ApiConfig {
  static const String baseUrl = 'https://backend-production-f771.up.railway.app';

  static const String loginPath = '/api/auth/login';
  static const String registerPath = '/api/auth/register';
  static const String verifyEmailPath = '/api/auth/verify-email';
  static const String resendVerificationPath = '/api/auth/resend-verification';
  static const String forgotPasswordPath = '/api/auth/forgot-password';
  static const String checkUsernamePath = '/api/auth/check-username';
  static const String mePath = '/api/auth/me';
  static const String preRegisterSendCodePath = '/api/auth/pre-register/send-code';
  static const String preRegisterVerifyCodePath = '/api/auth/pre-register/verify-code';

  /// Native STOMP endpoint (bildirimler: `/user/queue/notifications`). Mesajlar `/ws` kullanır.
  static const String wsNativePath = '/ws-native';
}

