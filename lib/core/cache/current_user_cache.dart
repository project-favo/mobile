import '../../features/auth/data/models/review_dto.dart';
import '../../features/auth/data/models/user_response_dto.dart';

/// Oturumdaki mevcut kullanıcının [id] / [userName] bilgisini tutar; [getMe] tamamlanmadan
/// önce review sahipliği (sil / şikayet) ekranlarında anında kullanılır.
class CurrentUserCache {
  CurrentUserCache._();
  static final CurrentUserCache instance = CurrentUserCache._();

  String? _userId;
  String? _userName;

  String? get userId => _userId;
  String? get userName => _userName;

  bool get hasUserId => _userId != null && _userId!.trim().isNotEmpty;

  void rememberFromDto(UserResponseDto u) {
    final id = u.id.trim();
    if (id.isEmpty) return;
    _userId = id;
    _userName = u.userName;
  }

  void clear() {
    _userId = null;
    _userName = null;
  }

  bool isMyUserId(String? ownerId) {
    if (!hasUserId) return false;
    final a = _userId!.trim();
    final b = (ownerId ?? '').trim();
    if (a.isEmpty || b.isEmpty) return false;
    return a == b;
  }

  /// Review listesinde [ownerId] ile eşleşen giriş yapan kullanıcının incelemesi mi?
  bool isMyReview(ReviewDto r) => isMyUserId(r.ownerId);
}
