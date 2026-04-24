import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcı bir ürüne review yazdığında: bu andan **önce**ki aynı ürün üzerindeki
/// başkalarının review bildirimleri gösterilmez (geçmiş sızıntısı).
class ProductReviewNotificationHorizonPrefs {
  ProductReviewNotificationHorizonPrefs._();
  static final ProductReviewNotificationHorizonPrefs instance =
      ProductReviewNotificationHorizonPrefs._();

  static String _storageKey(String viewerId) =>
      'notif_product_review_horizon_v1_${viewerId.trim()}';

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

  /// Review oluşturuldu veya güncellendi: [productId] için eşik şimdi (UTC).
  Future<void> applyReviewPosted({
    required String viewerId,
    required String productId,
  }) async {
    final v = viewerId.trim();
    final pid = productId.trim();
    if (v.isEmpty || pid.isEmpty) return;
    final map = await _readRaw(v);
    map[pid] = DateTime.now().toUtc().toIso8601String();
    await _writeRaw(v, map);
  }

  Future<Map<String, DateTime>> loadHorizonsUtc(String viewerId) async {
    final raw = await _readRaw(viewerId);
    final out = <String, DateTime>{};
    for (final e in raw.entries) {
      final t = DateTime.tryParse(e.value)?.toUtc();
      if (t != null) {
        out[e.key.trim()] = t;
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
