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
  
  // API endpoint paths
  static const String loginPath = '/api/auth/login';
  static const String registerPath = '/api/auth/register';
  static const String mePath = '/api/auth/me';
}

