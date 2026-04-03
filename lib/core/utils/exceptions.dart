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
/// [firebaseIdToken] doğrulama sayfasında kullanmak için taşınır.
class EmailNotVerifiedException implements Exception {
  final String firebaseIdToken;
  const EmailNotVerifiedException(this.firebaseIdToken);

  @override
  String toString() => 'EmailNotVerifiedException';
}

/// 401 Unauthorized — kullanıcı giriş yapmamış ya da token süresi dolmuş.
class UnauthorizedException implements Exception {
  const UnauthorizedException();

  @override
  String toString() => 'UnauthorizedException';
}
