class ApiConfig {
  // Backend base URL - Backend'in çalıştığı bilgisayarın IP adresini buraya yazın
  // 
  // Backend bilgisayarında IP adresini öğrenmek için:
  // - macOS/Linux: ifconfig | grep "inet " veya ipconfig getifaddr en0
  // - Windows: ipconfig (IPv4 Address'e bakın)
  //
  // Örnek: 'http://192.168.1.100:8080'
  // 
  // NOT: Her iki bilgisayar aynı WiFi ağında olmalı!
  static const String baseUrl = 'https://backend-production-f771.up.railway.app'; // BU IP ADRESİNİ DEĞİŞTİRİN!
  
  // API endpoint paths (single leading slash; baseUrl must not end with /)
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

