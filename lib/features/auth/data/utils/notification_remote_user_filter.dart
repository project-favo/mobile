import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:favo_mobile/core/cache/current_user_cache.dart';
import 'package:favo_mobile/core/cache/follow_notification_horizon_prefs.dart';
import 'package:favo_mobile/core/cache/product_review_notification_horizon_prefs.dart';
import 'package:favo_mobile/core/utils/entity_active.dart';
import 'package:favo_mobile/core/utils/exceptions.dart';
import 'package:favo_mobile/core/utils/session_helper.dart';
import 'package:favo_mobile/features/activity/data/friends_feed_dto.dart';
import 'package:favo_mobile/features/auth/data/models/notification_dto.dart';
import 'package:favo_mobile/features/auth/data/repositories/product_repository.dart';
import 'package:favo_mobile/features/auth/data/repositories/review_repository.dart';
import 'package:favo_mobile/features/auth/data/services/auth_service.dart';

/// Ağ taşmasını önlemek: [chunkSize] kadar paralel, sonra sıradaki dilim.
Future<void> _forEachChunked<T>(
  Iterable<T> items,
  int chunkSize,
  Future<void> Function(T item) action,
) async {
  final list = items.toList();
  if (list.isEmpty) return;
  final n = chunkSize.clamp(1, 16);
  for (var i = 0; i < list.length; i += n) {
    final end = i + n > list.length ? list.length : i + n;
    await Future.wait(list.sublist(i, end).map(action));
  }
}

/// Takip başladıktan **önce**ki aynı aktör bildirimlerini gizle (geçmiş aktivite sızıntısı).
List<NotificationDto> _filterNotificationsByActorFollowHorizon(
  List<NotificationDto> list,
  Map<String, DateTime> followeeIdToHorizonUtc,
) {
  if (followeeIdToHorizonUtc.isEmpty) return list;
  return list.where((n) {
    final actorId = n.resolvedUserIdForVisibilityCheck;
    if (actorId == null || actorId <= 0) return true;
    final key = actorId.toString();
    final horizon = followeeIdToHorizonUtc[key];
    if (horizon == null) return true;
    final at = n.createdAt;
    if (at == null) return true;
    return !at.toUtc().isBefore(horizon);
  }).toList();
}

/// Kendi review’ımızdan önceki aynı ürün üzerindeki başkalarının review bildirimleri.
List<NotificationDto> _filterNotificationsByProductReviewHorizon(
  List<NotificationDto> list,
  Map<String, DateTime> productIdToHorizonUtc,
) {
  if (productIdToHorizonUtc.isEmpty) return list;
  return list.where((n) {
    if (!notificationTypeIsOthersProductReviewPost(n.type)) return true;
    final actorId = n.resolvedUserIdForVisibilityCheck;
    if (actorId != null &&
        actorId > 0 &&
        CurrentUserCache.instance.isMyUserId(actorId.toString())) {
      return true;
    }
    final pid = notificationProductIdKey(n)?.trim() ?? '';
    if (pid.isEmpty) return true;
    final horizon = productIdToHorizonUtc[pid];
    if (horizon == null) return true;
    final at = n.createdAt;
    if (at == null) return true;
    return !at.toUtc().isBefore(horizon);
  }).toList();
}

/// Arkadaş akışı: aynı ürün için review yazdığımız andan önceki review satırları.
Future<List<FriendsFeedItemDto>> filterFriendsFeedByProductReviewHorizon(
  List<FriendsFeedItemDto> items,
  String viewerId,
) async {
  final me = viewerId.trim();
  if (me.isEmpty) return items;
  final horizons =
      await ProductReviewNotificationHorizonPrefs.instance.loadHorizonsUtc(me);
  if (horizons.isEmpty) return items;
  return items
      .where((e) {
        final t = e.type.toUpperCase();
        if (!t.contains('REVIEW') || t.contains('LIKE')) return true;
        final aid = e.actorUserId.trim();
        if (aid.isNotEmpty && aid == me) return true;
        final pid = e.productId?.trim() ?? '';
        if (pid.isEmpty) return true;
        final h = horizons[pid];
        if (h == null) return true;
        final at = e.createdAt;
        if (at == null) return true;
        return !at.toUtc().isBefore(h);
      })
      .toList();
}

class _CacheEntry {
  _CacheEntry(this.listable, this.expires);
  final bool listable;
  final DateTime expires;
}

/// [GET /api/products/{id}] + [bypassCache]: bildirim satırındaki gömülü ürün bayrakları güncel olmayabilir.
final class RemoteNotificationProductListabilityCache {
  RemoteNotificationProductListabilityCache._();
  static final RemoteNotificationProductListabilityCache instance =
      RemoteNotificationProductListabilityCache._();

  static const Duration _ttlListable = Duration(minutes: 4);
  static const Duration _ttlUnlisted = Duration(seconds: 90);

  final Map<String, _CacheEntry> _byProductId = HashMap();

  void clear() => _byProductId.clear();

  void invalidateProduct(String productId) =>
      _byProductId.remove(productId.trim());

  /// `true` = satır kalsın (ürün vitrinde / erişilebilir).
  Future<bool> isProductListableForNotificationRow(
    ProductRepository repo,
    String productId, {
    String? firebaseIdToken,
  }) async {
    final pid = productId.trim();
    if (pid.isEmpty) return true;
    final now = DateTime.now();
    final e = _byProductId[pid];
    if (e != null && e.expires.isAfter(now)) {
      return e.listable;
    }
    try {
      final token =
          firebaseIdToken ?? await SessionHelper().ensureSession();
      final p = await repo.getProductById(
        pid,
        firebaseIdToken: token,
        bypassCache: false,
        includeRatingAndLike: false,
      );
      if (p.isUnavailableForStorefront) {
        _byProductId[pid] = _CacheEntry(false, now.add(_ttlUnlisted));
        return false;
      }
      _byProductId[pid] = _CacheEntry(true, now.add(_ttlListable));
      return true;
    } on ProductNotAvailableException {
      _byProductId[pid] = _CacheEntry(false, now.add(_ttlUnlisted));
      return false;
    } on DioException catch (e) {
      final c = e.response?.statusCode;
      if (c != null && c >= 400 && c < 500 && c != 429) {
        _byProductId[pid] = _CacheEntry(false, now.add(_ttlUnlisted));
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }
}

/// [GET /api/reviews/{id}]: bildirimde ürün id yoksa veya ürün GET’i eski “aktif” dönerse
/// review + ürün görünürlüğü tek kaynak olur.
final class RemoteNotificationReviewContextCache {
  RemoteNotificationReviewContextCache._();
  static final RemoteNotificationReviewContextCache instance =
      RemoteNotificationReviewContextCache._();

  static const Duration _ttlListable = Duration(minutes: 4);
  static const Duration _ttlBad = Duration(seconds: 90);

  final Map<String, _CacheEntry> _byReviewId = HashMap();

  void clear() => _byReviewId.clear();

  void invalidateReview(String reviewId) => _byReviewId.remove(reviewId.trim());

  /// `true` = satır kalsın.
  Future<bool> isReviewContextListableForNotificationRow(
    ReviewRepository repo,
    String reviewId, {
    String? firebaseIdToken,
  }) async {
    final rid = reviewId.trim();
    if (rid.isEmpty) return true;
    final now = DateTime.now();
    final e = _byReviewId[rid];
    if (e != null && e.expires.isAfter(now)) {
      return e.listable;
    }
    try {
      final token =
          firebaseIdToken ?? await SessionHelper().ensureSession();
      final review = await repo.getReviewById(rid, firebaseIdToken: token);
      final pid = review.productId.trim();
      if (pid.isNotEmpty) {
        final productOk =
            await RemoteNotificationProductListabilityCache.instance
                .isProductListableForNotificationRow(
          ProductRepository(),
          pid,
          firebaseIdToken: token,
        );
        if (!productOk) {
          _byReviewId[rid] = _CacheEntry(false, now.add(_ttlBad));
          return false;
        }
      }
      _byReviewId[rid] = _CacheEntry(true, now.add(_ttlListable));
      return true;
    } on ReviewNotAvailableException {
      _byReviewId[rid] = _CacheEntry(false, now.add(_ttlBad));
      return false;
    } on ProductNotAvailableException {
      _byReviewId[rid] = _CacheEntry(false, now.add(_ttlBad));
      return false;
    } on DioException catch (e) {
      final c = e.response?.statusCode;
      if (c != null && c >= 400 && c < 500 && c != 429) {
        _byReviewId[rid] = _CacheEntry(false, now.add(_ttlBad));
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }
}

/// [getUserById] / 404 önbelleği. [getUserById] dolu ve profil engelli değilse listable; yalnızca
/// `u == null` iken profil resmi 404 ile doğrulanır.
final class RemoteNotificationUserListabilityCache {
  RemoteNotificationUserListabilityCache._();
  static final RemoteNotificationUserListabilityCache instance =
      RemoteNotificationUserListabilityCache._();

  static const Duration _ttlListable = Duration(seconds: 45);
  static const Duration _ttlUnlisted = Duration(seconds: 60);
  static const Duration _ttlUnknown = Duration(seconds: 25);

  final Map<int, _CacheEntry> _byUserId = HashMap();

  void clear() => _byUserId.clear();

  void invalidateUser(int id) => _byUserId.remove(id);

  /// [getUserById] sonrası bu satırlar tekrar değerlendirilsin (tek yenileme).
  void invalidateForNotificationDtos(Iterable<NotificationDto> list) {
    for (final n in list) {
      final id = n.resolvedUserIdForVisibilityCheck;
      if (id != null && id > 0) invalidateUser(id);
    }
  }

  /// `true` = satır kalsın. [getUserById] yeterliyse resim istenmez; yalnızca `u == null` iken 404 kontrolü.
  Future<bool> isUserListableForNotificationRow(
    AuthService auth,
    int id,
  ) async {
    if (id <= 0) return true;
    final now = DateTime.now();
    final e = _byUserId[id];
    if (e != null && e.expires.isAfter(now)) {
      return e.listable;
    }
    try {
      final u = await auth.getUserById(id.toString());
      if (u != null && u.isProfileViewBlocked) {
        _byUserId[id] = _CacheEntry(false, now.add(_ttlUnlisted));
        return false;
      }
      if (u != null) {
        _byUserId[id] = _CacheEntry(true, now.add(_ttlListable));
        return true;
      }
      final imgOnly = await auth.fetchUserProfileImage(id.toString());
      if (imgOnly != null && imgOnly.isNotFound) {
        _byUserId[id] = _CacheEntry(false, now.add(_ttlUnlisted));
        return false;
      }
      _byUserId[id] = _CacheEntry(true, now.add(_ttlUnknown));
      return true;
    } on TargetUserNotAvailableException {
      _byUserId[id] = _CacheEntry(false, now.add(_ttlUnlisted));
      return false;
    } catch (_) {
      return true;
    }
  }
}

/// "liked your review" ama ürün/review kimliği çıkarılamıyorsa vitrin doğrulanamaz → gösterme.
List<NotificationDto> _dropLikedYourReviewWithoutAnchors(
  List<NotificationDto> list,
) {
  return list.where((n) {
    if (!notificationIsLikedYourReviewRow(n)) return true;
    final p = notificationProductIdKey(n)?.trim() ?? '';
    final r = notificationReviewIdKey(n)?.trim() ?? '';
    return p.isNotEmpty || r.isNotEmpty;
  }).toList();
}

/// Önce JSON/ürün filtresi, sonra deaktif/silinen kullanıcı = profilde açılamaz kuralı.
Future<List<NotificationDto>> filterNotificationsHidingUnlistedUsers(
  Iterable<NotificationDto> list,
  AuthService auth, {
  RemoteNotificationUserListabilityCache? cache,
}) async {
  final c = cache ?? RemoteNotificationUserListabilityCache.instance;
  final pre = list.where(isNotificationListEntryVisibleForRemoteList).toList();
  final batchToken = await SessionHelper().ensureSession();
  final ids = <int>{};
  for (final n in pre) {
    final id = n.resolvedUserIdForVisibilityCheck;
    if (id != null && id > 0) ids.add(id);
  }
  List<NotificationDto> pass1;
  if (ids.isEmpty) {
    pass1 = pre;
  } else {
    final bad = <int>{};
    await _forEachChunked(ids, 5, (id) async {
      if (!await c.isUserListableForNotificationRow(auth, id)) {
        bad.add(id);
      }
    });
    if (bad.isEmpty) {
      pass1 = pre;
    } else {
      pass1 = pre.where((n) {
        final id = n.resolvedUserIdForVisibilityCheck;
        if (id == null || id <= 0) return true;
        return !bad.contains(id);
      }).toList();
    }
  }

  List<NotificationDto> pass1b = pass1;
  final productIds = <String>{};
  for (final n in pass1) {
    final key = notificationProductIdKey(n)?.trim();
    if (key != null && key.isNotEmpty) {
      productIds.add(key);
    }
  }
  if (productIds.isNotEmpty) {
    final repo = ProductRepository();
    final badProducts = <String>{};
    await _forEachChunked(productIds, 5, (pid) async {
      if (!await RemoteNotificationProductListabilityCache.instance
          .isProductListableForNotificationRow(
        repo,
        pid,
        firebaseIdToken: batchToken,
      )) {
        badProducts.add(pid);
      }
    });
    if (badProducts.isNotEmpty) {
      pass1b = pass1.where((n) {
        final key = notificationProductIdKey(n)?.trim() ?? '';
        if (key.isEmpty) return true;
        return !badProducts.contains(key);
      }).toList();
    }
  }

  var pass1c = pass1b;
  final reviewIds = <String>{};
  for (final n in pass1b) {
    final r = notificationReviewIdKey(n)?.trim();
    if (r != null && r.isNotEmpty) {
      reviewIds.add(r);
    }
  }
  if (reviewIds.isNotEmpty) {
    final rRepo = ReviewRepository();
    final badReviews = <String>{};
    await _forEachChunked(reviewIds, 5, (rid) async {
      if (!await RemoteNotificationReviewContextCache.instance
          .isReviewContextListableForNotificationRow(
        rRepo,
        rid,
        firebaseIdToken: batchToken,
      )) {
        badReviews.add(rid);
      }
    });
    if (badReviews.isNotEmpty) {
      pass1c = pass1b.where((n) {
        final r = notificationReviewIdKey(n)?.trim() ?? '';
        if (r.isEmpty) return true;
        return !badReviews.contains(r);
      }).toList();
    }
  }

  final me = CurrentUserCache.instance.userId?.trim();
  if (me == null || me.isEmpty) {
    return _dropLikedYourReviewWithoutAnchors(pass1c);
  }
  final followHorizons =
      await FollowNotificationHorizonPrefs.instance.loadHorizonsUtc(me);
  var pass2 = _filterNotificationsByActorFollowHorizon(pass1c, followHorizons);
  final reviewHorizons =
      await ProductReviewNotificationHorizonPrefs.instance.loadHorizonsUtc(me);
  pass2 = _filterNotificationsByProductReviewHorizon(pass2, reviewHorizons);
  return _dropLikedYourReviewWithoutAnchors(pass2);
}

/// Arkadaş akışı: satırdaki [actorUserId] için aynı [getUserById] kuralı.
Future<List<FriendsFeedItemDto>> filterFriendsFeedHidingUnlistedActors(
  Iterable<FriendsFeedItemDto> items,
  AuthService auth, {
  RemoteNotificationUserListabilityCache? cache,
}) async {
  final c = cache ?? RemoteNotificationUserListabilityCache.instance;
  final batchToken = await SessionHelper().ensureSession();
  var pass = filterVisibleFriendsFeedItems(items);
  final ids = <int>{};
  for (final e in pass) {
    final id = int.tryParse(e.actorUserId.trim());
    if (id != null && id > 0) ids.add(id);
  }
  if (ids.isNotEmpty) {
    final bad = <int>{};
    await _forEachChunked(ids, 5, (id) async {
      if (!await c.isUserListableForNotificationRow(auth, id)) {
        bad.add(id);
      }
    });
    if (bad.isNotEmpty) {
      pass = pass.where((e) {
        final id = int.tryParse(e.actorUserId.trim());
        if (id == null || id <= 0) return true;
        return !bad.contains(id);
      }).toList();
    }
  }

  final productIds = <String>{};
  for (final e in pass) {
    final pid = e.productId?.trim() ?? '';
    if (pid.isNotEmpty) productIds.add(pid);
  }
  if (productIds.isEmpty) {
    // Ürün yoksa yine de review satırlarını kontrol et.
    final onlyReviewIds = <String>{};
    for (final e in pass) {
      final rid = e.reviewId?.trim() ?? '';
      if (rid.isNotEmpty) onlyReviewIds.add(rid);
    }
    if (onlyReviewIds.isEmpty) return pass;
    final rRepo = ReviewRepository();
    final badReviews = <String>{};
    await _forEachChunked(onlyReviewIds, 5, (rid) async {
      if (!await RemoteNotificationReviewContextCache.instance
          .isReviewContextListableForNotificationRow(
        rRepo,
        rid,
        firebaseIdToken: batchToken,
      )) {
        badReviews.add(rid);
      }
    });
    if (badReviews.isEmpty) return pass;
    return pass.where((e) {
      final rid = e.reviewId?.trim() ?? '';
      if (rid.isEmpty) return true;
      return !badReviews.contains(rid);
    }).toList();
  }
  final repo = ProductRepository();
  final badProducts = <String>{};
  await _forEachChunked(productIds, 5, (pid) async {
    if (!await RemoteNotificationProductListabilityCache.instance
        .isProductListableForNotificationRow(
      repo,
      pid,
      firebaseIdToken: batchToken,
    )) {
      badProducts.add(pid);
    }
  });
  if (badProducts.isNotEmpty) {
    pass = pass.where((e) {
      final pid = e.productId?.trim() ?? '';
      if (pid.isEmpty) return true;
      return !badProducts.contains(pid);
    }).toList();
  }

  final reviewIds = <String>{};
  for (final e in pass) {
    final rid = e.reviewId?.trim() ?? '';
    if (rid.isNotEmpty) {
      reviewIds.add(rid);
    }
  }
  if (reviewIds.isEmpty) return pass;
  final rRepo = ReviewRepository();
  final badReviews = <String>{};
  await _forEachChunked(reviewIds, 5, (rid) async {
    if (!await RemoteNotificationReviewContextCache.instance
        .isReviewContextListableForNotificationRow(
      rRepo,
      rid,
      firebaseIdToken: batchToken,
    )) {
      badReviews.add(rid);
    }
  });
  if (badReviews.isEmpty) return pass;
  return pass.where((e) {
    final rid = e.reviewId?.trim() ?? '';
    if (rid.isEmpty) return true;
    return !badReviews.contains(rid);
  }).toList();
}
