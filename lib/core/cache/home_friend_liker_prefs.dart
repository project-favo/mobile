import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Ana sayfa ürün kartı arkadaş baloncukları: [HomePage] dispose / pushReplacement
/// sonrası da korunur; friends feed ilk sayfa sırası değişince kaybolmayı azaltır.
class HomeFriendLikerPrefs {
  HomeFriendLikerPrefs._();
  static final HomeFriendLikerPrefs instance = HomeFriendLikerPrefs._();

  static String _key(String viewerId) =>
      'home_friend_likers_v1_${viewerId.trim()}';

  Future<Map<String, List<String>>> loadMap(String viewerId) async {
    final id = viewerId.trim();
    if (id.isEmpty) return {};
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(id));
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return {};
      final out = <String, List<String>>{};
      for (final e in d.entries) {
        final pid = e.key.toString().trim();
        if (pid.isEmpty) continue;
        final v = e.value;
        if (v is! List) continue;
        final keys = v
            .map((x) => x.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (keys.isNotEmpty) {
          out[pid] = keys;
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveMap(String viewerId, Map<String, List<String>> map) async {
    final id = viewerId.trim();
    if (id.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    if (map.isEmpty) {
      await p.remove(_key(id));
      return;
    }
    final enc = <String, dynamic>{};
    for (final e in map.entries) {
      if (e.key.trim().isEmpty || e.value.isEmpty) continue;
      enc[e.key] = e.value;
    }
    if (enc.isEmpty) {
      await p.remove(_key(id));
      return;
    }
    await p.setString(_key(id), jsonEncode(enc));
  }

  Future<void> removeAllForViewer(String viewerId) async {
    final id = viewerId.trim();
    if (id.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.remove(_key(id));
  }
}
