import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Takip başlangıcı: bu andan **önce**ki aynı aktörün bildirimleri gösterilmez
/// (geçmiş review/like vb. sızıntısı).
class FollowNotificationHorizonPrefs {
  FollowNotificationHorizonPrefs._();
  static final FollowNotificationHorizonPrefs instance =
      FollowNotificationHorizonPrefs._();

  static String _storageKey(String viewerId) =>
      'notif_follow_horizon_v1_${viewerId.trim()}';

  Future<Map<String, String>> _readRaw(String viewerId) async {
    final id = viewerId.trim();
    if (id.isEmpty) return {};
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_storageKey(id));
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return {};
      return d.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeRaw(String viewerId, Map<String, String> map) async {
    final id = viewerId.trim();
    if (id.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    if (map.isEmpty) {
      await p.remove(_storageKey(id));
      return;
    }
    await p.setString(_storageKey(id), jsonEncode(map));
  }

  /// [follow] true: takip anı (UTC) kaydedilir; false: eşik silinir (yeniden takipte taze an).
  Future<void> applyFollowToggle({
    required String viewerId,
    required String followeeId,
    required bool nowFollowing,
  }) async {
    final v = viewerId.trim();
    final f = followeeId.trim();
    if (v.isEmpty || f.isEmpty || v == f) return;
    final map = await _readRaw(v);
    if (nowFollowing) {
      map[f] = DateTime.now().toUtc().toIso8601String();
    } else {
      map.remove(f);
    }
    await _writeRaw(v, map);
  }

  Future<Map<String, DateTime>> loadHorizonsUtc(String viewerId) async {
    final raw = await _readRaw(viewerId);
    final out = <String, DateTime>{};
    for (final e in raw.entries) {
      final t = DateTime.tryParse(e.value)?.toUtc();
      if (t != null) {
        out[e.key] = t;
      }
    }
    return out;
  }

  Future<void> removeAllForViewer(String viewerId) async {
    final id = viewerId.trim();
    if (id.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.remove(_storageKey(id));
  }
}
