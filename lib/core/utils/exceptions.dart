import 'package:dio/dio.dart';

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

/// GET /api/products/{id} ürünü döndürmüyor (silindi, askıda, 403/404/410).
class ProductNotAvailableException implements Exception {
  final String productId;
  final int? statusCode;

  const ProductNotAvailableException(this.productId, {this.statusCode});

  @override
  String toString() => 'ProductNotAvailableException';
}

bool looksLikeDeactivatedAccountMessage(String value) {
  final s = value.toLowerCase();
  if (s.contains('deactivated')) return true;
  if (s.contains('inactive')) return true;
  if (s.contains('suspend')) return true;
  if (s.contains('account_disabled')) return true;
  if (s.contains('user_disabled')) return true;
  return false;
}
