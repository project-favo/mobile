import 'package:dio/dio.dart';

/// Spring / özel API: uygulama kodu veya kullanıcıya gösterilecek birincil metin.
/// Öncelik kullanıcı mesajı (`message`, `detail`), sonra makine kodu (`errorCode`).
/// `error` alanı yalnızca jenerik HTTP sebebi değilse kullanılır (örn. "Bad Request" atlanır).
String? backendResponsePrimaryErrorText(dynamic data) {
  if (data == null) return null;
  if (data is String) {
    final t = data.trim();
    return t.isEmpty ? null : t;
  }
  if (data is! Map) return null;
  final m = Map<String, dynamic>.from(data);

  String? pick(String key) {
    final v = m[key];
    if (v == null) return null;
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }

  // Sunucunun İngilizce kullanıcı mesajı (message) makine kodundan (errorCode) önce gelmeli.
  for (final key in ['message', 'detail', 'title']) {
    final v = pick(key);
    if (v != null) return v;
  }
  for (final key in ['code', 'errorCode']) {
    final v = pick(key);
    if (v != null) return v;
  }
  final err = pick('error');
  if (err == null) return null;
  const genericHttpReasons = {
    'Bad Request',
    'Unauthorized',
    'Forbidden',
    'Not Found',
    'Method Not Allowed',
    'Conflict',
    'Unsupported Media Type',
    'Payload Too Large',
    'Unprocessable Entity',
    'Too Many Requests',
    'Internal Server Error',
    'Bad Gateway',
    'Service Unavailable',
    'Gateway Timeout',
  };
  if (genericHttpReasons.contains(err)) return null;
  return err;
}

/// Response gövdesini (Map, String, listeler) tek metinde birleştirir;
/// Spring 500/HTML veya iç içe JSON için EMAIL_NOT_VERIFIED aramasında kullanılır.
String dioResponseDataAsSearchString(dynamic data) {
  if (data == null) return '';
  if (data is String) return data;
  if (data is Map) {
    final parts = <String>[];
    for (final e in data.entries) {
      parts.add('${e.key}:${dioResponseDataAsSearchString(e.value)}');
    }
    return parts.join(' ');
  }
  if (data is List) {
    return data.map(dioResponseDataAsSearchString).join(' ');
  }
  return data.toString();
}

bool dioExceptionBodyContains(DioException e, String needle) {
  return dioResponseDataAsSearchString(e.response?.data).contains(needle);
}

/// [POST /api/auth/login] sonrası backend bazen açık "suspend" metni vermez (403/5xx).
/// Firebase girişi başarılı olduğu için burada genelde hesap durumu / politika reddi vardır.
bool looksLikeSuspendedBackendLoginResponse(DioException e) {
  if (e.requestOptions.method.toUpperCase() != 'POST') return false;
  final path = e.requestOptions.path.toLowerCase();
  if (!(path.contains('auth/login') || path.endsWith('/login'))) return false;
  final code = e.response?.statusCode ?? 0;
  final flat = dioResponseDataAsSearchString(e.response?.data);
  final sl = flat.toLowerCase();
  if (sl.contains('no_such_account') || sl.contains('no such account')) {
    return false;
  }
  if (flat.contains('EMAIL_NOT_VERIFIED')) return false;
  if (sl.contains('wrong') && sl.contains('password')) return false;
  if (sl.contains('invalid') && sl.contains('credential')) return false;
  if (code == 403 || code == 423) return true;
  if (code == 500 || code == 502) {
    if (looksLikeSuspendedAccountMessage(sl)) return true;
    if (looksLikeDeactivatedAccountMessage(sl)) return true;
    return true;
  }
  return false;
}

/// Login sırasında backend EMAIL_NOT_VERIFIED döndürdüğünde fırlatılır.
class EmailNotVerifiedException implements Exception {
  final String email;
  const EmailNotVerifiedException(this.email);

  @override
  String toString() => 'EmailNotVerifiedException';
}

/// Firebase Auth’ta e-posta henüz doğrulanmamış (gelen kutusundaki bağlantı).
class FirebaseEmailNotVerifiedException implements Exception {
  const FirebaseEmailNotVerifiedException();

  @override
  String toString() => 'FirebaseEmailNotVerifiedException';
}

/// 401 Unauthorized — kullanıcı giriş yapmamış ya da token süresi dolmuş.
class UnauthorizedException implements Exception {
  const UnauthorizedException();

  @override
  String toString() => 'UnauthorizedException';
}

/// Firebase oturumu var ama backend’de kayıt yok (kayıt akışı yarım kaldı).
class IncompleteBackendRegistrationException implements Exception {
  const IncompleteBackendRegistrationException();

  @override
  String toString() => 'IncompleteBackendRegistrationException';
}

/// Aynı review için şikayet zaten gönderilmiş.
class ReviewAlreadyReportedException implements Exception {
  const ReviewAlreadyReportedException();

  @override
  String toString() => 'ReviewAlreadyReportedException';
}

class DeactivatedAccountException implements Exception {
  const DeactivatedAccountException();

  @override
  String toString() => 'DeactivatedAccountException';
}

/// GET /api/products/{id} ürünü döndürmüyor (404 / 401).
class ProductNotAvailableException implements Exception {
  final String productId;
  final int? statusCode;

  const ProductNotAvailableException(this.productId, {this.statusCode});

  @override
  String toString() => 'ProductNotAvailableException';
}

/// GET /api/reviews/{id} yorum döndürmüyor (404 / 401).
class ReviewNotAvailableException implements Exception {
  final String reviewId;
  final int? statusCode;

  const ReviewNotAvailableException(this.reviewId, {this.statusCode});

  @override
  String toString() => 'ReviewNotAvailableException';
}

/// Görüntülenen başka kullanıcı kaldırıldı / erişilebilir değil (tüm uçlar 404 veya 401).
class TargetUserNotAvailableException implements Exception {
  final String userId;
  const TargetUserNotAvailableException(this.userId);

  @override
  String toString() => 'TargetUserNotAvailableException';
}

/// Login / auth hata gövdesinde askı — [looksLikeDeactivatedAccountMessage] ile çakışmasın;
/// önce askı kontrol edilir ([AuthService]).
bool looksLikeSuspendedAccountMessage(String value) {
  final s = value.toLowerCase();
  if (s.contains('suspend')) return true;
  if (s.contains('account_suspended') || s.contains('user_suspended')) return true;
  if (s.contains('account suspended') || s.contains('user suspended')) return true;
  if (s.contains('status:suspended') || s.contains('accountstatus:suspended')) {
    return true;
  }
  if (s.contains('banned') || s.contains('blocked')) return true;
  if (s.contains('restriction') && s.contains('account')) return true;
  if (s.contains('not eligible') || s.contains('ineligible')) return true;
  if (s.contains('no longer') && s.contains('available')) return true;
  if (s.contains('access denied') && s.contains('account')) return true;
  return false;
}

bool looksLikeDeactivatedAccountMessage(String value) {
  final s = value.toLowerCase();
  if (s.contains('deactivated')) return true;
  if (s.contains('inactive')) return true;
  if (s.contains('account_disabled')) return true;
  if (s.contains('user_disabled')) return true;
  if (s.contains('closed')) return true;
  if (s.contains('disabled') &&
      (s.contains('user') || s.contains('account'))) {
    return true;
  }
  if (s.contains('locked') &&
      (s.contains('user') || s.contains('account'))) {
    return true;
  }
  return false;
}

class SuspendedAccountException implements Exception {
  const SuspendedAccountException();

  @override
  String toString() => 'SuspendedAccountException';
}
