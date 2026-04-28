import 'profile_field_limits.dart';

/// Kullanıcı adı: harf (Türkçe `İ/ğ/ü` vb. Unicode dahil), rakam, alt çizgi.
/// Sunucu `[a-zA-Z0-9_]` ile sınırlı olsa dahi, istemci en azından aynı kuralla doğrulamalı.
class UsernameInputRules {
  UsernameInputRules._();

  /// Unicode "Letter" + ASCII rakam + `_` (boşluk, emoji, nokta yok)
  static final RegExp _allowed = RegExp(
    r'^[0-9_\p{L}]+$',
    unicode: true,
  );

  static bool isValidFormat(String trimmed) {
    if (trimmed.length < 3) return false;
    return _allowed.hasMatch(trimmed);
  }

  static String? validateForForm(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Username is required';
    }
    final t = value.trim();
    if (t.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (t.length > ProfileFieldLimits.maxUserNameLength) {
      return 'Username must be at most ${ProfileFieldLimits.maxUserNameLength} characters';
    }
    if (!isValidFormat(t)) {
      return 'Username can only contain letters, numbers and underscore';
    }
    return null;
  }
}
