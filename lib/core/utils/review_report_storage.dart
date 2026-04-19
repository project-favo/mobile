import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Raporlanan review id’leri: önce **bellek** (anında), sonra SharedPreferences.
class ReviewReportStorage {
  ReviewReportStorage._();

  static String normalizeId(String id) => id.toString().trim();

  static String _key(String uid) => 'reported_review_ids_v1_$uid';

  static final Map<String, Set<String>> _memory = {};
  static final Set<String> _hydratedUids = {};

  static Set<String> _setFor(String uid) =>
      _memory.putIfAbsent(uid, () => <String>{});

  /// Oturum kapanınca bellek temizlenir; yeniden girişte prefs’ten dolar.
  static void clearMemory() {
    _memory.clear();
    _hydratedUids.clear();
  }

  static Future<void> hydrateForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    if (_hydratedUids.contains(uid)) return;
    final p = await SharedPreferences.getInstance();
    final fromDisk = p.getStringList(_key(uid)) ?? [];
    _setFor(uid).addAll(fromDisk.map(normalizeId));
    _hydratedUids.add(uid);
  }

  /// Bellekte kesin kayıt var mı (prefs beklemeden).
  static bool hasReportedSync(String reviewId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return false;
    final id = normalizeId(reviewId);
    if (id.isEmpty) return false;
    return _setFor(uid).contains(id);
  }

  static Future<bool> hasReported(String reviewId) async {
    await hydrateForCurrentUser();
    return hasReportedSync(reviewId);
  }

  static Future<void> markReported(String reviewId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    final id = normalizeId(reviewId);
    if (id.isEmpty) return;

    _setFor(uid).add(id);
    _hydratedUids.add(uid);

    final p = await SharedPreferences.getInstance();
    final key = _key(uid);
    final merged = {..._setFor(uid)};
    var list = merged.toList();
    if (list.length > 400) {
      list = list.sublist(list.length - 400);
    }
    await p.setStringList(key, list);
  }
}
