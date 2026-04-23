import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/models/user_response_dto.dart';

/// Sunucu kullanıcı adı büyük/küçük harf duyarsız tekil olduğunda, sadece görünüm için
/// (örn. `han` → `Han`) tercih edilen yazımı yerel olarak saklar.
class UserDisplayNamePrefs {
  UserDisplayNamePrefs._();
  static final UserDisplayNamePrefs instance = UserDisplayNamePrefs._();

  static String _key(String userId) => 'username_display_case_v1_$userId';

  Future<String?> readPreferredDisplay(String userId, String serverUserName) async {
    final id = userId.trim();
    if (id.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    final stored = p.getString(_key(id))?.trim();
    if (stored == null || stored.isEmpty) return null;
    if (stored.toLowerCase() != serverUserName.trim().toLowerCase()) {
      await p.remove(_key(id));
      return null;
    }
    return stored;
  }

  Future<void> writePreferredDisplay(String userId, String displayUserName) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(id), displayUserName.trim());
  }

  Future<void> clearForUserId(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.remove(_key(id));
  }

  /// Çıkışta tüm `username_display_case_v1_*` anahtarlarını kaldırır.
  Future<void> removeAllCaseDisplayKeys() async {
    final p = await SharedPreferences.getInstance();
    final prefix = 'username_display_case_v1_';
    for (final k in p.getKeys()) {
      if (k.startsWith(prefix)) {
        await p.remove(k);
      }
    }
  }

  /// [getMe] / [updateMe] sonrası — sunucu adı ile eşleşiyorsa yerel tercihi uygular.
  Future<UserResponseDto> mergeInto(UserResponseDto u) async {
    final id = u.id.trim();
    if (id.isEmpty) return u;
    final pref = await readPreferredDisplay(id, u.userName);
    if (pref == null || pref == u.userName) return u;
    return u.withUserName(pref);
  }
}
