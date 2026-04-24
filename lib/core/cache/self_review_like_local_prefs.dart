import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/models/review_dto.dart';
import 'current_user_cache.dart';

/// Backend kendi yorumunu beğenmeyi reddettiğinde (ör. "cannot like your own review")
/// kullanıcıya beğeni UX'ini korumak için yerel overlay. Sunucu izin vermeye başlayınca
/// [isLikedByCurrentUser] true gelir ve boost sessizce temizlenir.
class SelfReviewLikeLocalPrefs {
  SelfReviewLikeLocalPrefs._();
  static final SelfReviewLikeLocalPrefs instance = SelfReviewLikeLocalPrefs._();

  static String _storageKey(String viewerId) =>
      'self_review_like_local_v1_${viewerId.trim()}';

  Future<Map<String, bool>> loadBoostMap(String viewerId) async {
    final id = viewerId.trim();
    if (id.isEmpty) return {};
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_storageKey(id));
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return {};
      final out = <String, bool>{};
      for (final e in d.entries) {
        final k = e.key.toString().trim();
        if (k.isEmpty) continue;
        final v = e.value;
        if (v == true || v == 1 || v.toString().toLowerCase() == 'true') {
          out[k] = true;
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMap(String viewerId, Map<String, bool> map) async {
    final id = viewerId.trim();
    if (id.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    if (map.isEmpty) {
      await p.remove(_storageKey(id));
      return;
    }
    await p.setString(_storageKey(id), jsonEncode(map));
  }

  Future<void> setBoost(String viewerId, String reviewId, bool boost) async {
    final rid = reviewId.trim();
    if (rid.isEmpty) return;
    final m = await loadBoostMap(viewerId);
    if (boost) {
      m[rid] = true;
    } else {
      m.remove(rid);
    }
    await _writeMap(viewerId, m);
  }

  Future<void> removeAllForViewer(String viewerId) async {
    final id = viewerId.trim();
    if (id.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.remove(_storageKey(id));
  }
}

/// Sunucu satırı + yerel boost → kart / detayda gösterilecek [ReviewDto].
class SelfReviewLikeDisplay {
  const SelfReviewLikeDisplay._();

  static ReviewDto mergeServerRowWithBoostMap(
    ReviewDto r,
    Map<String, bool> boosts,
  ) {
    if (!CurrentUserCache.instance.isMyReview(r)) return r;
    final boost = boosts[r.id] == true;
    if (!boost) return r;
    if (r.isLikedByCurrentUser) return r;
    return ReviewDto(
      id: r.id,
      title: r.title,
      description: r.description,
      isCollaborative: r.isCollaborative,
      rating: r.rating,
      createdAt: r.createdAt,
      productId: r.productId,
      productName: r.productName,
      ownerId: r.ownerId,
      ownerUserName: r.ownerUserName,
      ownerProfilePhotoUrl: r.ownerProfilePhotoUrl,
      mediaList: r.mediaList,
      likeCount: r.likeCount + 1,
      isLikedByCurrentUser: true,
      isProductNotListed: r.isProductNotListed,
      isReviewInactive: r.isReviewInactive,
    );
  }
}

bool interactionErrorLooksLikeCannotLikeOwnReview(Object e) {
  final s = e.toString().toLowerCase();
  if (s.contains('cannot like') && s.contains('own')) return true;
  if (s.contains("can't like") && s.contains('own')) return true;
  if (s.contains('can not like') && s.contains('own')) return true;
  if (s.contains('unable to like') && s.contains('own')) return true;
  if (s.contains('like your own')) return true;
  if (s.contains('own review')) return true;
  if (s.contains('kendi') && s.contains('beğen')) return true;
  if (s.contains('kendi') && s.contains('beg')) return true;
  return false;
}
